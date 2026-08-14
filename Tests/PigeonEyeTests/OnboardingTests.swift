import Testing

@testable import UI

// MARK: - First-run explainer

/// The deck has two ends and both are reachable by holding a button down. The
/// bound lives with the step (`OnboardingScreen.card(from:by:)`) rather than in
/// the two buttons, because that split is exactly what broke zoom in the F1
/// review.
@Test func the_card_deck_cannot_be_stepped_off_either_end() {
    let last = OnboardingScreen.cards.count - 1

    #expect(OnboardingScreen.card(from: 0, by: -1) == 0)
    #expect(OnboardingScreen.card(from: last, by: 1) == last)
    #expect(OnboardingScreen.card(from: 0, by: 1) == 1)
    #expect(OnboardingScreen.card(from: last, by: -1) == last - 1)
}

/// The explainer's whole job is saying what the app does, so an empty card is
/// a shipped blank screen on first launch — the one run where there is nothing
/// else on screen to explain it.
@Test func every_card_says_something() {
    #expect(OnboardingScreen.cards.count >= 3)
    for card in OnboardingScreen.cards {
        #expect(!card.kicker.isEmpty)
        #expect(!card.title.isEmpty)
        #expect(card.detail.count > 40, "a card with nothing on it: \(card.title)")
    }
}
