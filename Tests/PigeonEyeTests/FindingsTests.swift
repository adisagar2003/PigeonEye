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
            label: "EPA reg. no.", kind: .identifier, value: "7969-242", quote: "7969-242",
            page: 1, region: Region(x: 0, y: 0, width: 1, height: 0.1),
            origin: .validator, validated: true, conf: 0.9, in: transcript) != nil)

    #expect(
        finding(
            label: "EPA reg. no.", kind: .identifier, value: "9999-999", quote: "9999-999",
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
    // Carries the cue, because since 3.4 a bare `524-529` is a shape and not a
    // claim — see `a_registration_number_is_claimed_only_where_the_line_says_so`.
    let text = "EPA Reg. No. 524-529"
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

// MARK: - 7 · Slice 3.4 — the shape is not the claim

/// Helper: one line, one page, so a filter rule can be stated as a sentence.
private func page(_ text: String, conf: Float = 0.9) -> Page {
    Page(transcript: text,
         lines: [Line(text: text, conf: conf, bbox: [0.1, 0.2, 0.8, 0.02], title: false, alts: [])],
         tables: 0, lists: 0, data: [:])
}

/// **The 88% false positive this slice exists to kill.** `\b\d{3,5}-\d{1,5}\b`
/// matched 78 distinct values across `assets/` and 9 were registration numbers.
/// Every other one — phone numbers, IRS notice numbers, OMB numbers, ZIP+4 —
/// rendered *checked*, because passing the shape is exactly what "checked"
/// claimed. A shape this common is not a claim; the words beside it are.
@Test(arguments: [
    ("For emergencies call 1-800-424-9300 day or night.", false),
    ("See Rev. Proc. 2021-48 for the election.", false),
    ("OMB No. 1545-0074", false),
    ("Washington, D.C. 20250-9410; (2) fax", false),
    ("Supplemental: NVA 2008-04-088-0099", false),
    ("EPA Reg. No. 524-529", true),
    ("EPA Registration Number: 7969-242", true),
    ("MASTER LABEL FOR EPA REG. NO. 524-529", true),
])
func a_registration_number_is_claimed_only_where_the_line_says_so(text: String, claimed: Bool) async {
    let regs = await findings(on: page(text), number: 1)
        .filter { $0.label == Format.epaRegistration.label }
    #expect(!regs.isEmpty == claimed, "\(text.debugDescription) → \(regs.map { $0.value ?? "" })")
}

/// A phone number is still found — the cue declines to *label* a value, it never
/// discards one. The detector that legitimately found it still reports it.
@Test func the_phone_number_behind_a_rejected_registration_number_survives() async {
    let found = await findings(on: page("For emergencies call 1-800-424-9300 day or night."), number: 1)
    #expect(found.contains { $0.kind == .contact && $0.value?.contains("424-9300") == true },
            "rejecting the reg-no claim also lost the phone number: \(found.map { $0.value ?? "" })")
}

/// An establishment number is not a registration number, and `2008-04-088-0099`
/// contains four things shaped like one. Pinned as its own case because it is
/// the misread that looks most like a real value on an EPA label.
@Test func an_establishment_number_is_not_a_registration_number() async {
    let found = await findings(on: page("Supplemental: NVA 2008-04-088-0099"), number: 1)
    #expect(!found.contains { $0.origin == .validator && $0.value == "2008-04" },
            "a fragment of a longer number was emitted as a value of its own")
}

/// **One value, one row.** `$1,000` is matched by the `amount` validator *and*
/// by Apple's `moneyAmount` detector, at the same place on the same page — 693
/// and 695 rows of the same 120 pages of IRS P17. Two rows for one value is not
/// two facts, it is the same fact said twice, and the validator is the half that
/// carries a verdict.
@Test func one_value_in_one_place_is_one_row() async {
    let found = await findings(on: page("You may deduct up to $1,000 of that expense."), number: 1)
    let money = found.filter { $0.kind == .money }

    #expect(money.count == 1, "one amount produced \(money.count) rows: \(money.map(\.label))")
    #expect(money.first?.origin == .validator, "the merge kept the tier that cannot say no")
    #expect(money.first?.validated == true)
}

/// Apple's date detector reads a rate range as a date: `1.6-2.4` and `0.07 -
/// 0.10` off the EPA rate tables, `Saturday` off the tax guide. 80 of 114
/// `calendarEvent` matches in this corpus carried no date in them at all, and
/// they land in the one group a reader opens to find a deadline.
@Test(arguments: [
    ("Apply 1.6-2.4 per acre.", false),
    ("Rate range 0.07 - 0.10 lb.", false),
    ("or Saturday, whichever is later", false),
    ("File by April 15, 2026 to avoid penalty.", true),
    ("Stamped FEB 15 2011 on receipt.", true),
    ("Expires 4/22/09 per the notice.", true),
])
func a_detected_date_with_no_date_in_it_is_not_a_date(text: String, kept: Bool) async {
    let dates = await findings(on: page(text), number: 1).filter { $0.kind == .date }
    #expect(!dates.isEmpty == kept, "\(text.debugDescription) → \(dates.map { $0.value ?? "" })")
}

/// The detector types reach the screen as their own names, and `calendarEvent`
/// is not a word anybody reads a government document looking for.
@Test func a_detector_finding_is_named_in_the_readers_words() async {
    let found = await findings(on: page("Write to 26 Davis Drive, Research Triangle Park, NC 27709."), number: 1)
    #expect(!found.contains { $0.label.contains(where: \.isUppercase) && $0.label.hasPrefix("postal") },
            "a raw detector type reached the label: \(found.map(\.label))")
    #expect(found.contains { $0.kind == .contact })
}

/// Every finding lands in a group, so a filter chip set cannot hide one.
@Test func every_finding_on_a_real_page_carries_a_kind() async throws {
    let read = try await ocr(image(at: Fixture.cleanPage))
    let found = await findings(on: read, number: 1)
    #expect(!found.isEmpty)
    #expect(found.allSatisfy { Kind.allCases.contains($0.kind) })
}
