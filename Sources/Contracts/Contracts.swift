import Foundation

// Layer 0. Types only — no Vision, no PDFKit, no SwiftUI, no network.
// The output contract lives in context/architecture.md §11; this file is its
// only implementation. No parallel dictionaries, no ad-hoc JSON shapes.

/// One line of recognised text.
///
/// **Coordinate origin (I12).** `bbox` is `[x, y, width, height]`, normalised
/// 0...1, **upper-left** origin — y measured downward from the top of the page.
/// Vision hands back lower-left; the flip happens once, at Boundary A, inside
/// `Tools.ocr`. Nothing downstream converts again.
public struct Line: Codable, Sendable, Equatable {
    public let text: String
    public let conf: Float
    public let bbox: [Double]
    public let title: Bool
    /// Alternative readings from `topCandidates` — the homoglyph signal.
    public let alts: [String]

    public init(text: String, conf: Float, bbox: [Double], title: Bool, alts: [String]) {
        self.text = text
        self.conf = conf
        self.bbox = bbox
        self.title = title
        self.alts = alts
    }

    public var region: Region { Region(x: bbox[0], y: bbox[1], width: bbox[2], height: bbox[3]) }
}

/// A normalised rectangle, upper-left origin. See `Line.bbox`.
public struct Region: Codable, Sendable, Equatable {
    public let x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

/// A deterministic shape a value can be checked against.
///
/// The rule lives here; the regex that implements it lives in `Tools`
/// (`coding-standards.md` §1 — validation is split exactly one way). These are
/// the highest-trust signal in the composite: `524-529` validates and
/// `R G-2 26-O4871` does not, with no model involved (`architecture.md` §12).
public enum Format: String, Codable, Sendable, CaseIterable {
    case epaRegistration
    case duration
    case date
    case amount
    case formNumber
    case rate

    /// What a finding of this shape is called on screen (§11 — `label` is named
    /// per document, and these are the names this corpus uses).
    public var label: String {
        switch self {
        case .epaRegistration: "EPA reg. no."
        case .duration: "Time window"
        case .date: "Date"
        case .amount: "Amount"
        case .formNumber: "Form no."
        case .rate: "Application rate"
        }
    }
}

/// One fillable field, read from the file's AcroForm rather than inferred.
///
/// Carries no confidence and never will: `architecture.md` §9.1 — form fields
/// are ground truth from the file, exact by construction, so **I3** does not
/// apply to them. That is the whole reason form mode is worth having.
public struct Field: Codable, Sendable, Equatable {
    /// The raw AcroForm field name. IRS ships XFA paths
    /// (`topmostSubform[0].Page1[0].f1_04[0]`), NRCS ships readable ones
    /// (`Application Date`). Slice 2.2 resolves the first kind; until then this
    /// is what the user sees.
    public let name: String
    /// `PDFAnnotation.widgetFieldType` — `/Tx`, `/Btn`, `/Ch`, `/Sig`.
    public let kind: String
    /// 1-based, so `Document.pages[field.page - 1]` is this field's page.
    public let page: Int
    /// Normalised, upper-left — the same origin `Line.bbox` uses (**I12**).
    public let region: Region

    public init(name: String, kind: String, page: Int, region: Region) {
        self.name = name; self.kind = kind; self.page = page; self.region = region
    }

    /// Whether the overlay has a rect worth stroking. A widget with a zero-sized
    /// or off-page rect is still a field the user must fill, so it stays in the
    /// list — it just isn't drawn.
    ///
    /// "Off-page" is the half that is easy to miss: a rect wholly outside the
    /// media box has positive width and height, so a size check alone calls it
    /// drawable and the overlay points at nothing.
    public var isDrawable: Bool {
        guard region.x.isFinite, region.y.isFinite,
              region.width.isFinite, region.height.isFinite,
              region.width > 0, region.height > 0
        else { return false }
        // Overlaps the page at all, rather than sitting entirely off one edge.
        return region.x < 1 && region.y < 1
            && region.x + region.width > 0 && region.y + region.height > 0
    }
}

/// One page, read. Text only — page images are rendered on demand and
/// discarded, so a 45-page document does not hold 45 bitmaps.
public struct Page: Codable, Sendable {
    /// Vision's own reading-order text. A two-column form interleaves into
    /// nonsense without it.
    public let transcript: String
    public let lines: [Line]
    public let tables: Int
    public let lists: Int
    /// `detectedData` counts keyed by semantic type. Density is the signal,
    /// not presence — `measurement` fires on 31 of 45 pages of an EPA label.
    public let data: [String: Int]

    public init(transcript: String, lines: [Line], tables: Int, lists: Int, data: [String: Int]) {
        self.transcript = transcript; self.lines = lines
        self.tables = tables; self.lists = lists; self.data = data
    }

    /// Mean per-line confidence, or nil when the page produced no lines.
    public var meanConfidence: Double? {
        guard !lines.isEmpty else { return nil }
        return lines.reduce(0.0) { $0 + Double($1.conf) } / Double(lines.count)
    }
}

public enum Urgency: String, Codable, Sendable {
    case actNow = "act now"
    case soon
    case informational
}

/// Which tier produced a finding. Drives the green rule in §12; **I3** does
/// not apply to `acroform` — those are exact by construction (§9.1).
public enum Origin: String, Codable, Sendable {
    case acroform, datadetector, validator, model
}

public struct Signal: Codable, Sendable, Equatable {
    public let name: String
    public let value: Double
    public init(_ name: String, _ value: Double) { self.name = name; self.value = value }

    /// The signal names the composite understands. Strings, because the
    /// inspector renders them and `architecture.md` §12 ranks them by name — but
    /// named constants, because a typo in a raw string silently removes a signal
    /// from the composite instead of failing.
    public static let ocr = "ocr"
    public static let validator = "validator"
    public static let homoglyph = "homoglyph"
    /// A model's opinion of itself. Never sufficient alone (**I4**).
    public static let model = "model"
}

/// How sure the reader is, as a colour. Three states, because a number alone
/// invites reading precision into it that isn't there.
public enum Band: String, Codable, Sendable {
    case green, amber, red
}

/// The confidence composite — `architecture.md` §12.
///
/// **The two rules are not symmetrical, and that asymmetry is the feature:**
///
/// 1. **Low confidence is a reliable trigger.** Genuine garbage clusters at the
///    bottom of Vision's range — the seal misread `WEAL PROTEIN` scored 0.062,
///    2nd lowest of 1092 measured lines. Below the escalate point is red.
/// 2. **High confidence is not a licence to show green.** The four *highest*
///    scores in the same corpus (0.885, 0.828, 0.824, 0.788) were all `口`,
///    checkbox artifacts read as CJK glyphs. Green needs a reason beyond the
///    score: a format validator passed, or the top candidates agree without a
///    homoglyph substitution.
///
/// Without rule 2 the corpus's worst garbage renders as its most confident
/// finding, and the ring becomes decoration with a number painted on it.
public struct Confidence: Sendable, Equatable {
    public let score: Double
    public let band: Band
    /// Kept, not folded away: **I4** requires the inspector to show the
    /// breakdown, which a composite that discarded its inputs could not do.
    public let signals: [Signal]

    /// Fold signals into a band, or `nil` when there is nothing trustworthy to
    /// fold.
    ///
    /// Returns `nil` rather than a low score when the only signal is the model's
    /// own self-report (**I4**). Not-scored and scored-badly are different
    /// claims, and collapsing them would let a model talk its way onto the
    /// screen with a number no one measured.
    public static func compose(_ signals: [Signal]) -> Confidence? {
        func value(_ name: String) -> Double? {
            signals.first { $0.name == name }?.value
        }
        // I4 — at least one signal that is not the model talking about itself.
        guard signals.contains(where: { $0.name != Signal.model }) else { return nil }

        let validator = value(Signal.validator)
        let homoglyph = value(Signal.homoglyph)
        // With no OCR reading at all — an `acroform` value, say — there is
        // nothing to be uncertain about but the validator's verdict.
        let score = value(Signal.ocr) ?? (validator == 1 ? 1.0 : 0.0)

        let band: Band
        if validator == 0 {
            // I3 — a failed format check is knowledge, not noise. No score
            // argues it back to green; a low one still argues it down to red.
            band = score < Thresholds.escalate ? .red : .amber
        } else if score < Thresholds.escalate {
            band = .red
        } else if score >= Thresholds.confident && (validator == 1 || homoglyph == 0) {
            band = .green
        } else {
            band = .amber
        }
        return Confidence(score: score, band: band, signals: signals)
    }
}

/// One value the reader is willing to show, and the words it came from.
///
/// **Encodable, not Codable, and its initialiser is `package`, both on purpose.**
/// **I2** says every rendered value traces to a verbatim substring of the
/// transcript, and that is enforced at one construction point in `Tools`. A
/// public initialiser — or a synthesised `Decodable` — is a second way in that
/// has no transcript to check against, which would make the guarantee a comment
/// rather than a rule. Decoding comes back when there is an import path that
/// carries the transcript with it.
public struct Finding: Encodable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// `nil` when present-but-unreadable.
    public let value: String?
    public let conf: Double
    /// The verbatim words this came from. **I2** asserts it is a substring of
    /// the transcript.
    public let quote: String
    /// 1-based, required not optional — click-to-jump depends on it.
    public let page: Int
    public let region: Region?
    public let validated: Bool?
    public let origin: Origin
    /// Signal breakdown for the inspector. **I4** requires ≥1 non-model signal.
    public let signals: [Signal]
    public let unresolved: Bool

    /// `package`, so `Tools.finding(…)` stays the only way a `Finding` comes
    /// into existence and **I2**'s substring check cannot be walked around.
    package init(id: String, label: String, value: String?, conf: Double, quote: String,
                 page: Int, region: Region? = nil, validated: Bool? = nil,
                 origin: Origin, signals: [Signal] = [], unresolved: Bool = false) {
        self.id = id; self.label = label; self.value = value; self.conf = conf
        self.quote = quote; self.page = page; self.region = region
        self.validated = validated; self.origin = origin; self.signals = signals
        self.unresolved = unresolved
    }
}

/// The one home for every confidence cut-point (`coding-standards.md` §1.1).
/// A literal in a view or the agent is a bug.
///
/// These are **placeholders** — the design's words-to-number mapping, not a
/// measurement. Slice 3.3 replaces them with values picked off the 1092-line
/// distribution in `assets/scans/`, and open question 3 closes then.
public enum Thresholds {
    public static let confident = 0.85
    public static let fairlySure = 0.60
    /// Below this a region is a candidate for escalation.
    public static let escalate = 0.45

    public static func word(_ c: Double) -> String {
        c >= confident ? "confident" : c >= fairlySure ? "fairly sure" : "uncertain"
    }
}

/// Page-zoom bounds and the step the toolbar moves by.
///
/// One home, because the bug that put it here was exactly a mismatch between
/// the step the buttons passed and the arithmetic that consumed it
/// (`coding-standards.md` §1.1).
public enum Zoom {
    public static let min = 0.7
    public static let max = 1.6
    public static let step = 0.15

    /// Clamped to `min...max` and rounded to whole percent, so the label the UI
    /// shows is exactly the value held.
    public static func stepped(from current: Double, by delta: Double) -> Double {
        Swift.min(max, Swift.max(min, ((current + delta) * 100).rounded() / 100))
    }
}

public enum Limits {
    public static let maxBytes = 20 * 1_048_576
    /// Render DPI. 150 measured sufficient; 300 doubles render time for no CER gain.
    public static let dpi: Double = 150
    /// ponytail: a cap, not a design. Largest real document in assets/ is 45
    /// pages. Raise it when something real needs more; never silently exceed it.
    public static let maxPages = 120
    /// Pages rendered at once. Bounds peak memory: a 150 dpi US-Letter page is
    /// ~8 MB of bitmap, so 6 in flight is ~50 MB rather than 45 × 8 MB.
    public static let concurrentPages = 6

    public static let formats: Set<String> = ["pdf", "png", "jpg", "jpeg"]

    /// The ceiling asserted before every model call (**I13**). The limit fails
    /// *silently* when crossed, which is why the estimate happens before the
    /// request goes out rather than after it comes back wrong.
    ///
    /// ponytail: a character-count estimate, not a tokeniser. It over-counts on
    /// ordinary English, which errs toward sending less than allowed — the safe
    /// direction. A real tokeniser is the upgrade if a page is ever cut that did
    /// not need to be.
    public static let maxPromptTokens = 12_000

    /// How many times the model may ask for another page before it must answer
    /// with what it has (**I10**).
    ///
    /// Four, because the loop exists for one job — "the rates are not on this
    /// page, they are on the rate table" — and a model that needs a fifth page
    /// to answer a question about the page in front of the reader is not
    /// answering that question any more. On the last pass the tool is withdrawn
    /// rather than the turn abandoned, so the bound costs latency, never the
    /// answer.
    public static let askHops = 4

    /// How much of one page's text goes into an ask. The largest page in
    /// `assets/` is well under this; the cap exists so a pathological page
    /// cannot be what pushes a request over `maxPromptTokens`.
    public static let askPageChars = 6_000

    /// **How many pages may leave the machine to answer one question**, however
    /// many the model asks for.
    ///
    /// `askHops` bounds *rounds*, not pages — one reply may legally carry a
    /// hundred `read_page` calls, and processing them all would send an entire
    /// document inside a "bounded" loop. This is the bound that actually holds
    /// the privacy and billing promise, because it counts the thing that leaves.
    public static let askPages = 6

    /// The longest quote carried as evidence with a question, and the longest
    /// question accepted. Both are unbounded at their source — a quote is a
    /// verbatim OCR line and a question is whatever was pasted into the field —
    /// so both are capped before they can be what puts a request over budget.
    public static let askQuoteChars = 300
    public static let askQuestionChars = 2_000

    /// How many earlier turns travel with a question. Enough to follow up
    /// ("and the one below it?"), bounded so a long conversation cannot grow
    /// the payload without limit.
    public static let askHistory = 8

    /// How many pages get read, and whether that is fewer than the document has.
    /// Pure, so it is testable without a 200-page fixture.
    public static func pagesToRead(total: Int) -> (count: Int, capped: Bool) {
        total > maxPages ? (maxPages, true) : (total, false)
    }
}

/// One turn of a conversation about an open document.
///
/// Layer 0 because three layers hold it: the view renders it, the egress
/// serialises it, and the loop between them appends to it. A second shape for
/// "a message" in any of the three is the parallel-dictionary failure
/// `coding-standards.md` §1.1 exists to prevent.
public struct Turn: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant, tool }

    public let role: Role
    /// What the reader sees. For an `.assistant` turn that only asked for a
    /// page, this is empty and `calls` carries the request.
    public let text: String
    /// Which `Call` this turn answers. Set on `.tool` turns only — the API
    /// pairs a result to its request by id, not by position.
    public let callID: String?
    /// Set on `.assistant` turns that asked to read a page.
    public let calls: [Call]
    /// The pages this turn's answer rests on, 1-based and in the order they
    /// were used. Rendered under the answer so a claim can be checked against
    /// the page it came from.
    public let pages: [Int]

    public init(role: Role, text: String, callID: String? = nil,
                calls: [Call] = [], pages: [Int] = []) {
        self.role = role; self.text = text
        self.callID = callID; self.calls = calls; self.pages = pages
    }
}

/// The model asking for something it was not given.
public struct Call: Sendable, Equatable {
    public let id: String
    public let name: String
    /// The raw JSON string the API returns. Left as text on purpose: it is
    /// parsed at the one place that knows what the arguments mean, rather than
    /// decoded into a shape layer 0 would then have to keep in step with the
    /// tool list.
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id; self.name = name; self.arguments = arguments
    }

    /// The one tool this app offers.
    public static let readPage = "read_page"

    /// The page number in `arguments`, or nil if it is not a page request we
    /// understand. A malformed argument is a question the model asked badly,
    /// not a crash.
    public var requestedPage: Int? {
        guard name == Self.readPage,
              let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let number = object["page"] as? Int { return number }
        if let text = object["page"] as? String { return Int(text) }
        return nil
    }
}

/// Reasons a file is refused, each naming what actually happened.
/// `project-overview.md` §9 — none of these is a dead end.
public enum ReadFailure: Error, LocalizedError, Equatable {
    case tooLarge(bytes: Int, limit: Int)
    case unsupported(ext: String)
    case unreadable(name: String, why: String)
    case noPages(name: String)

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(bytes, limit):
            let mb = { (b: Int) in String(format: "%.1f", Double(b) / 1_048_576) }
            return "That file is \(mb(bytes)) MB. The limit is \(mb(limit)) MB."
        case let .unsupported(ext):
            return "PigeonEye reads PDF, PNG and JPEG. It cannot read a .\(ext) file."
        case let .unreadable(name, why):
            return "\(name) could not be opened: \(why)"
        case let .noPages(name):
            return "\(name) has no pages to read."
        }
    }
}
