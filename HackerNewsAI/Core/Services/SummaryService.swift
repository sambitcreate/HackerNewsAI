// SummaryService - HackerNewsAI
// Copyright 2026

import Foundation
import LLM

actor SummaryService {
    private let hnService: HackerNewsService
    private let lastVisitService: LastVisitService
    private let llmService: LLMGenerationService
    private var cachedSummary: CatchUpSummary?

    // Minimum time before generating a new summary (30 minutes).
    // `nonisolated` (immutable) so it can be read from the streaming Task.
    private nonisolated let minimumTimeBetweenSummaries: TimeInterval = 30 * 60

    init(
        hnService: HackerNewsService = HackerNewsService(),
        lastVisitService: LastVisitService = LastVisitService(),
        llmService: LLMGenerationService = .shared
    ) {
        self.hnService = hnService
        self.lastVisitService = lastVisitService
        self.llmService = llmService
    }

    func setProgressCallback(_ callback: @escaping @Sendable (Double) -> Void) async {
        await llmService.setProgressCallback(callback)
    }

    func generateCatchUpSummary(forceRegenerate: Bool = false, bypassTimeCheck: Bool = false) async throws -> CatchUpSummary {
        // Return cached summary if available and recent (within 5 minutes)
        if !forceRegenerate, let cached = cachedSummary,
           Date().timeIntervalSince(cached.generatedAt) < 300 {
            return cached
        }

        let lastVisit = await lastVisitService.getLastVisit()
        let timeSinceDescription = await lastVisitService.formattedTimeSinceLastVisit()

        // Check if user visited recently - if so, they're "all caught up"
        if !bypassTimeCheck, let lastVisit = lastVisit {
            let timeSinceLastVisit = Date().timeIntervalSince(lastVisit)

            if timeSinceLastVisit < minimumTimeBetweenSummaries {
                let summary = CatchUpSummary.allCaughtUp(
                    lastVisit: lastVisit,
                    timeSince: timeSinceDescription
                )
                cachedSummary = summary
                return summary
            }
        }

        // Fetch stories since last visit
        let stories = try await hnService.fetchStoriesSince(lastVisit, limit: 50)

        guard !stories.isEmpty else {
            throw SummaryError.noStoriesAvailable
        }

        // Determine if these are new stories or just current top
        let hasNewStories = lastVisit == nil || stories.contains { $0.postedDate > lastVisit! }

        // Build the prompt, shrinking the story list if the on-device context
        // budget would be exceeded (so we never overflow the model window).
        let configuration = await SettingsService.shared.llmConfiguration
        let maxStories = await resolveMaxStories(
            stories: stories,
            configuration: configuration,
            lastVisit: lastVisit,
            timeSinceDescription: timeSinceDescription,
            hasNewStories: hasNewStories
        )
        let prompt = buildPrompt(
            from: stories,
            lastVisit: lastVisit,
            timeSinceDescription: timeSinceDescription,
            hasNewStories: hasNewStories,
            maxStories: maxStories
        )

        // Generate summary using LLM module
        let responseText = try await llmService.generate(prompt: prompt, configuration: configuration)

        let summary = CatchUpSummary(
            summary: responseText,
            storyCount: stories.count,
            lastVisit: lastVisit,
            timeSinceLastVisit: timeSinceDescription,
            hasNewStories: hasNewStories,
            isAllCaughtUp: false,
            generatedAt: Date(),
            stories: stories
        )

        cachedSummary = summary
        return summary
    }

    /// Streams a catch-up summary as it is generated.
    ///
    /// - Yields `.partial(String)` with the raw, in-progress summary text.
    /// - Finishes with `.complete(CatchUpSummary)` once generation is done.
    ///
    /// All-caught-up and recently-cached states are delivered as a terminal
    /// `.complete` (never as a thrown error), so the UI can render them the
    /// same way as a freshly generated summary.
    ///
    /// On-device Apple Intelligence streams natively; MLX streams token-by-token;
    /// Anthropic is delivered as a single partial before completion.
    /// `nonisolated`: returns a stream synchronously and performs all actor
    /// interactions via `await` hops inside the stream's Task.
    nonisolated func generateCatchUpSummaryStreaming(
        forceRegenerate: Bool = false,
        bypassTimeCheck: Bool = false
    ) -> AsyncThrowingStream<SummaryStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: SummaryError.noStoriesAvailable)
                    return
                }
                do {
                    // Return cached summary if available and recent (within 5 minutes)
                    if !forceRegenerate, let cached = await self.cachedSummary,
                       Date().timeIntervalSince(cached.generatedAt) < 300 {
                        continuation.yield(.complete(cached))
                        continuation.finish()
                        return
                    }

                    let lastVisit = await self.lastVisitService.getLastVisit()
                    let timeSinceDescription = await self.lastVisitService.formattedTimeSinceLastVisit()

                    // All-caught-up state -> terminal complete, not an error.
                    if !bypassTimeCheck, let lastVisit {
                        let timeSinceLastVisit = Date().timeIntervalSince(lastVisit)
                        if timeSinceLastVisit < self.minimumTimeBetweenSummaries {
                            let summary = CatchUpSummary.allCaughtUp(
                                lastVisit: lastVisit,
                                timeSince: timeSinceDescription
                            )
                            await self.setCachedSummary(summary)
                            continuation.yield(.complete(summary))
                            continuation.finish()
                            return
                        }
                    }

                    let stories = try await self.hnService.fetchStoriesSince(lastVisit, limit: 50)
                    guard !stories.isEmpty else {
                        continuation.finish(throwing: SummaryError.noStoriesAvailable)
                        return
                    }
                    let hasNewStories = lastVisit == nil || stories.contains { $0.postedDate > lastVisit! }

                    let configuration = await SettingsService.shared.llmConfiguration
                    let maxStories = await self.resolveMaxStories(
                        stories: stories,
                        configuration: configuration,
                        lastVisit: lastVisit,
                        timeSinceDescription: timeSinceDescription,
                        hasNewStories: hasNewStories
                    )
                    let prompt = self.buildPrompt(
                        from: stories,
                        lastVisit: lastVisit,
                        timeSinceDescription: timeSinceDescription,
                        hasNewStories: hasNewStories,
                        maxStories: maxStories
                    )

                    let stream = self.llmService.generateStream(prompt: prompt, configuration: configuration)
                    var finalText = ""
                    for try await event in stream {
                        switch event {
                        case .partial(let partial):
                            continuation.yield(.partial(partial))
                        case .complete(let complete):
                            finalText = complete
                        }
                    }

                    let summary = CatchUpSummary(
                        summary: finalText,
                        storyCount: stories.count,
                        lastVisit: lastVisit,
                        timeSinceLastVisit: timeSinceDescription,
                        hasNewStories: hasNewStories,
                        isAllCaughtUp: false,
                        generatedAt: Date(),
                        stories: stories
                    )
                    await self.setCachedSummary(summary)
                    continuation.yield(.complete(summary))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Actor-isolated setter for `cachedSummary`, callable from the streaming Task.
    private func setCachedSummary(_ summary: CatchUpSummary?) {
        cachedSummary = summary
    }

    func markAsRead() async {
        await lastVisitService.updateLastVisit()
        cachedSummary = nil
    }

    func clearCache() {
        cachedSummary = nil
    }

    // MARK: - Streaming / budget helpers

    /// Decides how many stories fit in the prompt without overflowing the
    /// model's context window. For the on-device provider we use the real
    /// Foundation Models context budget; otherwise we keep the default of 30.
    private nonisolated func resolveMaxStories(
        stories: [HNStory],
        configuration: LLMConfiguration,
        lastVisit: Date?,
        timeSinceDescription: String,
        hasNewStories: Bool
    ) async -> Int {
        guard configuration.provider == .onDevice else { return 30 }

        let budget = LLMGenerationService.shared.foundationModelBudget()
        guard let budget else { return 30 }

        // Estimate the full prompt at 30 stories; if it fits, keep 30.
        // Otherwise shrink so the estimated prompt stays below ~70% of the
        // budget, leaving room for the model's response.
        let fullPrompt = buildPrompt(
            from: stories,
            lastVisit: lastVisit,
            timeSinceDescription: timeSinceDescription,
            hasNewStories: hasNewStories,
            maxStories: 30
        )
        let fullEstimate =
            await LLMGenerationService.shared.foundationModelTokenCount(for: fullPrompt)
            ?? LLMGenerationService.shared.tokenEstimate(for: fullPrompt)
        let safeBudget = Int(Double(budget) * 0.7)

        guard fullEstimate > safeBudget else { return 30 }

        // Linear scale-down based on per-story token weight.
        let perStory = max(1, fullEstimate / max(1, min(30, stories.count)))
        let allowed = max(3, safeBudget / perStory)
        return min(allowed, 30)
    }

    private nonisolated func buildPrompt(
        from stories: [HNStory],
        lastVisit: Date?,
        timeSinceDescription: String,
        hasNewStories: Bool,
        maxStories: Int = 30
    ) -> String {
        let contextIntro: String
        if lastVisit == nil {
            contextIntro = "This is the user's first time using the app. Give them a warm welcome and summarize what's currently trending on Hacker News."
        } else if hasNewStories {
            contextIntro = "The user last checked Hacker News \(timeSinceDescription). Summarize what they missed."
        } else {
            contextIntro = "The user last checked Hacker News \(timeSinceDescription). There are no major new stories since then, but here's what's currently trending. Let them know nothing big happened but share what's popular right now."
        }

        var prompt = """
        You are a helpful tech news assistant. \(contextIntro)

        Current top Hacker News stories:

        """

        let limit = max(1, min(maxStories, 30))
        for (index, story) in stories.prefix(limit).enumerated() {
            let domain = story.domain ?? "self"
            let timeAgo = story.relativeTime
            let url = story.url ?? "https://news.ycombinator.com/item?id=\(story.id)"
            prompt += "\(index + 1). [Score: \(story.score), \(timeAgo)] \"\(story.title)\" URL: \(url) (\(domain))\n"
        }

        prompt += """

        Provide a concise catch-up summary:
        - Start with a brief greeting acknowledging the time away (e.g., "Since you've been away..." or "Welcome! Here's what's trending...")
        - List the 3-5 most important/interesting things happening
        - Use bullet points with brief explanations
        - Focus on: major announcements, trending discussions, notable launches
        - Keep it conversational and scannable
        - IMPORTANT: When mentioning story titles, format them as markdown links like this: [Story Title](URL)
        """

        return prompt
    }
}

enum SummaryError: LocalizedError {
    case noStoriesAvailable

    var errorDescription: String? {
        switch self {
        case .noStoriesAvailable:
            return "No stories available at the moment."
        }
    }
}

/// Incremental events emitted by ``SummaryService/generateCatchUpSummaryStreaming(forceRegenerate:bypassTimeCheck:)``.
enum SummaryStreamEvent: Sendable {
    /// Raw, in-progress summary text (unfiltered).
    case partial(String)
    /// Final summary. Always the last event before the stream finishes.
    /// Also used to deliver all-caught-up and recently-cached states.
    case complete(CatchUpSummary)
}
