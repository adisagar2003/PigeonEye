import CoreGraphics
import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Tools

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
    static let scan = root.appending(path: "assets/scans/007969-00242-20170111-01.jpg")
    static let form = root.appending(path: "assets/gov-forms/IRS-ScheduleF-farm-profit-loss.pdf")

    static func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "pigeoneye-test-\(name)")
    }
}

// MARK: - 1 · OCR reads a real scan

@Test func ocr_reads_a_degraded_scan() async throws {
    let page = try await ocr(image(at: Fixture.scan))
    #expect(!page.lines.isEmpty)
    #expect(page.transcript.uppercased().contains("REGISTRATION"))
}

// MARK: - 2 · The coordinate origin is flipped once, at Boundary A

@Test func bbox_origin_is_upper_left() async throws {
    let page = try await ocr(image(at: Fixture.scan))
    // The letterhead is printed at the top of the page. Flipped, it reads
    // y ≈ 0.05; under Vision's own lower-left origin it reads y ≈ 0.94.
    let head = try #require(page.lines.first { $0.text.uppercased().contains("ENVIRONMENTAL PROTECTION AGENCY") })
    #expect(head.region.y < 0.5, "letterhead y was \(head.region.y) — origin not flipped")
    #expect(head.region.height > 0, "height must be positive in either origin")
}

// MARK: - 3 · The crop round-trip, which is what makes I12 real

@Test func crop_of_a_line_reads_back_as_that_line() async throws {
    let img = try image(at: Fixture.scan)
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
    let doc = try await read(Fixture.scan)
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
    let doc = try await read(Fixture.scan)
    #expect(doc.log.contains { $0.message == "network calls: 0" })
}
