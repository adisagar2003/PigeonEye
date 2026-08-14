import Contracts
import CoreGraphics
import Foundation
import Tools

// Layer 2. Orchestrates rasterise + OCR and owns the step log. Knows nothing
// about SwiftUI, and opens no sockets — an agent that opens a socket is a bug
// against I1, not a style issue (coding-standards.md §1).

/// One line of the inspector's step log.
///
/// **§5.2 — content never goes in here.** Counts, durations and decisions
/// only: no document text, no filename, no path, no key. The test
/// `the_step_log_never_contains_the_document` is what keeps that true.
public struct Step: Sendable, Identifiable {
    public enum Tag: String, Sendable { case local, flag, wait, sent, hold }

    public let id = UUID()
    public let seconds: Double
    public let message: String
    public let tag: Tag

    public var stamp: String { String(format: "%.2fs", seconds) }
}

/// A document, read. Text only — page images are rendered on demand through
/// `pageImage(_:)` and discarded, so nothing here holds 45 bitmaps.
public struct Document: Sendable {
    public enum Kind: Sendable { case pdf, image }

    public let url: URL
    public let kind: Kind
    /// Pages the file has.
    public let pageCount: Int
    /// Pages actually read. Differs from `pageCount` only when capped.
    public let pagesRead: Int
    public let capped: Bool
    public let pages: [Page]
    public let log: [Step]

    public var fileName: String { url.lastPathComponent }

    /// **I5** — rendered unconditionally, never behind a disclosure.
    public var pagesReadLine: String {
        pagesRead == 1 ? "read page 1 of \(pageCount)"
                       : "read pages 1–\(pagesRead) of \(pageCount)"
    }

    /// The full transcript, in page order.
    public var transcript: String {
        pages.map(\.transcript).joined(separator: "\n\n")
    }

    /// Rendered on demand, 1-based. The source is opened read-only (**I7**).
    public func pageImage(_ number: Int) throws -> CGImage {
        switch kind {
        case .pdf: try rasterise(pdf: url, page: number)
        case .image: try image(at: url)
        }
    }
}

/// Read a document: every page, eagerly, on this machine.
///
/// Eager because reading was never the constraint — context was. 45 pages cost
/// ~15s once; a lazy read costs 45 round-trips to discover what one pass
/// already knows (`progress-tracker.md`, page window).
public func read(
    _ url: URL,
    onProgress: (@Sendable (Int, Int) -> Void)? = nil
) async throws -> Document {
    let clock = ContinuousClock()
    let start = clock.now
    func elapsed() -> Double { Double(start.duration(to: clock.now).components.seconds)
        + Double(start.duration(to: clock.now).components.attoseconds) / 1e18 }

    var log: [Step] = []
    func note(_ message: String, _ tag: Step.Tag = .local) {
        log.append(Step(seconds: elapsed(), message: message, tag: tag))
    }

    let kind = try validate(url)
    let total = kind == .pdf ? try pageCount(pdf: url) : 1
    let (toRead, capped) = Limits.pagesToRead(total: total)
    note("open · \(total) page\(total == 1 ? "" : "s") · \(kind == .pdf ? "pdf" : "image")")
    if capped {
        note("page cap \(Limits.maxPages) · reading \(toRead) of \(total)", .flag)
    }

    var pages = [Page?](repeating: nil, count: toRead)
    var done = 0
    // Bounded fan-out: a full-width TaskGroup over 45 pages would hold 45
    // bitmaps at once. Each task opens its own PDFDocument — PDFKit is not
    // documented as safe to share across threads.
    for batch in stride(from: 0, to: toRead, by: Limits.concurrentPages) {
        let upper = min(batch + Limits.concurrentPages, toRead)
        try await withThrowingTaskGroup(of: (Int, Page).self) { group in
            for index in batch..<upper {
                group.addTask {
                    let img = switch kind {
                    case .pdf: try rasterise(pdf: url, page: index + 1)
                    case .image: try Tools.image(at: url)
                    }
                    return (index, try await ocr(img))
                }
            }
            for try await (index, page) in group {
                pages[index] = page
                done += 1
                onProgress?(done, toRead)
            }
        }
    }

    let read = pages.compactMap { $0 }
    guard read.count == toRead else {
        throw ReadFailure.unreadable(name: url.lastPathComponent, why: "only \(read.count) of \(toRead) pages could be read")
    }

    let confidences = read.compactMap(\.meanConfidence)
    let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
    note(String(format: "OCR %d page%@ · mean conf %.2f", toRead, toRead == 1 ? "" : "s", mean))

    let blank = read.enumerated().filter { $0.element.lines.isEmpty }.map { $0.offset + 1 }
    if !blank.isEmpty {
        note("no text on \(blank.count) page\(blank.count == 1 ? "" : "s")", .flag)
    }
    note("network calls: 0")

    return Document(url: url, kind: kind, pageCount: total, pagesRead: toRead,
                    capped: capped, pages: read, log: log)
}

/// Format and size, checked before anything is opened or rendered.
private func validate(_ url: URL) throws -> Document.Kind {
    let ext = url.pathExtension.lowercased()
    guard Limits.formats.contains(ext) else { throw ReadFailure.unsupported(ext: ext) }

    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? nil
    if let size, size > Limits.maxBytes {
        throw ReadFailure.tooLarge(bytes: size, limit: Limits.maxBytes)
    }
    if size == 0 {
        throw ReadFailure.unreadable(name: url.lastPathComponent, why: "the file is empty")
    }
    return ext == "pdf" ? .pdf : .image
}
