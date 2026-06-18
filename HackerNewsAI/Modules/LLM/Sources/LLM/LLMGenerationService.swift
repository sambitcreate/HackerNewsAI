// LLMGenerationService - LLM Module
// Copyright 2026

import Foundation
// AnyLanguageModel powers the Anthropic backend (`AnthropicLanguageModel` + its
// `LanguageModelSession`). The on-device path does NOT use it; it goes through
// `FoundationModelRuntime`, which talks to FoundationModels directly.
import AnyLanguageModel
#if os(macOS) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLX)
import MLXLLM
import MLXLMCommon
import MLX
#endif

/// Errors that can occur during LLM generation
public enum LLMError: LocalizedError {
    case apiKeyMissing
    case foundationModelsUnavailable
    case appleIntelligenceUnavailable(FoundationModelAvailability.Reason)
    case mlxUnavailable

    public var errorDescription: String? {
        switch self {
        case .apiKeyMissing:
            return "Anthropic API key is not configured. Please add it in Settings."
        case .foundationModelsUnavailable:
            return "Foundation Models require macOS 26.0 or iOS 26.0."
        case .appleIntelligenceUnavailable(let reason):
            return reason.localizedDescription
        case .mlxUnavailable:
            return "MLX local models are only available in macOS builds."
        }
    }
}

/// Internal sentinel for stream cancellation when the service is released mid-stream.
private enum LLMErrorGenerationStreamFailure: Error {
    case cancelled
}

/// Incremental events emitted by ``LLMGenerationService/generateStream(prompt:configuration:)``.
public enum GenerationStreamEvent: Sendable {
    /// Partial raw (unfiltered) text accumulated so far.
    case partial(String)
    /// Final, filtered text. Always the last event before the stream finishes.
    case complete(String)
}

/// Service for generating text using various LLM providers
public actor LLMGenerationService {
    /// Shared instance
    public static let shared = LLMGenerationService()

#if os(macOS) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLX)
    // Cache for MLX model containers
    private var mlxModelCache: [String: ModelContainer] = [:]
#endif

    // Progress callback for model downloads
    private var onDownloadProgress: (@Sendable (Double) -> Void)?

    public init() {}

    /// Set callback for download progress updates
    public func setProgressCallback(_ callback: @escaping @Sendable (Double) -> Void) {
        onDownloadProgress = callback
    }

    /// Generate a response using the configured LLM
    public func generate(prompt: String, configuration: LLMConfiguration) async throws -> String {
        let rawResponse: String

        switch configuration.provider {
        case .onDevice:
            rawResponse = try await generateWithFoundationModel(prompt: prompt)
        case .mlx:
            rawResponse = try await generateWithMLX(prompt: prompt, modelId: configuration.mlxModelId)
        case .anthropic:
            rawResponse = try await generateWithAnthropic(prompt: prompt, apiKey: configuration.anthropicAPIKey)
        }

        return LLMResponseFilter.filter(rawResponse)
    }

    /// Stream a response from the configured LLM.
    ///
    /// - Yields `.partial(String)` with the raw (unfiltered) accumulated text as
    ///   it grows. The on-device backend streams natively; MLX streams from its
    ///   own generator; Anthropic is fetched in one shot then emitted as a
    ///   single partial (it has no native stream in this app).
    /// - Finishes with `.complete(String)` carrying the *filtered* final text.
    ///
    /// Partial text is intentionally unfiltered: `LLMResponseFilter` strips
    /// whole-document structures (thinking tags / outer XML wrappers) that are
    /// only meaningful on complete output, so filtering is deferred to completion.
    public nonisolated func generateStream(
        prompt: String,
        configuration: LLMConfiguration
    ) -> AsyncThrowingStream<GenerationStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var accumulated = ""
                    switch configuration.provider {
                    case .onDevice:
                        guard #available(macOS 26.0, iOS 26.0, *) else {
                            throw LLMError.foundationModelsUnavailable
                        }
                        for try await chunk in FoundationModelRuntime.shared.stream(prompt: prompt) {
                            accumulated = chunk
                            continuation.yield(.partial(accumulated))
                        }
                    case .mlx:
                        for try await chunk in self.streamMLX(prompt: prompt, modelId: configuration.mlxModelId) {
                            accumulated += chunk
                            continuation.yield(.partial(accumulated))
                        }
                    case .anthropic:
                        // No native streaming wired for Anthropic; emit once.
                        let full = try await self.generateWithAnthropic(
                            prompt: prompt,
                            apiKey: configuration.anthropicAPIKey
                        )
                        accumulated = full
                        continuation.yield(.partial(accumulated))
                    }
                    continuation.yield(.complete(LLMResponseFilter.filter(accumulated)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Foundation Models (direct)

    /// Probes Apple Intelligence availability for the on-device provider.
    public nonisolated func foundationModelAvailability() -> FoundationModelAvailability {
        if #available(macOS 26.0, iOS 26.0, *) {
            return FoundationModelRuntime.shared.availability()
        } else {
            return .unavailable(.other("requires macOS 26.0 or iOS 26.0"))
        }
    }

    /// The on-device model's context-window size in tokens, when knowable.
    /// Returns `nil` if Foundation Models is unavailable. Callers use this to
    /// size/truncate prompts before generation.
    public nonisolated func foundationModelBudget() -> Int? {
        guard #available(macOS 26.0, iOS 26.0, *) else { return nil }
        return FoundationModelRuntime.shared.contextBudget()
    }

    /// Rough token estimate for a string (~4 chars/token), used for prompt
    /// budgeting against the context window.
    public nonisolated func tokenEstimate(for text: String) -> Int {
        FoundationModelRuntime.shared.tokenEstimate(for: text)
    }

    /// Token count from the Foundation Models runtime when available.
    /// Falls back to `nil` instead of throwing so callers can keep their
    /// existing rough-estimate path.
    public nonisolated func foundationModelTokenCount(for text: String) async -> Int? {
        guard #available(macOS 26.4, iOS 26.4, *) else { return nil }
        return await FoundationModelRuntime.shared.tokenCount(for: text)
    }

    private func generateWithFoundationModel(prompt: String) async throws -> String {
        guard #available(macOS 26.0, iOS 26.0, *) else {
            throw LLMError.foundationModelsUnavailable
        }
        // Availability is re-checked inside `respond`; this throws a typed
        // `LLMError.appleIntelligenceUnavailable` when not ready.
        return try await FoundationModelRuntime.shared.respond(prompt: prompt)
    }

    // MARK: - Anthropic

    private func generateWithAnthropic(prompt: String, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw LLMError.apiKeyMissing
        }
        let model = AnthropicLanguageModel(
            apiKey: apiKey,
            model: "claude-sonnet-4-6"
        )
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: prompt)
        return response.content
    }

    // MARK: - MLX

#if os(macOS) && canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLX)
    private func generateWithMLX(prompt: String, modelId: String) async throws -> String {
        let container = try await loadMLXModel(modelId: modelId)

        var responseText = ""

        // Create input inside perform to avoid Sendable issues
        let stream = try await container.perform { (context: ModelContext) in
            let userInput = UserInput(
                chat: [Chat.Message(role: .user, content: prompt)]
            )
            let input = try await context.processor.prepare(input: userInput)
            let parameters = GenerateParameters(temperature: 0.7)
            return try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
        }

        for await generation in stream {
            switch generation {
            case .chunk(let chunk):
                responseText += chunk
            case .info:
                break
            case .toolCall:
                break
            }
        }

        return responseText
    }

    /// Streams MLX generation chunks (text deltas only).
    ///
    /// `nonisolated` so it can be kicked off from `generateStream`'s detached
    /// Task; the model-load (which mutates the cache) still hops to the actor.
    private nonisolated func streamMLX(prompt: String, modelId: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let container = try await self.loadMLXModel(modelId: modelId)
                    let stream = try await container.perform { (context: ModelContext) in
                        let userInput = UserInput(
                            chat: [Chat.Message(role: .user, content: prompt)]
                        )
                        let input = try await context.processor.prepare(input: userInput)
                        let parameters = GenerateParameters(temperature: 0.7)
                        return try MLXLMCommon.generate(input: input, parameters: parameters, context: context)
                    }
                    for await generation in stream {
                        switch generation {
                        case .chunk(let chunk):
                            continuation.yield(chunk)
                        case .info:
                            break
                        case .toolCall:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func loadMLXModel(modelId: String) async throws -> ModelContainer {
        if let cached = mlxModelCache[modelId] {
            print("[MLX] Using cached model: \(modelId)")
            return cached
        }

        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        print("[MLX] Cache directory: \(cacheDir?.path ?? "unknown")")
        print("[MLX] HuggingFace models typically stored in: ~/.cache/huggingface/hub/")
        print("[MLX] Loading model: \(modelId)")

        Memory.cacheLimit = 20 * 1024 * 1024

        let configuration = getModelConfiguration(for: modelId)
        print("[MLX] Using configuration: \(configuration)")

        let progressCallback = onDownloadProgress

        let container = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { progress in
            progressCallback?(progress.fractionCompleted)
        }

        progressCallback?(1.0)

        mlxModelCache[modelId] = container

        return container
    }

    private func getModelConfiguration(for modelId: String) -> ModelConfiguration {
        switch modelId {
        case "mlx-community/Qwen3-0.6B-4bit":
            return LLMRegistry.qwen3_0_6b_4bit
        case "mlx-community/Qwen3-4B-4bit":
            return LLMRegistry.qwen3_4b_4bit
        case "mlx-community/Llama-3.2-3B-Instruct-4bit":
            return LLMRegistry.llama3_2_3B_4bit
        default:
            return LLMRegistry.qwen3_0_6b_4bit
        }
    }
#else
    private func generateWithMLX(prompt: String, modelId: String) async throws -> String {
        throw LLMError.mlxUnavailable
    }

    private nonisolated func streamMLX(prompt: String, modelId: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMError.mlxUnavailable)
        }
    }
#endif
}
