// ModelUnavailableView - HackerNewsAI

import SwiftUI
import LLM

/// Shown when the on-device provider is selected but Apple Intelligence is not
/// available (device not eligible, Apple Intelligence off, or model not ready).
///
/// Replaces the generic error view for this specific, recoverable state and
/// points the user at Settings (to enable Apple Intelligence or switch provider).
struct ModelUnavailableView: View {
    let availability: FoundationModelAvailability
    /// Opens the system settings URL. Injectable for previews/testing.
    var openSettings: () -> Void = {
        #if os(iOS)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    var body: some View {
        ContentUnavailableView {
            Label("Apple Intelligence Unavailable", systemImage: "cpu")
        } description: {
            Text(availability.localizedDescription)
        } actions: {
            VStack(spacing: 8) {
                Button {
                    openSettings()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)

                #if os(macOS)
                Text("Or switch to the Claude (Anthropic) or MLX provider in app Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #else
                Text("Or switch to the Claude (Anthropic) provider in app Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                #endif
            }
        }
    }
}

#Preview {
    ModelUnavailableView(availability: .unavailable(.appleIntelligenceNotEnabled))
}
