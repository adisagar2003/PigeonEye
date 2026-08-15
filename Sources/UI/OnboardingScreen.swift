import Agent
import AppKit
import SwiftUI

// The first-run explainer. Four cards, stepped through by hand, then never
// shown again. Every claim here has to be one the build actually keeps.
//
// It once said "there is no Gate layer in the package", which was true by
// construction until F9 built one. **A first-run screen is the worst place in
// an app to carry a stale promise**: it is read once, by someone deciding
// whether to trust the thing, and never revisited. So the cards now describe
// two tiers that both exist — reading is local either way, and asking is local
// too when the reader picks it (context/features/09-ask-about-this-page.md).

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
    /// row in §5 that decided "cloud for the demo, local where hardware allows".
    ///
    /// **This is now load-bearing rather than recorded.** `ReaderModel.honour`
    /// reads it, and it decides both whether a question is answered on this Mac
    /// or sent to an endpoint, and whether the Explain with OpenAI button is
    /// offered at all. A preference nothing consults is a setting that lies, and
    /// this one used to be exactly that.
    ///
    /// It stays in UI rather than moving to `Contracts`, because the Gate does
    /// not read it — UI reads it and decides whether to call the Gate. Nothing
    /// below layer 4 has an opinion about which tier a person picked.
    ///
    /// **Asking** on `.local` is answered on-device and nothing leaves.
    /// **Explaining** on `.local` is the locally-assembled explanation and
    /// nothing more — no on-device prose yet, which is slice 4.3.
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
                "The text of a page you ask about leaves the machine, and only "
                    + "after you agree to it for that document."
            case .local:
                "Apple's on-device model answers your questions here. Nothing "
                    + "leaves, and there is no key to supply."
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
              title: "Reading happens here, and only here",
              detail: """
                      Rendering and reading both happen on this machine — no \
                      page image and no file ever leaves it. The one thing that \
                      can leave is the text of a page you ask a question about, \
                      and only after you say so. The inspector lists every page \
                      that left, or says nothing did.
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
              title: "OpenAI answers questions, unless you say otherwise",
              detail: """
                      Ask about a page and its text goes to OpenAI, once you \
                      agree to it for that document. Pick On this Mac and \
                      Apple's on-device model answers instead — nothing leaves, \
                      and there is nothing to agree to. Reading is local either \
                      way.
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
    /// Asked once here and again every time the app comes back to the front.
    /// "Download now" sends the user to System Settings, so the trip back is
    /// exactly when the answer has changed — a value read straight in `body`
    /// would leave the button offering a download that has already happened.
    @State private var localModelReady = localModelAvailable()
    @Environment(\.scenePhase) private var scenePhase
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { localModelReady = localModelAvailable() }
        }
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
            if Self.needsDownload(tier, modelReady: localModelReady) {
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
