// FoundationModelAvailability - LLM Module
// Copyright 2026

import Foundation

/// A Foundation-Models-free, UI-safe representation of Apple Intelligence
/// availability on this device.
///
/// `FoundationModelRuntime` maps `FoundationModels.SystemLanguageModel.availability`
/// into this type so the rest of the app (and this package) never imports
/// `FoundationModels` directly.
public enum FoundationModelAvailability: Sendable, Equatable {
    /// The on-device model is ready to use.
    case available
    /// The model is unavailable for a known reason.
    case unavailable(Reason)

    public enum Reason: Sendable, Equatable {
        /// The device does not meet Apple Intelligence hardware requirements.
        case deviceNotEligible
        /// Apple Intelligence is turned off in system settings.
        case appleIntelligenceNotEnabled
        /// The model is still downloading / warming up.
        case modelNotReady
        /// Any other (including future) unavailable state.
        case other(String)

        /// A user-facing explanation suitable for display in the UI.
        public var localizedDescription: String {
            switch self {
            case .deviceNotEligible:
                return "This device isn't eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off. Enable it in Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                return "The on-device model is still getting ready. Please try again in a moment."
            case .other(let detail):
                return "Apple Intelligence isn't available right now (\(detail))."
            }
        }
    }

    /// `true` when the model can be used right now.
    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    /// A user-facing explanation. Empty string when available.
    public var localizedDescription: String {
        switch self {
        case .available:
            return ""
        case .unavailable(let reason):
            return reason.localizedDescription
        }
    }
}
