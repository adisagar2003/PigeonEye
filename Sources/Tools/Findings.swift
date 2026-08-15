import Contracts
import DataDetection
import Foundation

// The two deterministic producers (`issues.md` 3.1): format validators, and
// Apple's data detectors. Neither can hallucinate — a validator either matches
// or it doesn't, and a detector reports what it found in text that was already
// read. `architecture.md` §12 ranks validators the highest-trust signal there is.
//
// Everything here is a pure function over a Page. No network, no model.

/// What a line is *searched* for, which is deliberately looser than what
/// validates.
///
/// One pattern for both jobs silently drops the findings that matter most: OCR
/// reads `10.5 0Z` for `10.5 oz` on page 12 of the 45-page label, and a strict
/// search never sees it — so the user is never told the rate exists, let alone
/// that its reading is doubtful. Finding it and then failing it is the honest
/// outcome; discarding it is the app deciding for the reader.
///
/// ponytail: the widened classes are the confusions measured in this corpus
/// (`0`/`O`, `1`/`l`/`I`, `5`/`S`), not a general OCR-error model. A homoglyph
/// table belongs with 3.2's `topCandidates` signal, which sees the alternatives
/// directly instead of guessing them.
private func candidatePattern(for format: Format) -> Regex<Substring> {
    switch format {
    // `[o0]` is the measured confusion; the units themselves are matched
    // case-insensitively because labels shout them (`10.5 OZ`).
    case .rate: /\b\d{1,4}(?:\.\d{1,2})? ?(?:(?i:fl ?[o0]z|[o0]z|lbs?|gal|pts?|qts?)|%)(?:\s?\/\s?(?i:A|acre))?\b/
    case .epaRegistration: /\b[\dOolI]{3,5}-[\dOolI]{1,5}\b/
    default: pattern(for: format)
    }
}

/// The regex behind each `Format`. Literals, so a broken pattern is a compile
/// error rather than a `try!` that fires on the first bad scan.
private func pattern(for format: Format) -> Regex<Substring> {
    switch format {
    // 524-529, 7969-242, 35915-4. Deliberately not `\d+-\d+`: two digits either
    // side matches a page range and half the numbers on a tax form.
    case .epaRegistration: /\b\d{3,5}-\d{1,5}\b/
    // "18 months from the date of this letter" — a relative window, which is the
    // shape this corpus's obligations actually take. `eval/cases.json` names
    // anchoring one of these to the wrong date as the sharpest trap there is.
    case .duration: /\b\d{1,3} (?:day|week|month|year)s?\b/
    case .date: /\b(?:\d{1,2}\/\d{1,2}\/\d{2,4}|(?:January|February|March|April|May|June|July|August|September|October|November|December) \d{1,2}, \d{4})\b/
    case .amount: /\$\d{1,3}(?:,\d{3})*(?:\.\d{2})?\b/
    case .formNumber: /\b(?:CPA|IRS|EPA|SF|OMB)[- ]?\d{3,4}[A-Z]?\b/
    case .rate: /\b\d{1,4}(?:\.\d{1,2})? ?(?:(?i:fl ?oz|oz|lbs?|gal|pts?|qts?)|%)(?:\s?\/\s?(?i:A|acre))?\b/
    }
}

/// Does this text, in full, have the shape `format` describes?
///
/// Whole-match on purpose: a *containment* check would pass `R G-2 26-O4871`
/// the moment any fragment of it looked like a registration number, which is the
/// exact misread this validator exists to reject.
public func validate(_ text: String, using format: Format) -> Bool {
    guard !text.isEmpty else { return false }
    return (try? pattern(for: format).wholeMatch(in: text)) .flatMap { $0 } != nil
}

/// Every deterministic finding on one page, 1-based.
///
/// Async because `dataDetectorMatches` is an `AsyncSequence`. Nothing here
/// awaits I/O — there is none to await.
public func findings(on page: Page, number: Int) async -> [Finding] {
    var found: [Finding] = []
    var seen = Set<String>()

    func keep(_ candidate: Finding?) {
        guard let candidate else { return }
        // Same words, same place, same shape — one row. "18 months" appears
        // twice in one sentence of the EPA letter and both occurrences share a
        // line, so they share a region and there is nothing to tell them apart.
        let key = "\(candidate.label)|\(candidate.value ?? "")|\(candidate.region.map { "\($0.x),\($0.y)" } ?? "")"
        guard seen.insert(key).inserted else { return }
        found.append(candidate)
    }

    for line in page.lines {
        // ponytail: the region is the whole line, not the matched words — Vision
        // gives per-line boxes and word boxes would need a second request.
        // F5 crops this region, so a tighter box is an upgrade, not a fix.
        let region = line.region

        for format in Format.allCases {
            for match in line.text.matches(of: candidatePattern(for: format)) {
                let quote = String(match.output)
                let validated = validate(quote, using: format)
                keep(
                    finding(
                        label: format.label, value: quote, quote: quote,
                        page: number, region: region,
                        origin: .validator, validated: validated,
                        conf: Double(line.conf),
                        signals: signals(for: quote, line: line, validated: validated),
                        in: page.transcript))
            }
        }

        for await match in line.text.dataDetectorMatches() {
            guard let range = match.range else { continue }
            let quote = String(line.text[range])
            keep(
                finding(
                    label: typeName(match.details), value: quote, quote: quote,
                    page: number, region: region,
                    // A detector reports what it parsed; it ran no format rule,
                    // so `validated` is unknown rather than false (§11).
                    origin: .datadetector, validated: nil,
                    conf: Double(line.conf),
                    signals: signals(for: quote, line: line, validated: nil),
                    in: page.transcript))
        }
    }
    return found
}

/// Characters OCR confuses for one another. Measured in this corpus, not
/// imported from a general Unicode confusables table: `lan Murphy` for
/// `Ian Murphy`, `524-S29` for `524-529`.
///
/// ponytail: single characters only. `rn`→`m` is the classic multi-character
/// confusion and is not covered — it needs alignment rather than a positional
/// walk, and no reading in the corpus has hit it yet.
private let homoglyphClasses: [Set<Character>] = [
    ["l", "I", "1", "|"], ["O", "o", "0"], ["S", "5"], ["Z", "2"],
    ["B", "8"], ["G", "6"], ["q", "9"], ["g", "9"],
]

/// Do two readings differ *only* by characters OCR is known to confuse?
///
/// This is the signal per-line confidence missed entirely. `lan Murphy` scored a
/// comfortable 0.542 — nothing in the number says anything is wrong — while
/// candidate #2 was the correct `Ian Murphy`. `l`/`I` and `O`/`0` are precisely
/// the failure mode on names, dates and registration numbers, which is to say on
/// every value this product exists to get right.
public func differsOnlyByHomoglyph(_ a: String, _ b: String) -> Bool {
    guard a != b else { return false }
    let left = Array(a), right = Array(b)
    guard left.count == right.count else { return false }

    for (x, y) in zip(left, right) where x != y {
        guard homoglyphClasses.contains(where: { $0.contains(x) && $0.contains(y) }) else {
            return false
        }
    }
    return true
}

/// The signals `architecture.md` §12 ranks, for one reading of one line.
///
/// The homoglyph signal is only emitted when there are alternative readings to
/// compare — absent means "not checked", which the composite treats differently
/// from "checked and clean". Silence and a clean bill of health are not the same
/// claim.
private func signals(for quote: String, line: Line, validated: Bool?) -> [Signal] {
    var out = [Signal(Signal.ocr, Double(line.conf))]
    if let validated { out.append(Signal(Signal.validator, validated ? 1 : 0)) }

    let others = line.alts.filter { $0 != line.text }
    if !others.isEmpty {
        let confused = others.contains { differsOnlyByHomoglyph(line.text, $0) }
        out.append(Signal(Signal.homoglyph, confused ? 1 : 0))
    }
    return out
}

/// **The single construction point for a `Finding`, and the only one.**
///
/// **I2** — every rendered value traces to a quote that is a verbatim substring
/// of the transcript. Enforcing it here rather than per-caller is the point: a
/// caller cannot invent a quote, because a caller cannot build a `Finding` any
/// other way. A quote that is not in the transcript yields nil, loudly enough
/// that a test catches it and quietly enough that one bad line does not cost the
/// page its other findings.
func finding(
    label: String, value: String?, quote: String,
    page: Int, region: Region?,
    origin: Origin, validated: Bool?, conf: Double,
    signals: [Signal] = [],
    in transcript: String
) -> Finding? {
    guard !quote.isEmpty, transcript.contains(quote) else { return nil }
    // The region is part of the identity: the same words can appear twice on one
    // page in two places, and two rows sharing an id highlight together and
    // conflate two source locations.
    let where_ = region.map { "\($0.x),\($0.y),\($0.width),\($0.height)" } ?? "-"
    return Finding(
        id: "\(origin.rawValue):\(page):\(label):\(quote):\(where_)",
        label: label, value: value, conf: conf, quote: quote,
        page: page, region: region, validated: validated,
        origin: origin, signals: signals, unresolved: false)
}
