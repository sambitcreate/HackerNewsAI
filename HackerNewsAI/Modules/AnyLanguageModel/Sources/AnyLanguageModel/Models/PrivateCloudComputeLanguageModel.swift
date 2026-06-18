#if canImport(FoundationModels)
import FoundationModels
#endif
import Foundation

#if compiler(>=6.4) && canImport(FoundationModels)

/// A language model that uses Private Cloud Compute (PCC).
@available(macOS 27.0, iOS 27.0, watchOS 27.0, tvOS 27.0, visionOS 27.0, *)
public actor PrivateCloudComputeLanguageModel: LanguageModel {
    public enum UnavailableReason: Sendable, Equatable {
        case deviceNotEligible
        case serviceUnavailable
        case other(String)
    }

    private let fmModel: FoundationModels.PrivateCloudComputeLanguageModel

    public init() {
        self.fmModel = FoundationModels.PrivateCloudComputeLanguageModel()
    }

    nonisolated public var availability: Availability<UnavailableReason> {
        switch fmModel.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return .unavailable(.other(String(describing: reason)))
        }
    }

    public var quotaUsage: String {
        return String(describing: fmModel.quotaUsage)
    }

    nonisolated public var contextSize: Int {
        return 32768
    }

    nonisolated public func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        let fmPrompt = FoundationModels.Prompt(prompt.description)
        let fmOptions = options.toFoundationModels()
        let fmSession = FoundationModels.LanguageModelSession(
            model: fmModel,
            tools: session.tools.toFoundationModels(),
            transcript: session.transcript.toFoundationModels(instructions: session.instructions)
        )

        if type == String.self {
            let fmResponse = try await fmSession.respond(to: fmPrompt, options: fmOptions)
            let generatedContent = GeneratedContent(fmResponse.content)
            return LanguageModelSession.Response(
                content: fmResponse.content as! Content,
                rawContent: generatedContent,
                transcriptEntries: []
            )
        } else {
            let schema = FoundationModels.GenerationSchema(type.generationSchema)
            let fmResponse = try await fmSession.respond(
                to: fmPrompt,
                schema: schema,
                includeSchemaInPrompt: includeSchemaInPrompt,
                options: fmOptions
            )
            let generatedContent = try GeneratedContent(fmResponse.content)
            let content = try type.init(generatedContent)
            return LanguageModelSession.Response(
                content: content,
                rawContent: generatedContent,
                transcriptEntries: []
            )
        }
    }

    nonisolated public func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        let fmPrompt = FoundationModels.Prompt(prompt.description)
        let fmOptions = options.toFoundationModels()
        let fmSession = FoundationModels.LanguageModelSession(
            model: fmModel,
            tools: session.tools.toFoundationModels(),
            transcript: session.transcript.toFoundationModels(instructions: session.instructions)
        )

        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { continuation in
            let streamingTask = _Concurrency.Task(priority: nil) {
                do {
                    if type == String.self {
                        let fmTextStream = fmSession.streamResponse(to: fmPrompt, options: fmOptions)
                        var accumulatedText = ""
                        for try await snapshot in fmTextStream {
                            accumulatedText += snapshot.content
                            let raw = GeneratedContent(accumulatedText)
                            continuation.yield(.init(content: accumulatedText as! Content.PartiallyGenerated, rawContent: raw))
                        }
                    } else {
                        let schema = FoundationModels.GenerationSchema(type.generationSchema)
                        let fmStream = fmSession.streamResponse(
                            to: fmPrompt,
                            schema: schema,
                            includeSchemaInPrompt: includeSchemaInPrompt,
                            options: fmOptions
                        )
                        for try await snapshot in fmStream {
                            let jsonString = snapshot.content.jsonString
                            let raw = try GeneratedContent(json: jsonString)
                            if let content = try? type.init(raw) {
                                continuation.yield(.init(content: content.asPartiallyGenerated(), rawContent: raw))
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in streamingTask.cancel() }
        }
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

#else

/// Fallback dummy implementation for Xcode 26 / older platforms.
public actor PrivateCloudComputeLanguageModel: LanguageModel {
    public enum UnavailableReason: Sendable, Equatable {
        case deviceNotEligible
        case serviceUnavailable
        case other(String)
    }

    public init() {}

    nonisolated public var availability: Availability<UnavailableReason> {
        return .unavailable(.serviceUnavailable)
    }

    public var quotaUsage: String {
        return "Quota information not available"
    }

    nonisolated public var contextSize: Int {
        return 8192
    }

    nonisolated public func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        throw NSError(domain: "PrivateCloudComputeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Private Cloud Compute is not available on this platform/OS."])
    }

    nonisolated public func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        var continuation: AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error>.Continuation!
        let stream = AsyncThrowingStream<LanguageModelSession.ResponseStream<Content>.Snapshot, any Error> { cont in
            continuation = cont
        }
        continuation.finish(throwing: NSError(domain: "PrivateCloudComputeError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Private Cloud Compute is not available on this platform/OS."]))
        return LanguageModelSession.ResponseStream(stream: stream)
    }
}

#endif
