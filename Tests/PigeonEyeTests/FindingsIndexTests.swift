import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Tools

// F3 slice 3.4 — the findings index. A per-page list is the wrong tool for a
// long document: IRS P17 produces 2,064 findings over 120 pages, and a reader
// looking for the filing deadline cannot page through that. The index is one row
// per distinct value, searchable, with the pages it appears on.

private let transcript = """
    EPA Reg. No. 524-529
    Apply 1.6 oz/acre. Respond within 18 months.
    File by April 15, 2026. Fee: $1,250.00, payable on receipt.
    A second, smaller fee of $99.00 applies to late filings.
    """

private func made(_ rows: [(label: String, kind: Kind, value: String, page: Int, y: Double)]) -> Document {
    let found = rows.compactMap {
        finding(label: $0.label, kind: $0.kind, value: $0.value, quote: $0.value,
                page: $0.page, region: Region(x: 0.1, y: $0.y, width: 0.5, height: 0.02),
                origin: .validator, validated: true, conf: 0.8, in: transcript)
    }
    return Document(
        url: URL(fileURLWithPath: "/tmp/x.pdf"), kind: .pdf, pageCount: 9, pagesRead: 9,
        capped: false,
        pages: (1...9).map { _ in Page(transcript: transcript, lines: [], tables: 0, lists: 0, data: [:]) },
        failedPages: [], fields: [], findings: found, log: [])
}

/// **The reason the index exists.** `$1,250.00` on four pages is one value a
/// reader wants to look up, not four rows to scroll past — and on the real
/// corpus that ratio is 8,421 findings against a far smaller set of values.
@Test func repeated_values_collapse_to_one_row_that_lists_every_page() {
    let doc = made([
        ("Amount", .money, "$1,250.00", 1, 0.2),
        ("Amount", .money, "$1,250.00", 4, 0.5),
        ("Amount", .money, "$1,250.00", 7, 0.1),
        ("Amount", .money, "$99.00", 2, 0.3),
    ])

    let money = doc.index.filter { $0.kind == .money }
    #expect(money.count == 2, "four findings produced \(money.count) rows")

    let repeated = money.first { $0.value == "$1,250.00" }
    #expect(repeated?.pages == [1, 4, 7], "pages: \(repeated?.pages ?? [])")
    #expect(repeated?.count == 3)
}

/// Search is what makes a 120-page document usable at all. Case- and
/// diacritic-insensitive, over the value and over what the value is called —
/// somebody looking for a deadline types "date", not "April".
@Test(arguments: [
    ("april", ["April 15, 2026"]),
    ("APRIL", ["April 15, 2026"]),
    ("date", ["April 15, 2026"]),
    ("1,250", ["$1,250.00"]),
    ("zzz", []),
    ("", ["$1,250.00", "April 15, 2026"]),
])
func the_index_is_searchable_by_value_and_by_what_it_is(query: String, expected: [String]) {
    let doc = made([
        ("Amount", .money, "$1,250.00", 1, 0.2),
        ("Date", .date, "April 15, 2026", 3, 0.4),
    ])
    let values = doc.index(matching: query, kind: nil).map(\.value).sorted()
    #expect(values == expected.sorted(), "\(query.debugDescription) → \(values)")
}

/// A chip narrows to one group and nothing else, which is the whole reason
/// `Kind` is a layer-0 type rather than a string a view matches on.
@Test func a_kind_filter_keeps_only_that_kind() {
    let doc = made([
        ("Amount", .money, "$1,250.00", 1, 0.2),
        ("Date", .date, "April 15, 2026", 3, 0.4),
        ("Time window", .window, "18 months", 2, 0.6),
    ])
    #expect(doc.index(matching: "", kind: .date).map(\.value) == ["April 15, 2026"])
    #expect(doc.index(matching: "", kind: .window).map(\.value) == ["18 months"])
    #expect(doc.index(matching: "1,250", kind: .date).isEmpty, "the query and the chip must both apply")
}

/// Clicking a row that appears on seven pages has to go somewhere in particular,
/// and clicking it again has to go somewhere else — otherwise the second click
/// looks broken.
@Test func a_row_walks_its_occurrences_in_page_order_and_wraps() {
    let doc = made([
        ("Amount", .money, "$1,250.00", 1, 0.2),
        ("Amount", .money, "$1,250.00", 4, 0.5),
        ("Amount", .money, "$1,250.00", 7, 0.1),
    ])
    let row = try! #require(doc.index.first)

    #expect(row.occurrence(after: nil).page == 1, "the first click lands on the first occurrence")
    #expect(row.occurrence(after: 1).page == 4)
    #expect(row.occurrence(after: 4).page == 7)
    #expect(row.occurrence(after: 7).page == 1, "the last occurrence wraps to the first")
    #expect(row.occurrence(after: 5).page == 7, "from a page between two occurrences, the next one")
}

/// The index is in document order, so the first row is the first thing the
/// reader would have met reading it — and two values on one page keep the order
/// they were read in, which needs a *stable* sort and does not come free.
@Test func the_index_is_in_document_order() {
    let doc = made([
        ("Date", .date, "April 15, 2026", 5, 0.4),
        ("Amount", .money, "$1,250.00", 2, 0.2),
        ("Time window", .window, "18 months", 2, 0.6),
    ])
    #expect(doc.index.map(\.value) == ["$1,250.00", "18 months", "April 15, 2026"])
}

/// A row with nothing to jump to is a row that cannot exist: every occurrence
/// carries a page, and the index is built from occurrences.
@Test func an_empty_document_has_an_empty_index() {
    #expect(made([]).index.isEmpty)
}

/// Against a real document rather than a hand-built one — the ratio is the whole
/// argument for the feature, so it is asserted as a floor rather than trusted.
@Test func a_real_label_indexes_to_fewer_rows_than_it_has_findings() async throws {
    let doc = try await Agent.read(Fixture.shortLabel)
    #expect(!doc.findings.isEmpty)
    #expect(doc.index.count < doc.findings.count,
            "\(doc.findings.count) findings indexed to \(doc.index.count) rows — nothing collapsed")
    #expect(doc.index.allSatisfy { !$0.pages.isEmpty })
    #expect(doc.index.reduce(0) { $0 + $1.count } == doc.findings.count,
            "the index lost or duplicated a finding")
}
