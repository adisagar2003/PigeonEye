import AppKit
import Testing

@testable import UI

// MARK: - The shortcut list

/// `?` opens the list, and nothing else does. The monitor sees every key press
/// in the app, so a match that is too loose swallows a keystroke meant for the
/// window underneath — `⌘?` reaches the header button, not this.
@Test func only_a_bare_question_mark_opens_the_list() {
    #expect(ShortcutsSheet.opensList(characters: "?", modifiers: [], typing: false))
    // Shift is what produces `?` on most layouts, so it cannot disqualify it.
    #expect(ShortcutsSheet.opensList(characters: "?", modifiers: .shift, typing: false))

    #expect(!ShortcutsSheet.opensList(characters: "/", modifiers: [], typing: false))
    #expect(!ShortcutsSheet.opensList(characters: nil, modifiers: [], typing: false))
    #expect(!ShortcutsSheet.opensList(characters: "?", modifiers: .command, typing: false))
    #expect(!ShortcutsSheet.opensList(characters: "?", modifiers: [.command, .shift], typing: false))
    #expect(!ShortcutsSheet.opensList(characters: "?", modifiers: .control, typing: false))
    #expect(!ShortcutsSheet.opensList(characters: "?", modifiers: .option, typing: false))
}

/// A row with no keys or no description is a line the reader has to guess at,
/// which is worse than the shortcut staying hidden.
@Test func every_row_names_a_key_and_what_it_does() {
    #expect(ShortcutsSheet.all.count >= 5)
    for entry in ShortcutsSheet.all {
        #expect(!entry.keys.isEmpty)
        #expect(!entry.what.isEmpty, "a row with no description: \(entry.keys)")
    }
}
