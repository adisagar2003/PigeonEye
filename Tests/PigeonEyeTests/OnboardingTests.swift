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

// MARK: - Which tier reads it

/// `architecture.md` §5 decided the cloud leg is what the demo runs on, so a
/// first run that has not been touched is an OpenAI run. A default that drifted
/// to local would change where the work happens without anyone choosing it.
@Test func the_tier_defaults_to_openai() {
    #expect(OnboardingScreen.Tier.preferred == .openAI)
    #expect(OnboardingScreen.Tier.allCases == [.openAI, .local])
}

/// The download offer is the one claim on this screen that can be false: the
/// cloud tier never needs a download, and neither does a Mac that already has
/// the model. Offering it anyway is the screen lying about its own state.
@Test func only_a_missing_local_model_is_offered_a_download() {
    #expect(OnboardingScreen.needsDownload(.local, modelReady: false))
    #expect(!OnboardingScreen.needsDownload(.local, modelReady: true))
    #expect(!OnboardingScreen.needsDownload(.openAI, modelReady: false))
    #expect(!OnboardingScreen.needsDownload(.openAI, modelReady: true))
}

/// The picker's own card carries it, and exactly one card does — the deck is
/// stepped by index, so a second one would hand out two competing dropdowns.
@Test func exactly_one_card_carries_the_picker() {
    #expect(OnboardingScreen.cards.count { $0.picksTier } == 1)
    for tier in OnboardingScreen.Tier.allCases {
        #expect(!tier.title.isEmpty)
        #expect(tier.detail.count > 40, "an unexplained tier: \(tier.title)")
    }
}
