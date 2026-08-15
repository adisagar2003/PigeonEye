import SwiftUI

/// Settings — ⌘, and the app menu, where a Mac user looks for a preference.
///
/// **It exists because the tier was a one-way door.** The picker shipped on the
/// last card of the first-run explainer, and that deck never renders again once
/// `onboardingSeen` is set, so the choice deciding whether documents leave this
/// machine could be made exactly once and never revisited. A reader who picked
/// OpenAI to try it had no way back short of editing a plist, and one who picked
/// "On this Mac" could not turn the cloud leg on when they wanted it.
///
/// Deliberately one control. This is not a preferences dump — every other knob
/// in this app is a measured constant in `Contracts.Limits` or `Thresholds`, and
/// `project-overview.md` §3.1 says the confidence story is told in the ring and
/// its tooltip rather than in settings. What belongs here is the decision the
/// *reader* owns, and today that is one decision.
public struct SettingsScreen: View {
    /// What the pane offers, and the assertion that it is everything. A tier
    /// pickable at first run but absent here would be a one-way door again, for
    /// that tier only — the failure this screen was added to close.
    static let tiers = OnboardingScreen.Tier.allCases

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where reasoning happens")
                    .font(.heading(16)).tracking(0.3)
                // Said here rather than left to the picker's per-tier detail,
                // because the reader who opens this pane is asking a question
                // about their own privacy and deserves the answer above the
                // control, not underneath it.
                Text("""
                     Rendering and reading a document always happen on this Mac. \
                     This decides who answers questions about it, and it is the \
                     only thing that can send text off the machine.
                     """)
                    .font(.body(12)).foregroundStyle(Ink.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Ink.divider).frame(height: 1)

            TierPicker()

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
        .background(Ink.bg)
        .foregroundStyle(Ink.text)
    }
}
