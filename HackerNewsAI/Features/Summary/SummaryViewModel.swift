// SummaryViewModel - HackerNewsAI

import Foundation
import LLM

@Observable
@MainActor
class SummaryViewModel {
    var summary: CatchUpSummary?
    var isLoading = false
    var error: Error?

    // Download progress (0.0 to 1.0), nil when not downloading
    var downloadProgress: Double?
    var isDownloadingModel: Bool { downloadProgress != nil && downloadProgress! < 1.0 }

    /// Live, in-progress summary text shown while streaming. Cleared on completion.
    var streamingText: String?

    /// When the on-device provider is selected and Apple Intelligence is
    /// unavailable, this holds the user-facing reason (rendered by
    /// `ModelUnavailableView` instead of attempting and failing generation).
    var unavailabilityReason: FoundationModelAvailability?

    private let service = SummaryService()
    private var streamTask: Task<Void, Never>?

    init() {
        setupProgressTracking()
    }

    private func setupProgressTracking() {
        Task { [service, weak self] in
            await service.setProgressCallback { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.downloadProgress = progress
                }
            }
        }
    }

    /// Generates the summary, streaming the result when possible.
    ///
    /// When the on-device provider is selected, Apple Intelligence availability
    /// is probed first; if it is unavailable we surface `unavailabilityReason`
    /// instead of kicking off a generation that would only fail.
    func generateSummary(forceRegenerate: Bool = false) async {
        // Cancel any in-flight stream.
        streamTask?.cancel()

        // Reset prior terminal state.
        unavailabilityReason = nil
        error = nil
        streamingText = nil

        // Availability gate for the on-device provider.
        let configuration = SettingsService.shared.llmConfiguration
        if configuration.provider == .onDevice {
            let availability = LLMGenerationService.shared.foundationModelAvailability()
            if !availability.isAvailable {
                unavailabilityReason = availability
                return
            }
        }

        isLoading = true
        downloadProgress = nil

        streamTask = Task { [service, forceRegenerate] in
            do {
                let stream = service.generateCatchUpSummaryStreaming(forceRegenerate: forceRegenerate)
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .partial(let partial):
                        self.streamingText = partial
                    case .complete(let summary):
                        self.summary = summary
                        self.streamingText = nil
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                }
            }
            self.isLoading = false
            self.downloadProgress = nil
            self.streamingText = nil
        }

        await streamTask?.value
    }

    func regenerate() async {
        await generateSummary(forceRegenerate: true)
    }

    func forceGenerateSummary() async {
        // Bypasses the all-caught-up / availability gating for an explicit
        // "generate anyway" from the user — but on-device still needs Apple
        // Intelligence to be available to do anything useful.
        let configuration = SettingsService.shared.llmConfiguration
        if configuration.provider == .onDevice {
            let availability = LLMGenerationService.shared.foundationModelAvailability()
            if !availability.isAvailable {
                unavailabilityReason = availability
                error = nil
                streamingText = nil
                return
            }
        }

        streamTask?.cancel()
        unavailabilityReason = nil
        error = nil
        streamingText = nil
        isLoading = true
        downloadProgress = nil

        streamTask = Task { [service] in
            do {
                let stream = service.generateCatchUpSummaryStreaming(
                    forceRegenerate: true,
                    bypassTimeCheck: true
                )
                for try await event in stream {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .partial(let partial):
                        self.streamingText = partial
                    case .complete(let summary):
                        self.summary = summary
                        self.streamingText = nil
                    }
                }
            } catch {
                if !Task.isCancelled {
                    self.error = error
                }
            }
            self.isLoading = false
            self.downloadProgress = nil
            self.streamingText = nil
        }

        await streamTask?.value
    }

    func markAsRead() async {
        await service.markAsRead()
    }
}
