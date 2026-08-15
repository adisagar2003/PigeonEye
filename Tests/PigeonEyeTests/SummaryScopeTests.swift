import Testing

@testable import UI

// MARK: - Which pages a summary claims to cover

/// The block is a demo shell, but the span it names is the one thing that must
/// not lie: a card headed "pages 3–7" over a summary of page 3 is worse than no
/// card. Bounds entered backwards and bounds past the end of the document are
/// the two ways a stepper pair gets there.
@Test func a_page_span_is_ordered_and_stays_inside_the_document() {
    typealias Block = SummaryBlock

    #expect(Block.pages(scope: .thisPage, page: 4, from: 1, to: 1, last: 10) == [4])
    #expect(Block.pages(scope: .range, page: 1, from: 2, to: 4, last: 10) == [2, 3, 4])
    // Entered the other way round — same span, not an empty one.
    #expect(Block.pages(scope: .range, page: 1, from: 4, to: 2, last: 10) == [2, 3, 4])
    #expect(Block.pages(scope: .range, page: 1, from: 8, to: 99, last: 10) == [8, 9, 10])
    #expect(Block.pages(scope: .thisPage, page: 99, from: 1, to: 1, last: 10) == [10])
    #expect(Block.pages(scope: .whole, page: 4, from: 2, to: 3, last: 3) == [1, 2, 3])
}

/// The span is written once and read in three places — the button, the result
/// header and the footer line. One page is "page 4", not "pages 4–4".
@Test func a_span_reads_as_one_page_or_a_range() {
    #expect(SummaryBlock.label([4]) == "page 4")
    #expect(SummaryBlock.label([2, 3, 4]) == "pages 2–4")
}

/// Sample text has to say it is sample text. This block prints words no model
/// produced, and the one thing that keeps that honest is the label on it.
@Test func the_demo_summary_names_its_own_span_and_says_it_is_a_placeholder() {
    let lines = SummaryBlock.demoSummary([2, 3, 4])
    #expect(lines.count >= 3)
    #expect(lines[0].contains("pages 2–4"))
    #expect(lines[0].lowercased().contains("placeholder"))
}
