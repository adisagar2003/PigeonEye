import AppKit
import FoundationModels
import SwiftUI

// The first-run explainer. Four cards, stepped through by hand, then never
// shown again. Every claim here is one F1 actually keeps — there is no Gate
// layer in the package, so "nothing leaves this machine" is true by
// construction rather than by promise (context/features/01-read-it-locally.md
// §3). When a later feature adds egress, the card that says so changes with it.

public struct OnboardingScreen: View {
    struct Card {
        let kicker: String
        let title: String
        let detail: String
        /// The one card that carries a control rather than only prose. Named on
        /// the card so adding a fifth cannot silently move the picker onto it.
        var picksTier = false
    }

    /// Which tier does the reasoning — `architecture.md` §6, Boundary C, and the
    /// row in §5 that already decided "cloud for the demo, local where hardware
    /// allows". Recorded at first run and read when F5 ships the egress
    /// function; **today it sends nothing either way**, because there is no Gate
    /// layer in the package — `scripts/layers.sh` still reports "no egress
    /// outside Gate", and this file is not allowed to be the exception.
    ///
    /// ponytail: lives in UI because UI is the only layer that has an opinion
    /// about it. It moves down to `Contracts` the moment the Gate reads it.
    public enum Tier: String, CaseIterable, Identifiable, Sendable {
        case openAI
        case local

        public var id: String { rawValue }

        /// The default, per §5: the cloud leg is what the demo runs on.
        public static let preferred = Tier.openAI

        public var title: String {
            switch self {
            case .openAI: "OpenAI"
            case .local: "On this Mac"
            }
        }

        public var detail: String {
            switch self {
            case .openAI:
                "Crops and transcript text leave the machine, and only inside the "
                    + "consent you give when you import a document."
            case .local:
                "Apple's on-device model. Nothing leaves, and there is no key to supply."
            }
        }
    }

    /// The one branch here worth a test: only the local tier can want a
    /// download, and only when macOS has not put the model on this machine yet.
    /// Taking `modelReady` as an argument keeps it decidable without a
    /// particular Mac's Apple Intelligence state deciding the test result.
    public static func needsDownload(_ tier: Tier, modelReady: Bool) -> Bool {
        tier == .local && !modelReady
    }

    /// The only framework read on this screen outside SwiftUI, so it stays
    /// behind one name. A property read, not a download or a session.
    static var localModelReady: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static let cards: [Card] = [
        .init(kicker: "What it is",
              title: "PigeonEye reads government documents",
              detail: """
                      Open an EPA pesticide label, a tax form, or a scan of \
                      either. It renders every page and reads the text off it, \
                      so what is buried on page 39 is text you can search and \
                      copy.
                      """),
        .init(kicker: "Where it runs",
              title: "On this machine, and only this machine",
              detail: """
                      Rendering and reading both happen here. This build has no \
                      network code in it at all, and the inspector shows every \
                      step it took and what left the machine: nothing.
                      """),
        .init(kicker: "What you get",
              title: "Every page, or an honest gap",
              detail: """
                      You are told how many pages were read. A page that could \
                      not be rendered is named — in the toolbar and again in the \
                      transcript, where it sits. A missing page is never quietly \
                      skipped.
                      """),
        .init(kicker: "Which model",
              title: "OpenAI reads it, unless you say otherwise",
              detail: """
                      When a page is too unclear to settle here, the question \
                      goes to OpenAI — crops and transcript text, only under the \
                      consent you give at import. Pick On this Mac and nothing \
                      leaves at all. Either way this build sends nothing yet: \
                      the card before this one is still true.
                      """,
              picksTier: true),
    ]

    /// Clamped, so the first Back and the last Next cannot walk off the deck.
    /// The same shape as `Zoom.stepped` and for the same reason: the step and
    /// its bound belong in one place, not split between the two buttons.
    static func card(from index: Int, by delta: Int) -> Int {
        min(max(0, index + delta), cards.count - 1)
    }

    @State private var index = 0
    /// Same store and same reason as `onboardingSeen` in `ReaderScreen`: a
    /// SwiftPM executable has no bundle, so this lands in
    /// `~/Library/Preferences/PigeonEye.plist` and survives a rebuild.
    @AppStorage("readingTier") private var tier = Tier.preferred
    private let done: () -> Void

    public init(done: @escaping () -> Void) { self.done = done }

    private var isLast: Bool { index == Self.cards.count - 1 }

    public var body: some View {
        ZStack {
            Ink.bg
            VStack(alignment: .leading, spacing: 0) {
                card
                Rectangle().fill(Ink.divider).frame(height: 1)
                controls
            }
            .frame(width: 520)
            .background(Ink.bg)
            .blueprint()
        }
        .foregroundStyle(Ink.text)
    }

    private var card: some View {
        let card = Self.cards[index]
        return VStack(alignment: .leading, spacing: 12) {
            Text(card.kicker).kicker(12, tracking: 1.2)
            Text(card.title).font(.heading(25)).tracking(0.5)
            Text(card.detail)
                .font(.body(13.5)).foregroundStyle(Ink.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            if card.picksTier { picker.padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(28)
    }

    /// A plain menu `Picker`. The rest of this app draws its own controls
    /// because the design has no stock equivalent; a dropdown does, and the
    /// stock one already handles keyboard, VoiceOver and the menu placement.
    private var picker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Model").kicker(11, tracking: 1.1)

            Picker("Model", selection: $tier) {
                ForEach(Tier.allCases) { option in Text(option.title).tag(option) }
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
            if Self.needsDownload(tier, modelReady: Self.localModelReady) {
                Button(action: openSettings) {
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
    }

    /// ponytail: the top of System Settings, not the Apple Intelligence pane.
    /// The per-pane URL is an undocumented bundle id that has moved between
    /// releases, and landing on the wrong pane is worse than landing on the
    /// front page. Deep-link it when there is a documented anchor to use.
    private func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:") else { return }
        NSWorkspace.shared.open(url)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            // The dots are the progress readout and a control at once: three
            // cards is short enough that jumping back to one is quicker than
            // pressing Back twice.
            ForEach(Self.cards.indices, id: \.self) { position in
                Button { index = position } label: {
                    Rectangle()
                        .fill(position == index ? Ink.accent : Ink.neutral400)
                        .frame(width: position == index ? 18 : 8, height: 3)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.flat)
                .help(Self.cards[position].title)
            }

            Spacer()

            if index > 0 {
                Button { index = Self.card(from: index, by: -1) } label: {
                    Text("Back")
                        .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(Ink.neutral700)
                        .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
                }
                .buttonStyle(.flat)
            } else {
                // Skip is only offered before the deck has been stepped into.
                // Past that point the remaining card is one press away and a
                // second dismissal button is just a way to miss the last claim.
                Button(action: done) {
                    Text("Skip")
                        .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .foregroundStyle(Ink.neutral600)
                }
                .buttonStyle(.flat)
                .keyboardShortcut(.cancelAction)
            }

            Button { isLast ? done() : (index = Self.card(from: index, by: 1)) } label: {
                Text(isLast ? "Start reading" : "Next")
                    .font(.heading(13)).tracking(1.2).textCase(.uppercase)
                    .padding(.horizontal, 16).padding(.vertical, 6)
                    .background(Ink.accent).foregroundStyle(Ink.bg)
                    .overlay(Rectangle().stroke(Ink.accent, lineWidth: 1))
            }
            .buttonStyle(.flat)
            // Return, not an arrow key: ⌘← and ⌘→ already page the document
            // underneath, and this sits on top of it.
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
    }
}
