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

        /// The one key this preference lives under, shared by every view that
        /// binds it. A second view spelling the string itself is how a settings
        /// pane comes to write somewhere the reader never looks — the "setting
        /// that lies" failure `ReaderModel.honour` exists to prevent, one level
        /// up and harder to see.
        public static let storageKey = "readingTier"

        public var title: String {
            switch self {
            case .openAI: "OpenAI"
            case .local: "On this Mac"
            }
        }

        public var detail: String {
            switch self {
            case .openAI:
                "The text you ask about — or the whole document, if you press "
                    + "Explain — leaves the machine, and only after you agree "
                    + "to it for that document."
            case .local:
                "Apple's on-device model answers your questions here, and the "
                    + "explanation is the one this app assembles itself. "
                    + "Nothing leaves, and there is no key to supply."
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
                      page image and no file ever leaves it. Two things can \
                      leave, both only after you say so: the text of a page you \
                      ask about, and the text of the document if you press \
                      Explain with OpenAI. The inspector lists everything that \
                      left, or says nothing did.
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
                      agree to it for that document; Explain with OpenAI sends \
                      the document's text the same way. Pick On this Mac and \
                      Apple's on-device model answers questions here instead — \
                      nothing leaves, no key, and the explanation is the one \
                      this app assembles itself. Reading is local either way.
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
    // The tier binding, the on-device availability check and the scene-phase
    // refresh all moved to `TierPicker` with the control itself. This screen
    // shows the picker; it no longer has an opinion about what is in it.
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
            if card.picksTier { TierPicker().padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .padding(28)
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
