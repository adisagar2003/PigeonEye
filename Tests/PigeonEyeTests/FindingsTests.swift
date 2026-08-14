import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Tools

// F3 slice 3.1 — the two deterministic producers, and the one place a Finding
// gets built. Every row of the slice's stress table is a test here.

// MARK: - 1 · Validators are deterministic, and say no

/// `524-529` is a real EPA registration number; `R G-2 26-O4871` is what Vision
/// read off a degraded seal on the same corpus. A validator that cannot tell
/// them apart is decoration. Table-driven because the inputs vary and the logic
/// does not (`coding-standards.md` §4).
@Test(arguments: [
    ("524-529", true),
    ("7969-242", true),
    ("35915-4", true),
    ("R G-2 26-O4871", false),
    ("524", false),
    ("52-52", false),
    ("", false),
])
func epa_registration_numbers_validate_and_garbage_does_not(text: String, valid: Bool) {
    #expect(validate(text, using: .epaRegistration) == valid, "\(text.debugDescription)")
}

/// A validator is given whatever OCR produced, which on a bad scan is anything
/// at all. It returns false; it does not throw and it does not hang.
@Test func a_validator_survives_junk() {
    let junk = String(repeating: "x9-", count: 4000)  // ~12 KB
    for format in Format.allCases {
        #expect(!validate("", using: format))
        #expect(!validate(junk, using: format))
        #expect(!validate("日本語テキスト🙂", using: format))
        #expect(!validate("   ", using: format))
    }
}

// MARK: - 2 · I2 — every value traces to a verbatim quote

/// **The invariant this slice exists to make real.** A quote that is not in the
/// transcript is refused at the one construction point, so no caller can invent
/// one — that is the whole reason there is only one construction point.
@Test func a_fabricated_quote_is_refused() {
    let transcript = "EPA Registration Number: 7969-242"

    #expect(
        finding(
            label: "EPA reg. no.", value: "7969-242", quote: "7969-242",
            page: 1, region: Region(x: 0, y: 0, width: 1, height: 0.1),
            origin: .validator, validated: true, conf: 0.9, in: transcript) != nil)

    #expect(
        finding(
            label: "EPA reg. no.", value: "9999-999", quote: "9999-999",
            page: 1, region: Region(x: 0, y: 0, width: 1, height: 0.1),
            origin: .validator, validated: true, conf: 0.9, in: transcript) == nil,
        "a quote absent from the transcript was accepted — I2 is not enforced")
}

/// The same guard, against a real page rather than a hand-built string.
@Test func every_finding_quotes_the_transcript_verbatim() async throws {
    let page = try await ocr(image(at: Fixture.cleanPage))
    let found = await findings(on: page, number: 1)

    #expect(!found.isEmpty, "no findings at all on a page that has a registration number on it")
    for f in found {
        #expect(page.transcript.contains(f.quote), "quote not in transcript: \(f.quote.debugDescription)")
    }
}

// MARK: - 3 · The obligation the document is actually about

/// `eval/cases.json` calls this letter's 18-month window the thing that matters,
/// and its sharpest trap is `wrong_deadline_anchor` — the letter also carries an
/// application date, and anchoring to that is the plausible wrong answer.
///
/// This slice does not decide *which* one is the deadline; F4 does. What it must
/// do is emit the obligation at all, quoted verbatim, so F4 has something true
/// to choose from.
@Test func a_real_scan_yields_the_obligation_quoted_verbatim() async throws {
    let page = try await ocr(image(at: Fixture.cleanPage))
    let found = await findings(on: page, number: 1)

    let durations = found.filter { $0.value?.contains("month") == true }
    #expect(!durations.isEmpty, "the 18-month window was not found")
    #expect(durations.contains { $0.quote.contains("18 month") }, "found a duration, but not the 18-month one")

    let regs = found.filter { $0.origin == .validator && $0.value == "7969-242" }
    #expect(!regs.isEmpty, "the EPA registration number was not found")
    #expect(regs.allSatisfy { $0.validated == true })
    #expect(regs.allSatisfy { $0.page == 1 })
}

// MARK: - 4 · Nothing silently picks a winner

/// The decoy is not suppressed and not promoted: both the date and the relative
/// window are emitted as their own findings with their own quotes. A slice that
/// dropped one would be making F4's choice for it, invisibly.
@Test func the_decoy_date_and_the_relative_window_are_both_emitted() async throws {
    let page = try await ocr(image(at: Fixture.cleanPage))
    let found = await findings(on: page, number: 1)

    #expect(found.contains { $0.value?.contains("month") == true }, "no relative window")
    #expect(found.contains { $0.label.lowercased().contains("date") }, "no date finding")
}

// MARK: - 5 · A doubtful reading is shown, not swallowed

/// **The stress case this slice must not fail.** Page 12 of the 45-page label
/// carries a mix rate, and OCR reads `10.5 0Z` for `10.5 oz`.
///
/// Searching with the same strict pattern that validates would mean never
/// finding it — so the user is never told the rate exists, let alone that its
/// reading is doubtful. Find it and fail it: the row appears, `validated` is
/// false, and 3.2 is what turns that into a colour.
@Test func an_ocr_misread_rate_is_emitted_unvalidated() async {
    let text = "Apply 10.5 0Z per acre before bloom."
    let page = Page(
        transcript: text,
        lines: [Line(text: text, conf: 0.71, bbox: [0.1, 0.2, 0.8, 0.02], title: false, alts: [])],
        tables: 0, lists: 0, data: [:])

    let rates = await findings(on: page, number: 12).filter { $0.label == Format.rate.label }
    let misread = try? #require(rates.first { $0.quote.contains("0Z") })

    #expect(misread != nil, "the misread rate was dropped instead of shown")
    #expect(misread?.validated == false, "a misread rate was reported as validated")
    #expect(misread?.page == 12)

    // And the clean spelling still validates, so failing is a verdict and not
    // the only thing this validator can do.
    let clean = "Apply 10.5 oz per acre before bloom."
    let cleanPage = Page(
        transcript: clean,
        lines: [Line(text: clean, conf: 0.9, bbox: [0.1, 0.2, 0.8, 0.02], title: false, alts: [])],
        tables: 0, lists: 0, data: [:])
    let good = await findings(on: cleanPage, number: 12).filter { $0.label == Format.rate.label }
    #expect(good.contains { $0.validated == true }, "the correct spelling did not validate")
}

/// The same words twice on one page in two places are two findings, and two
/// findings need two identities — otherwise selecting one highlights both and
/// any consumer keyed on `id` conflates two source locations.
@Test func the_same_value_in_two_places_gets_two_identities() async {
    let text = "524-529"
    func line(_ y: Double) -> Line {
        Line(text: text, conf: 0.9, bbox: [0.1, y, 0.3, 0.02], title: false, alts: [])
    }
    let page = Page(
        transcript: text, lines: [line(0.2), line(0.6)], tables: 0, lists: 0, data: [:])

    let found = await findings(on: page, number: 1).filter { $0.origin == .validator }
    #expect(found.count == 2, "two occurrences on different lines collapsed into \(found.count)")
    #expect(Set(found.map(\.id)).count == 2, "two findings share one id")
}

// MARK: - 6 · Degenerate pages

/// A page that read as nothing produces nothing, and does not crash reaching for
/// lines that are not there.
@Test func a_page_with_no_text_yields_no_findings() async {
    let empty = Page(transcript: "", lines: [], tables: 0, lists: 0, data: [:])
    #expect(await findings(on: empty, number: 1).isEmpty)
}

/// Findings carry a 1-based page, because click-to-jump depends on it (§11).
@Test func findings_carry_the_page_they_were_found_on() async throws {
    let page = try await ocr(image(at: Fixture.cleanPage))
    let found = await findings(on: page, number: 7)
    #expect(found.allSatisfy { $0.page == 7 })
}
