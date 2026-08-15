import AppKit
import Agent
import SwiftUI

/// The one control that decides where reasoning happens, and therefore whether
/// anything leaves this machine at all.
///
/// It is a view of its own because two screens show it — the first-run explainer
/// and settings — and a second copy is how the wording, the download offer and
/// the storage key drift apart. The reader who chose "On this Mac" in one place
/// and sees "OpenAI" in the other has been told two things about their own
/// document, and has no way to know which one the app believes.
///
/// It binds `Tier.storageKey` directly rather than taking a `Binding`, because
/// the preference *is* the shared state: `ReaderScreen` observes the same key
/// and calls `ReaderModel.honour` when it changes, so a change made here takes
/// effect in the reader without this view knowing the reader exists.
struct TierPicker: View {
    @AppStorage(OnboardingScreen.Tier.storageKey)
    private var tier = OnboardingScreen.Tier.preferred

    /// Asked once and again every time the app comes back to the front.
    /// "Download now" sends the user to System Settings, so the trip back is
    /// exactly when the answer has changed — a value read straight in `body`
    /// would leave the button offering a download that has already happened.
    @State private var localModelReady = localModelAvailable()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model").kicker(11, tracking: 1.1)

            // A plain menu `Picker`. The rest of this app draws its own controls
            // because the design has no stock equivalent; a dropdown does, and
            // the stock one already handles keyboard, VoiceOver and the menu
            // placement.
            Picker("Model", selection: $tier) {
                ForEach(OnboardingScreen.Tier.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(Ink.accent)
            .frame(width: 190)

            Text(tier.detail)
                .font(.body(12)).foregroundStyle(Ink.neutral600)
                .fixedSize(horizontal: false, vertical: true)

            // Only when macOS has not put the on-device model here yet. Offering
            // it unconditionally would be this screen's first false statement.
            if OnboardingScreen.needsDownload(tier, modelReady: localModelReady) {
                Button(action: openSystemSettings) {
                    Text("Download now")
                        .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(Ink.accent700)
                        .overlay(Rectangle().stroke(Ink.accent400, lineWidth: 1))
                }
                .buttonStyle(.flat)
                .help("Apple Intelligence downloads the model. Opens System Settings.")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { localModelReady = localModelAvailable() }
        }
    }

    /// ponytail: the top of System Settings, not the Apple Intelligence pane.
    /// The per-pane URL is an undocumented bundle id that has moved between
    /// releases, and landing on the wrong pane is worse than landing on the
    /// front page. Deep-link it when there is a documented anchor to use.
    private func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:") else { return }
        NSWorkspace.shared.open(url)
    }
}
