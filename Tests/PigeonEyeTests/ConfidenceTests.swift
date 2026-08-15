import Foundation
import Testing

@testable import Contracts
@testable import Tools

// F3 slice 3.2 — the composite from `architecture.md` §12, and the rules that
// make it unable to lie. The asymmetry is the whole feature: low confidence is a
// reliable trigger, high confidence is not a licence.

private func signals(ocr: Double? = nil, validator: Double? = nil,
                     homoglyph: Double? = nil, model: Double? = nil) -> [Signal] {
    var out: [Signal] = []
    if let ocr { out.append(Signal(Signal.ocr, ocr)) }
    if let validator { out.append(Signal(Signal.validator, validator)) }
    if let homoglyph { out.append(Signal(Signal.homoglyph, homoglyph)) }
    if let model { out.append(Signal(Signal.model, model)) }
    return out
}

// MARK: - 1 · I3 — a failed validator can never render green

/// The clamp, and the reason it is a clamp and not a weight: a value that failed
/// a deterministic format check is *known* wrong-shaped. No OCR score, however
/// high, is evidence against that.
@Test(arguments: [0.5, 0.75, 0.885, 0.99, 1.0])
func a_failed_validator_can_never_render_green(ocr: Double) throws {
    let c = try #require(Confidence.compose(signals(ocr: ocr, validator: 0)))
    #expect(c.band != .green, "OCR \(ocr) with a failed validator rendered \(c.band)")
}

/// And passing one is what green is actually for.
@Test func a_passed_validator_at_a_high_score_is_green() throws {
    let c = try #require(Confidence.compose(signals(ocr: 0.9, validator: 1)))
    #expect(c.band == .green)
}

// MARK: - 2 · I4 — never solely model self-report

/// A model saying it is sure about itself is not a measurement. With nothing
/// else present the finding cannot be scored at all — not scored low, *not
/// scored*, so the UI has to say so rather than paint a number.
@Test func a_finding_with_only_model_self_report_cannot_be_scored() {
    #expect(Confidence.compose(signals(model: 0.99)) == nil)
    #expect(Confidence.compose([]) == nil)
    #expect(Confidence.compose(signals(ocr: 0.7, model: 0.99)) != nil,
            "one non-model signal is enough, and this had one")
}

// MARK: - 3 · The low end is trustworthy

/// `WEAL PROTEIN` — the circular-seal misread, 2nd lowest of 1092 lines in the
/// corpus. Genuine garbage clusters at the bottom, which is why rule 1 works.
@Test func the_worst_line_in_the_corpus_scores_red() throws {
    let c = try #require(Confidence.compose(signals(ocr: 0.062)))
    #expect(c.band == .red, "0.062 rendered \(c.band)")
}

// MARK: - 4 · The high end is not

/// The four highest scores in the whole corpus — 0.885, 0.828, 0.824, 0.788 —
/// were all `口`, checkbox artifacts read as CJK glyphs. If a high score alone
/// could award green, the corpus's worst garbage would render as its most
/// confident finding. Nothing may reach green on OCR score alone.
@Test(arguments: [0.885, 0.828, 0.824, 0.788])
func the_high_end_of_ocr_confidence_does_not_license_green(ocr: Double) throws {
    let c = try #require(Confidence.compose(signals(ocr: ocr)))
    #expect(c.band != .green, "\(ocr) with no other signal rendered green")
}

// MARK: - 5 · Homoglyphs, the signal confidence missed

/// `lan Murphy` scored a comfortable mid-range 0.542 — nothing in the number
/// says anything is wrong. Candidate #2 was `Ian Murphy`, which is the correct
/// reading. `l`/`I` is exactly the failure mode on names, dates and reg numbers.
@Test func a_homoglyph_alternative_is_flagged() throws {
    #expect(differsOnlyByHomoglyph("lan Murphy", "Ian Murphy"))
    #expect(differsOnlyByHomoglyph("524-S29", "524-529"))
    #expect(differsOnlyByHomoglyph("0hio", "Ohio"))

    // Not homoglyphs: a real disagreement, and an identical reading.
    #expect(!differsOnlyByHomoglyph("Murphy", "Murphys"))
    #expect(!differsOnlyByHomoglyph("cat", "dog"))
    #expect(!differsOnlyByHomoglyph("same", "same"))

    let c = try #require(Confidence.compose(signals(ocr: 0.542, homoglyph: 1)))
    #expect(c.band != .green, "a homoglyph disagreement still rendered green")
}

/// Clean candidates are the *other* route to green — §12's rule 2 is a
/// disjunction, not a validator monopoly.
@Test func clean_candidates_at_a_high_score_are_green() throws {
    let c = try #require(Confidence.compose(signals(ocr: 0.9, homoglyph: 0)))
    #expect(c.band == .green)
}

// MARK: - 6 · The boundaries are decided, not accidental

/// `<` versus `<=` at a cut point is the kind of thing that is wrong for a year
/// without anyone noticing. Exactly-at-threshold is defined here.
@Test(arguments: [
    (Thresholds.escalate, Band.amber),   // at the escalate point, not below it
    (Thresholds.confident, Band.green),  // at the confident point, green
])
func confidence_exactly_at_a_threshold_is_defined(score: Double, expected: Band) throws {
    let c = try #require(Confidence.compose(signals(ocr: score, validator: 1)))
    #expect(c.band == expected, "\(score) landed on \(c.band)")
}

@Test func just_below_the_escalate_point_is_red() throws {
    let c = try #require(Confidence.compose(signals(ocr: Thresholds.escalate - 0.001, validator: 1)))
    #expect(c.band == .red, "a validator pass rescued a score below the escalate point")
}

// MARK: - 7 · The inspector can show its work

/// **I4** says the breakdown is visible. A composite that folded its inputs away
/// would make that impossible, so the signals survive on the result.
@Test func the_composite_keeps_the_signals_it_was_built_from() throws {
    let c = try #require(Confidence.compose(signals(ocr: 0.7, validator: 1, homoglyph: 0)))
    #expect(Set(c.signals.map(\.name)) == [Signal.ocr, Signal.validator, Signal.homoglyph])
}

// MARK: - 8 · Against the real corpus

/// The sweep the stress table asks for: every finding on the degraded scan,
/// through the composite. None may be green without a validator pass or clean
/// candidates — the property, checked against real readings rather than
/// hand-built signal sets.
@Test func no_real_finding_is_green_without_earning_it() async throws {
    let page = try await ocr(image(at: Fixture.degradedScan))
    let found = await findings(on: page, number: 1)

    for f in found {
        guard let c = Confidence.compose(f.signals) else { continue }
        guard c.band == .green else { continue }
        let passedValidator = f.signals.first { $0.name == Signal.validator }?.value == 1
        let cleanCandidates = f.signals.first { $0.name == Signal.homoglyph }?.value == 0
        #expect(passedValidator || cleanCandidates,
                "green with neither a validator pass nor clean candidates: \(f.quote.debugDescription)")
    }
}

/// **The false-flag rate is the difference between a signal and an alarm.**
///
/// Measured over all 1092 lines in `assets/scans/`: **93.8% carry some candidate
/// disagreement, but only 0.7% are homoglyph disagreements** — worst page 4.3%.
/// That gap is the whole reason §12 ranks raw disagreement "low, too noisy as a
/// binary" and the homoglyph filter "high, and specific".
///
/// A ceiling, not an exact score (`coding-standards.md` §4). If this ever climbs
/// toward the raw rate, F5's gate escalates whole documents, and escalating
/// everything is a failure rather than caution.
@Test func the_homoglyph_signal_flags_few_enough_lines_to_be_a_signal() async throws {
    let page = try await ocr(image(at: Fixture.degradedScan))
    let withAlternatives = page.lines.filter { line in
        line.alts.contains { $0 != line.text }
    }
    let flagged = withAlternatives.filter { line in
        line.alts.contains { $0 != line.text && differsOnlyByHomoglyph(line.text, $0) }
    }

    #expect(!withAlternatives.isEmpty, "no candidate alternatives at all — the signal cannot exist")
    let rate = Double(flagged.count) / Double(withAlternatives.count)
    #expect(rate < 0.15, "homoglyph flags on \(Int(rate * 100))% of lines — that is an alarm, not a signal")
}

/// Every finding carries at least one non-model signal, so **I4** holds for
/// everything the deterministic tier produces rather than only in theory.
@Test func every_deterministic_finding_can_be_scored() async throws {
    let page = try await ocr(image(at: Fixture.degradedScan))
    let found = await findings(on: page, number: 1)

    #expect(!found.isEmpty)
    for f in found {
        #expect(Confidence.compose(f.signals) != nil,
                "\(f.label) carries no non-model signal, so it can never be scored")
    }
}
