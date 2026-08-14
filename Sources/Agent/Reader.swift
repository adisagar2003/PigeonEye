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
    /// One entry per page in the read window, **positionally**: `pages[n - 1]` is
    /// always page `n`, so `Finding.page` and click-to-jump stay 1-based-correct
    /// even when a page in the middle could not be rendered. A page listed in
    /// `failedPages` holds an empty placeholder here.
    public let pages: [Page]
    /// Pages in the window that could not be rendered or read, 1-based, sorted.
    /// Empty for every document in `assets/`. A damaged page must not cost the
    /// user the other 50 (`features/01-read-it-locally.md` §7), and it must not
    /// pass silently either — `project-overview.md` §9.
    public let failedPages: [Int]
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
    //
    // Non-throwing on purpose. A throwing group cancels its siblings and
    // unwinds the whole read, so one damaged page in a 51-page label used to
    // cost the user the other 50. Each task reports its own outcome instead.
    for batch in stride(from: 0, to: toRead, by: Limits.concurrentPages) {
        let upper = min(batch + Limits.concurrentPages, toRead)
        await withTaskGroup(of: (Int, Page?).self) { group in
            for index in batch..<upper {
                group.addTask {
                    do {
                        let img = switch kind {
                        case .pdf: try rasterise(pdf: url, page: index + 1)
                        case .image: try Tools.image(at: url)
                        }
                        return (index, try await ocr(img))
                    } catch {
                        // Named, not swallowed: the page number reaches the log
                        // below and the screen. The error itself carries the
                        // filename, so it is not logged (§5.2).
                        return (index, nil)
                    }
                }
            }
            for await (index, page) in group {
                pages[index] = page
                done += 1
                onProgress?(done, toRead)
            }
        }
    }

    let failed = pages.enumerated().filter { $0.element == nil }.map { $0.offset + 1 }
    // Every page failing is a different thing from some pages failing: there is
    // no document to show, and an empty one dressed as success is exactly what
    // `project-overview.md` §9 forbids.
    guard failed.count < toRead else {
        throw ReadFailure.unreadable(name: url.lastPathComponent,
                                     why: "none of its \(toRead) page\(toRead == 1 ? "" : "s") could be read")
    }

    // Placeholders keep `pages[n - 1] == page n` true, so a failed page shifts
    // nothing downstream (I12's sibling problem — an off-by-one here would
    // highlight the wrong region just as surely as a flipped origin).
    let read = pages.map { $0 ?? Page(transcript: "", lines: [], tables: 0, lists: 0, data: [:]) }

    let confidences = read.compactMap(\.meanConfidence)
    let mean = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
    note(String(format: "OCR %d page%@ · mean conf %.2f", toRead - failed.count,
                toRead - failed.count == 1 ? "" : "s", mean))

    if !failed.isEmpty {
        note("could not read \(failed.count == 1 ? "page" : "pages") \(list(failed)) · read the rest", .flag)
    }

    let blank = read.enumerated()
        .filter { $0.element.lines.isEmpty && !failed.contains($0.offset + 1) }
        .map { $0.offset + 1 }
    if !blank.isEmpty {
        note("no text on \(blank.count) page\(blank.count == 1 ? "" : "s")", .flag)
    }
    note("network calls: 0")

    return Document(url: url, kind: kind, pageCount: total, pagesRead: toRead,
                    capped: capped, pages: read, failedPages: failed, log: log)
}

/// "2", "2 and 7", "2, 7 and 9" — page numbers are the one document-derived
/// value that is safe to log (§5.2 allows counts and positions, never content).
private func list(_ numbers: [Int]) -> String {
    guard let last = numbers.last else { return "" }
    guard numbers.count > 1 else { return "\(last)" }
    return numbers.dropLast().map(String.init).joined(separator: ", ") + " and \(last)"
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
