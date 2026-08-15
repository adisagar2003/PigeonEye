import AppKit
import SwiftUI

/// Every shortcut the reader answers to, in one list.
///
/// The `.help(…)` tooltips on the controls already name their own key, but a
/// tooltip is only readable once you have found the control and hovered it.
/// This is the list for someone who has not — which is the only reason a
/// shortcut sheet exists.
public struct ShortcutsSheet: View {
    public struct Entry {
        let keys: String
        let what: String
    }

    public static let all: [Entry] = [
        .init(keys: "⌘O", what: "Open a file"),
        .init(keys: "⌘←  ⌘→", what: "Previous / next page"),
        .init(keys: "⌘−  ⌘+", what: "Zoom out / in"),
        .init(keys: "⇧⌘T", what: "Show or hide the text it read"),
        .init(keys: "⌘I", what: "Inspector — every step it took"),
        .init(keys: "⌘K", what: "Ask about the page you are on"),
        .init(keys: "?", what: "This list"),
        .init(keys: "esc", what: "Close this list"),
    ]

    /// Whether a key press is the bare `?` that opens this list.
    ///
    /// Matched on the character rather than declared as a `KeyEquivalent`,
    /// because `?` is Shift-/ on a US layout and a different key elsewhere — a
    /// key equivalent has to name one modifier set, and the layout decides
    /// which one that is. Command, Control and Option are excluded so this can
    /// never swallow a real shortcut.
    ///
    /// `typing` is the whole reason this takes a third argument. The monitor
    /// behind it sees **every** keystroke in the app, and returning true
    /// swallows the character — so once there is a text field to type a question
    /// into, "what does ? mean here" opened this sheet and ate the `?`. A
    /// shortcut that steals characters out of a field is worse than no shortcut.
    public static func opensList(characters: String?, modifiers: NSEvent.ModifierFlags,
                                 typing: Bool) -> Bool {
        !typing && characters == "?" && modifiers.intersection([.command, .control, .option]).isEmpty
    }

    private let close: () -> Void

    public init(close: @escaping () -> Void) { self.close = close }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Keyboard shortcuts").kicker(12, tracking: 1.2)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(Self.all.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(entry.keys)
                            .font(.mono(12)).foregroundStyle(Ink.accent700)
                            .frame(width: 76, alignment: .leading)
                        Text(entry.what)
                            .font(.body(13)).foregroundStyle(Ink.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .blueprint(stroke: Ink.divider)

            HStack {
                Spacer()
                Button(action: close) {
                    Text("Done")
                        .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Ink.accent).foregroundStyle(Ink.bg)
                        .overlay(Rectangle().stroke(Ink.accent, lineWidth: 1))
                }
                .buttonStyle(.flat)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 14)
        }
        .padding(24)
        .frame(width: 400)
        .background(Ink.bg)
        .foregroundStyle(Ink.text)
    }
}
