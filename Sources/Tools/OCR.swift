import Contracts
import CoreGraphics
import DataDetection
import Foundation
import Vision

// Boundary A (architecture.md §6): `image -> [Line]`. Pure — no state, no
// network, no UI knowledge. §10 depends on this staying that way; a later
// Tauri port reuses it as a sidecar and only the shell changes.
//
// RecognizeDocumentsRequest, not VNRecognizeTextRequest, because it returns
// reading order — on a two-column form the older API interleaves the columns
// into nonsense.

/// Caps how many Vision requests are ever in flight at once, process-wide.
///
/// Vision's own teardown is not concurrency-safe. A crash report from this
/// project shows `EXC_BAD_ACCESS` in `objc_release` inside **TextRecognition**
/// while releasing a finished request — a refcount race in Apple's framework,
/// which we cannot fix and must simply stop provoking.
///
/// The bound has to live **here**, not in each caller, because per-caller bounds
/// compose into no bound at all: `Agent.read` limited itself to
/// `Limits.concurrentPages`, and two concurrent reads still put twice that many
/// requests in flight. One gate at the shared choke point covers `read`, the
/// `ocr` CLI's fan-out, and tests running in parallel.
///
/// ponytail: bounded, not serialised. Serialising would be simpler and provably
/// safe, but 45 pages measured 23.3s at this width and serial is several times
/// that — the demo pays for it. If the crash ever reproduces at this bound,
/// lower `Limits.concurrentPages` before adding machinery.
actor VisionGate {
    static let shared = VisionGate(limit: Limits.concurrentPages)

    private let limit: Int
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func acquire() async {
        guard active >= limit else { active += 1; return }
        // ponytail: not cancellation-aware. No caller cancels an in-flight OCR
        // today — `read` uses a non-throwing group and the UI discards stale
        // results rather than cancelling. Revisit with the first caller that does.
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            active -= 1
        } else {
            // Hand the slot straight over, so `active` stays at the limit.
            waiting.removeFirst().resume()
        }
    }
}

/// Read one page image. Returns Vision's reading-order transcript plus the
/// per-line confidence, geometry and alternative readings the confidence
/// composite (§12) is built on.
public func ocr(_ image: CGImage) async throws -> Page {
    await VisionGate.shared.acquire()
    do {
        let page = try await recognise(image)
        await VisionGate.shared.release()
        return page
    } catch {
        await VisionGate.shared.release()
        throw error
    }
}

/// The request itself. Split out only so the gate above has exactly one thing to
/// wrap — `defer` cannot await.
private func recognise(_ image: CGImage) async throws -> Page {
    // One request per call: the type is not documented as safe to share
    // concurrently.
    let observations = try await RecognizeDocumentsRequest().perform(on: image)
    guard let doc = observations.first?.document else {
        return Page(transcript: "", lines: [], tables: 0, lists: 0, data: [:])
    }

    let lines = doc.text.lines.map { line -> Line in
        let xs = [line.topLeft.x, line.topRight.x, line.bottomLeft.x, line.bottomRight.x]
        let ys = [line.topLeft.y, line.topRight.y, line.bottomLeft.y, line.bottomRight.y]
        let minX = Double(xs.min()!), maxX = Double(xs.max()!)
        let minY = Double(ys.min()!), maxY = Double(ys.max()!)

        // I12, and this is the only place it happens. Vision normalises with a
        // lower-left origin; PDFKit and Core Graphics image work are
        // upper-left. Convert once, here, and never again downstream —
        // handled twice in compensating directions, crops come out mirrored
        // and F5 escalates a region the user never approved.
        return Line(text: line.transcript,
                    conf: line.confidence,
                    bbox: [minX, 1 - maxY, maxX - minX, maxY - minY],
                    title: line.isTitle,
                    alts: line.topCandidates(3).map(\.string))
    }

    var data: [String: Int] = [:]
    for match in doc.text.detectedData { data[detected(match.match.details).type, default: 0] += 1 }

    return Page(transcript: doc.text.transcript, lines: lines,
                tables: doc.tables.count, lists: doc.lists.count, data: data)
}

/// What a detector match is called, three ways: `type` for the page-density
/// index the agent plans against, `label` for the screen, `kind` for the group
/// the findings index files it under.
///
/// One switch rather than three, because a detector type that gains a name in
/// one place and not the others is how `calendarEvent` reached the screen —
/// `data` counts wanted the raw type and the panel took the same string. Density
/// is the signal for the first job (`measurement` fires on 31 of 45 pages of an
/// EPA label, so presence alone filters nothing) and it is a different job from
/// naming a row.
func detected(_ details: DataDetector.Match.SemanticDetails) -> (type: String, label: String, kind: Kind) {
    switch details {
    case .link: ("link", "Link", .contact)
    case .emailAddress: ("emailAddress", "Email", .contact)
    case .phoneNumber: ("phoneNumber", "Phone", .contact)
    case .postalAddress: ("postalAddress", "Address", .contact)
    case .calendarEvent: ("calendarEvent", "Date", .date)
    case .moneyAmount: ("moneyAmount", "Amount", .money)
    case .flightNumber: ("flightNumber", "Flight no.", .other)
    case .shipmentTrackingNumber: ("shipmentTrackingNumber", "Tracking no.", .other)
    case .measurement: ("measurement", "Measurement", .measure)
    case .paymentIdentifier: ("paymentIdentifier", "Payment ref.", .other)
    @unknown default: ("other", "Other", .other)
    }
}
