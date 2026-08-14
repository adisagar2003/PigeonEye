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

public struct Signal: Codable, Sendable {
    public let name: String
    public let value: Double
    public init(_ name: String, _ value: Double) { self.name = name; self.value = value }
}

public struct Finding: Codable, Sendable, Identifiable {
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

    public init(id: String, label: String, value: String?, conf: Double, quote: String,
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

    /// How many pages get read, and whether that is fewer than the document has.
    /// Pure, so it is testable without a 200-page fixture.
    public static func pagesToRead(total: Int) -> (count: Int, capped: Bool) {
        total > maxPages ? (maxPages, true) : (total, false)
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
