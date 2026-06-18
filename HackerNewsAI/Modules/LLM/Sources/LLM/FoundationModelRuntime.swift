// FoundationModelRuntime - LLM Module
// Copyright 2026

import Foundation
/// Direct bridge to Apple's FoundationModels framework.
///
/// This is the *only* file in the LLM module that imports `FoundationModels`.
/// Every Foundation Models type is spelled with a `FoundationModels.` prefix
/// because the vendored `AnyLanguageModel` package redeclares colliding names
/// (`LanguageModelSession`, `SystemLanguageModel`, `GenerationOptions`).
/// Keeping the reference fully-qualified keeps the two worlds unambiguous.
import FoundationModels

/// A thin, direct adapter over Apple's on-device Foundation Models.
///
/// Responsibilities:
/// - Probe Apple Intelligence availability and surface it as `FoundationModelAvailability`.
/// - Build sessions with explicit `GenerationOptions` (deterministic sampling).
/// - Offer both one-shot (`respond`) and streaming (`stream`) generation.
/// - Expose the model's context budget so callers can size/truncate prompts.
///
/// Runtime/availability gates are resolved once per call and reused for the
/// duration of that call (no mid-request re-resolution).
public struct FoundationModelRuntime: Sendable {

    /// Shared runtime backed by the default system language model.
    public static let shared = FoundationModelRuntime()

    /// Creates a runtime for the default system language model.
    public init() {}

    // MARK: - Availability

    /// Probes the default system language model's availability without throwing.
    public func availability() -> FoundationModelAvailability {
        let model = FoundationModels.SystemLanguageModel.default
        return Self.translate(model.availability)
    }

    // MARK: - Context budget

    /// The model's context-window size in tokens, when knowable.
    ///
    /// `SystemLanguageModel.contextSize` is back-deployed to iOS/macOS 26
    /// (returns a conservative 4096 on older runtimes) and reflects the real
    /// budget on OS 27. Returns `nil` only if Foundation Models is unavailable.
    public func contextBudget() -> Int? {
        guard availability().isAvailable else { return nil }
        return FoundationModels.SystemLanguageModel.default.contextSize
    }

    /// Rough token estimate for a prompt string (~4 chars/token), used to decide
    /// whether a prompt risks overflowing the context window.
    public func tokenEstimate(for text: String) -> Int {
        max(1, text.count / 4)
    }

    /// Uses Foundation Models' tokenizer for a prompt when the runtime exposes it.
    ///
    /// Returns `nil` when Apple Intelligence is unavailable, the OS runtime does
    /// not expose token counting, or the tokenizer rejects the prompt.
    public func tokenCount(for text: String) async -> Int? {
        guard availability().isAvailable else { return nil }
        guard #available(macOS 26.4, iOS 26.4, *) else { return nil }

        let prompt = FoundationModels.Prompt(text)
        return try? await FoundationModels.SystemLanguageModel.default.tokenCount(for: prompt)
    }

    // MARK: - Generation

    /// Generates a complete response, throwing if Apple Intelligence is unavailable.
    ///
    /// - Parameter prompt: The user prompt string.
    /// - Parameter temperature: Sampling temperature. `0.0` (greedy/deterministic)
    ///   by default to keep summaries stable.
    public func respond(prompt: String, temperature: Double = 0.0) async throws -> String {
        try ensureAvailable()

        let options = makeSummaryOptions(temperature: temperature)
        let session = FoundationModels.LanguageModelSession(model: .default)
        let response = try await session.respond(to: prompt, options: options)
        return response.content
    }

    /// Streams incremental chunks of the response as they are produced.
    ///
    /// Each yielded `String` is the *accumulated* text so far (Foundation Models
    /// snapshots are cumulative for `String` content). The final yield is the
    /// complete response. Throws if Apple Intelligence is unavailable.
    ///
    /// - Parameter prompt: The user prompt string.
    /// - Parameter temperature: Sampling temperature. `0.0` (greedy) by default.
    public func stream(
        prompt: String,
        temperature: Double = 0.0
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try ensureAvailable()

                    let options = makeSummaryOptions(temperature: temperature)
                    let session = FoundationModels.LanguageModelSession(model: .default)
                    let responseStream: FoundationModels.LanguageModelSession.ResponseStream<String> =
                        session.streamResponse(to: prompt, options: options)

                    for try await snapshot in responseStream {
                        // String.PartiallyGenerated == String; snapshot.content is cumulative.
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internal

    /// Throws `LLMError.appleIntelligenceUnavailable` when the model can't be used.
    private func ensureAvailable() throws {
        switch availability() {
        case .available:
            return
        case .unavailable(let reason):
            throw LLMError.appleIntelligenceUnavailable(reason)
        }
    }

    /// Summary generation is text-only and does not use tools. On OS 27, make
    /// that policy explicit instead of relying only on an empty tools array.
    private func makeSummaryOptions(temperature: Double) -> FoundationModels.GenerationOptions {
        var options = FoundationModels.GenerationOptions(
            samplingMode: .greedy,
            temperature: temperature
        )

        if #available(macOS 27.0, iOS 27.0, *) {
            options.toolCallingMode = .disallowed
        }

        return options
    }

    /// Maps the Foundation Models availability enum into our UI-safe type.
    private static func translate(
        _ availability: FoundationModels.SystemLanguageModel.Availability
    ) -> FoundationModelAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable(.deviceNotEligible)
            case .appleIntelligenceNotEnabled:
                return .unavailable(.appleIntelligenceNotEnabled)
            case .modelNotReady:
                return .unavailable(.modelNotReady)
            @unknown default:
                return .unavailable(.other(String(describing: reason)))
            }
        }
    }
}
