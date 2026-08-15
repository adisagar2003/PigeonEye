import CoreGraphics
import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Tools
@testable import UI

// The TDD flow in context/features/01-read-it-locally.md §5, in order.
// Behaviour through each layer's public surface — never the Vision plumbing
// behind it, which architecture.md §10 wants free to change.

/// SwiftPM does not promise a working directory, so fixtures resolve from the
/// source file's own path.
enum Fixture {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // PigeonEyeTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root

    static let label = root.appending(path: "assets/epa-labels/000524-00529-20241120.pdf")
    static let shortLabel = root.appending(path: "assets/epa-labels/007969-00242-20170111.pdf")
    /// Named for what it is. This page is a *clean digital render* — the
    /// `WEAL PROTECTED` misread recorded against it comes from the circular
    /// seal, not from scan damage. It is the fast one-page image the tests use
    /// when the subject is anything other than degradation.
    static let cleanPage = root.appending(path: "assets/scans/007969-00242-20170111-01.jpg")

    /// An actual bad scan: photocopy speckle, skew, a `SEP 11 2008` stamp and
    /// handwritten annotations. 36 lines at mean confidence 0.56, six of them
    /// below `Thresholds.escalate`.
    static let degradedScan = root.appending(path: "assets/scans/007969-00186-20080911-01.jpg")

    static let form = root.appending(path: "assets/gov-forms/IRS-ScheduleF-farm-profit-loss.pdf")

    /// The three born-digital forms, with the widget counts `spike_form.swift`
    /// measured. IRS names are XFA-cryptic, NRCS names are human-readable —
    /// which is the whole reason slice 2.2 exists.
    static let irs4835 = root.appending(path: "assets/gov-forms/IRS-4835-farm-rental-income.pdf")
    static let cpa1200 = root.appending(path: "assets/gov-forms/NRCS-CPA-1200-conservation-application.pdf")

    /// Three pages; page 2 has `MediaBox [0 0 0 0]`, so it cannot be rendered
    /// while 1 and 3 can. Synthetic on purpose — no real document in `assets/`
    /// has a damaged page, and this is the only way to reach that branch.
    static let damaged = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/damaged-page-2.pdf")

    /// Two pages; page 2 has `MediaBox [0 0 0 0]` and carries the file's only
    /// `Widget`. Synthetic, like `damaged`, and for the same reason. It exists
    /// to pin what PDFKit actually does with such a page — see
    /// `pdfkit_hides_widgets_on_a_zero_sized_page`.
    static let zeroSizedPage = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "Fixtures/widget-on-zero-sized-page.pdf")

    static func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pigeoneye-test-\(name)")
    }
}

// MARK: - 1 · OCR reads a real scan

/// This used to run against a clean digital render, so "reads a degraded scan"
/// asserted nothing about degradation — it was green for the wrong reason.
/// Floors, not exact scores (`coding-standards.md` §4): the measured numbers
/// live in `progress-tracker.md` and an exact assertion here would flap.
@Test func ocr_reads_a_degraded_scan() async throws {
    let page = try await ocr(image(at: Fixture.degradedScan))

    // It still reads. Degradation must not become an excuse for giving up.
    #expect(page.lines.count >= 25, "read only \(page.lines.count) lines")
    #expect(page.transcript.uppercased().contains("REGISTRATION"))

    // And the damage is visible to the confidence machinery rather than hidden
    // behind a uniformly high score — the seal fragments read at ~0.26.
    let mean = try #require(page.meanConfidence)
    #expect(mean < Thresholds.fairlySure, "mean confidence \(mean) — too clean to be the degraded fixture")
    #expect(page.lines.contains { $0.conf < Float(Thresholds.escalate) },
            "nothing scored below the escalate threshold; low confidence is not being reported")
}

// MARK: - 2 · The coordinate origin is flipped once, at Boundary A

@Test func bbox_origin_is_upper_left() async throws {
    let page = try await ocr(image(at: Fixture.cleanPage))
    // The letterhead is printed at the top of the page. Flipped, it reads
    // y ≈ 0.05; under Vision's own lower-left origin it reads y ≈ 0.94.
    let head = try #require(page.lines.first { $0.text.uppercased().contains("ENVIRONMENTAL PROTECTION AGENCY") })
    #expect(head.region.y < 0.5, "letterhead y was \(head.region.y) — origin not flipped")
    #expect(head.region.height > 0, "height must be positive in either origin")
}

// MARK: - 3 · The crop round-trip, which is what makes I12 real

@Test func crop_of_a_line_reads_back_as_that_line() async throws {
    let img = try image(at: Fixture.cleanPage)
    let page = try await ocr(img)
    // A long line, so OCR of the crop has something to hold on to.
    let line = try #require(page.lines.filter { $0.text.count > 24 }.min { $0.region.y < $1.region.y })

    let padded = Region(x: max(0, line.region.x - 0.01),
                        y: max(0, line.region.y - 0.01),
                        width: min(1, line.region.width + 0.02),
                        height: min(1, line.region.height + 0.02))
    let cropped = try #require(crop(img, to: padded))
    let reread = try await ocr(cropped)

    // A vertically mirrored crop lands on a different line and still passes a
    // bbox check — this is the assertion it cannot survive.
    #expect(squash(reread.transcript) == squash(line.text),
            "crop read back as \"\(reread.transcript)\" but the line is \"\(line.text)\"")
}

/// Whitespace- and case-insensitive compare. Deliberately not a normaliser:
/// `eval/ocr_bench.py` already owns `norm()` for scoring, and a second one
/// that scores differently is the bug coding-standards.md §1.2 warns about.
private func squash(_ s: String) -> String {
    s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

// MARK: - 4 · Rasterisation, because Vision cannot take a PDF

@Test func every_page_of_a_pdf_rasterises() throws {
    let n = try pageCount(pdf: Fixture.shortLabel)
    #expect(n == 12)
    for page in 1...n {
        let img = try rasterise(pdf: Fixture.shortLabel, page: page)
        // US Letter at 150 dpi is 1275 × 1650. Allow a point of rounding.
        #expect(img.width > 1000 && img.height > 1000, "page \(page) is \(img.width)×\(img.height)")
    }
}

// MARK: - 5 · The page cap is computed, and says so

@Test(arguments: [(1, 1, false), (45, 45, false), (120, 120, false), (200, 120, true)])
func page_cap_is_computed_not_silent(total: Int, expected: Int, capped: Bool) {
    let got = Limits.pagesToRead(total: total)
    #expect(got.count == expected)
    #expect(got.capped == capped)
}

// MARK: - 6 · Reading a document end to end

@Test func reading_a_pdf_produces_a_transcript_and_a_page_count() async throws {
    let doc = try await read(Fixture.label)
    #expect(doc.pageCount == 45)
    #expect(doc.pagesRead == 45)
    #expect(doc.pagesReadLine == "read pages 1–45 of 45")
    #expect(doc.pages.count == 45)
    #expect(doc.pages.allSatisfy { !$0.transcript.isEmpty })
}

@Test func reading_an_image_needs_no_rasterisation() async throws {
    let doc = try await read(Fixture.cleanPage)
    #expect(doc.pageCount == 1)
    #expect(doc.pagesReadLine == "read page 1 of 1")
    #expect(!doc.pages[0].transcript.isEmpty)
}

// MARK: - 7 · Refusals name what happened

@Test func an_empty_file_is_a_named_refusal() async throws {
    let url = Fixture.temp("empty.pdf")
    try Data().write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: ReadFailure.self) { try await read(url) }
}

@Test func a_text_file_renamed_pdf_is_a_named_refusal() async throws {
    let url = Fixture.temp("not-really.pdf")
    try Data("this is not a pdf".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: ReadFailure.self) { try await read(url) }
}

@Test func an_unsupported_format_names_the_extension() async throws {
    let url = Fixture.temp("notes.txt")
    try Data("hello".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    await #expect(throws: ReadFailure.unsupported(ext: "txt")) { try await read(url) }
}

@Test func an_oversized_file_names_its_actual_size() async throws {
    let url = Fixture.temp("huge.pdf")
    try Data(count: Limits.maxBytes + 1_048_576).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    do {
        _ = try await read(url)
        Issue.record("expected a refusal")
    } catch let failure as ReadFailure {
        guard case let .tooLarge(bytes, limit) = failure else {
            Issue.record("expected .tooLarge, got \(failure)")
            return
        }
        #expect(bytes == Limits.maxBytes + 1_048_576)
        #expect(limit == Limits.maxBytes)
        #expect(failure.errorDescription?.contains("21.0 MB") == true)
    }
}

// MARK: - 8 · The source file is never modified (I7)

@Test func the_source_file_is_never_modified() async throws {
    let attrs = try FileManager.default.attributesOfItem(atPath: Fixture.shortLabel.path)
    let before = try Data(contentsOf: Fixture.shortLabel)

    _ = try await read(Fixture.shortLabel)

    let after = try FileManager.default.attributesOfItem(atPath: Fixture.shortLabel.path)
    #expect(try Data(contentsOf: Fixture.shortLabel) == before)
    #expect(attrs[.modificationDate] as? Date == after[.modificationDate] as? Date)
    #expect(attrs[.size] as? Int == after[.size] as? Int)
}

// MARK: - 9 · The step log never contains the document (§5.2)

@Test func the_step_log_never_contains_the_document() async throws {
    let doc = try await read(Fixture.shortLabel)
    let log = doc.log.map(\.message).joined(separator: "\n")

    #expect(!log.contains(Fixture.shortLabel.lastPathComponent))
    #expect(!log.contains(Fixture.shortLabel.path))

    // No run of the document's own words either.
    let words = doc.pages[0].transcript.split(whereSeparator: \.isWhitespace)
    for run in stride(from: 0, to: max(0, words.count - 4), by: 7) {
        let phrase = words[run..<min(run + 4, words.count)].joined(separator: " ")
        if phrase.count >= 20 { #expect(!log.contains(phrase), "log leaked \"\(phrase)\"") }
    }
}

@Test func the_log_records_that_nothing_left_the_machine() async throws {
    let doc = try await read(Fixture.cleanPage)
    #expect(doc.log.contains { $0.message == "network calls: 0" })
}

// MARK: - 10 · Review findings, each red before its fix
//
// From the F1 review. Every one of these is a stress case
// context/features/01-read-it-locally.md §7 already specified and no test
// covered.

/// §7: "A PDF where page 3 fails to render → Pages 1–2 and 4–51 still read;
/// page 3 reported, not swallowed." It threw the whole document away instead.
@Test func one_unrenderable_page_does_not_lose_the_rest() async throws {
    let doc = try await read(Fixture.damaged)

    #expect(doc.pageCount == 3)
    #expect(doc.failedPages == [2])
    // Position is preserved, so page 3 is still index 2 and click-to-jump holds.
    #expect(doc.pages.count == 3)
    #expect(doc.pages[0].transcript.contains("PAGE 1"))
    #expect(doc.pages[2].transcript.contains("PAGE 3"))
    // Reported, not swallowed.
    #expect(doc.log.contains { $0.message.contains("page 2") && $0.tag == .flag })
}

/// The other half of the same rule: a document where *nothing* renders is a
/// named refusal, not an empty document dressed as success
/// (`project-overview.md` §9).
@Test func a_document_whose_every_page_fails_is_still_a_refusal() async throws {
    let onlyBadPage = Fixture.temp("all-pages-broken.pdf")
    // The damaged fixture with its two good pages stripped: one 0x0 page.
    let single = """
        %PDF-1.4
        1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
        2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
        3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 0 0] >> endobj
        trailer << /Size 4 /Root 1 0 R >>
        %%EOF
        """
    try single.write(to: onlyBadPage, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: onlyBadPage) }

    // `any Error` would also be satisfied by a cancellation or a raw PDFKit
    // error, which is the opposite of the promise: the refusal has to be one
    // the reader can read. Assert the case and the sentence.
    do {
        _ = try await read(onlyBadPage)
        Issue.record("a document with no readable page was accepted as success")
    } catch let failure as ReadFailure {
        guard case let .unreadable(name, why) = failure else {
            Issue.record("expected .unreadable, got \(failure)")
            return
        }
        #expect(name == onlyBadPage.lastPathComponent)
        #expect(why == "none of its 1 page could be read")
    }
}

// MARK: - 11 · ReaderModel (layer 4) — request invalidation and zoom

/// 🔥 The critical finding: opening a second file did not invalidate the first
/// read, so a slower earlier read assigned its Document over the newer one.
/// The 45-page label takes ~5x the 1-page scan, so the interleaving is reliable.
@Test @MainActor func a_later_open_wins_over_an_earlier_slower_one() async throws {
    let model = ReaderModel()

    async let slowFirst: Void = model.open(Fixture.label)   // 45 pages, ~23s
    async let fastSecond: Void = model.open(Fixture.cleanPage)   // 1 image, ~4s
    _ = await (slowFirst, fastSecond)

    #expect(model.doc?.url == Fixture.cleanPage, "the earlier, slower read overwrote the newer document")
    #expect(model.doc?.pageCount == 1)
}

/// 🔥 Re-opening what is already on screen re-read it from scratch: ~15s, a
/// blanked pane, and the same bytes. It was reachable by a single keystroke —
/// so a stray press threw away the document the user was reading and replaced
/// it with an identical copy 15 seconds later.
@Test @MainActor func the_document_on_screen_is_not_read_a_second_time() async {
    let model = ReaderModel()

    await model.open(Fixture.cleanPage)
    let firstRead = model.doc?.log.first?.id
    #expect(firstRead != nil)

    await model.open(Fixture.cleanPage)

    // A second read builds a fresh log with fresh Step ids. Same id ⇒ the
    // document on screen is the one already read, untouched.
    #expect(model.doc?.log.first?.id == firstRead, "the same document was read twice")

    // Not re-reading is right; doing it silently is not. Pick the file you
    // already have open out of the file dialog and the app has to say
    // something, or the click looks like a hang.
    #expect(model.notice != nil, "the declined re-read produced no acknowledgement at all")
}

/// The latch keys on modification date as well as path. Without that, a file
/// re-saved on disk could never be re-read — you would be shown a transcript of
/// bytes that no longer exist, with no way out but opening something else.
@Test @MainActor func a_file_that_changed_on_disk_is_read_again() async throws {
    // .jpg, so both revisions are the same kind and only the bytes differ.
    let url = Fixture.temp("changing.jpg")
    defer { try? FileManager.default.removeItem(at: url) }

    try Data(contentsOf: Fixture.cleanPage).write(to: url)
    let model = ReaderModel()
    await model.open(url)
    let firstRead = model.doc?.log.first?.id
    #expect(firstRead != nil)

    // Same path, different bytes and a later modification date.
    try Data(contentsOf: Fixture.degradedScan).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)],
                                          ofItemAtPath: url.path)
    await model.open(url)

    #expect(model.doc?.log.first?.id != firstRead, "the stale transcript was kept after the file changed")
}

/// 🔥 The other completion-order race in the same flow. Progress is delivered
/// on unstructured tasks, so one can be queued on the main actor when `read`
/// returns and land *after* `phase` is `.ready` — putting a finished document
/// back on the "Reading page…" screen with nothing left running to take it off.
@Test @MainActor func a_late_progress_event_cannot_undo_a_finished_read() async {
    // Hold the handler instead of a clock: the point is *when* it is called,
    // not how long the read took.
    nonisolated(unsafe) var late: (@Sendable (Int, Int) -> Void)?
    let model = ReaderModel(read: { url, onProgress in
        late = onProgress
        return try await read(url)
    })

    await model.open(Fixture.cleanPage)
    guard case .ready = model.phase else {
        Issue.record("the read did not finish; the rest of this test proves nothing")
        return
    }

    late?(1, 1)
    // Enqueued after the progress task, so by the time this resumes that task
    // has had its turn.
    _ = await Task { @MainActor in }.value

    guard case .ready = model.phase else {
        Issue.record("a stale progress event put a finished document back to .reading")
        return
    }
}

/// A failed page is represented by no image, and the pane's fallback for no
/// image is a spinner. Without this the toolbar says a page failed while the
/// page itself says it is still working — `project-overview.md` §9.
@Test @MainActor func an_unreadable_page_is_named_on_the_page_it_belongs_to() async {
    let model = ReaderModel()
    await model.open(Fixture.damaged)

    #expect(model.doc?.failedPages == [2])
    #expect(!model.pageFailed, "page 1 rendered; nothing should claim it failed")

    model.page = 2
    #expect(model.pageFailed, "page 2 could not be rendered and the pane says nothing")

    model.page = 3
    #expect(!model.pageFailed)
}

/// Zoom multiplied the delta by 100 before adding it, so the first click of
/// either button clamped to the minimum and it never moved again.
@Test @MainActor func zoom_steps_by_the_delta_it_is_given() {
    let model = ReaderModel()
    #expect(model.zoom == 1.0)

    model.zoomBy(0.15)
    #expect(model.zoom == 1.15)
    model.zoomBy(0.15)
    #expect(model.zoom == 1.3)
    model.zoomBy(-0.15)
    #expect(model.zoom == 1.15)
}

@Test @MainActor func zoom_clamps_at_both_ends_without_snapping() {
    let model = ReaderModel()

    for _ in 0..<20 { model.zoomBy(0.15) }
    #expect(model.zoom == 1.6)
    for _ in 0..<20 { model.zoomBy(-0.15) }
    #expect(model.zoom == 0.7)
    // And it still steps normally on the way back off the clamp.
    model.zoomBy(0.15)
    #expect(model.zoom == 0.85)
}
