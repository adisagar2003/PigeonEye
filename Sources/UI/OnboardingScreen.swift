import SwiftUI

// The first-run explainer. Three cards, stepped through by hand, then never
// shown again. Every claim here is one F1 actually keeps — there is no Gate
// layer in the package, so "nothing leaves this machine" is true by
// construction rather than by promise (context/features/01-read-it-locally.md
// §3). When a later feature adds egress, the card that says so changes with it.

public struct OnboardingScreen: View {
    struct Card {
        let kicker: String
        let title: String
        let detail: String
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
    ]

    /// Clamped, so the first Back and the last Next cannot walk off the deck.
    /// The same shape as `Zoom.stepped` and for the same reason: the step and
    /// its bound belong in one place, not split between the two buttons.
    static func card(from index: Int, by delta: Int) -> Int {
        min(max(0, index + delta), cards.count - 1)
    }

    @State private var index = 0
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
