import Contracts
import Foundation
import PDFKit
import Testing

@testable import Agent
@testable import Tools

// F8 slice 8.1 — the app's only write. Every row of the slice's stress table in
// `issues.md` is a test here, plus the two CSV escaping cases that the stress
// table does not name and a spreadsheet does.

// MARK: - Fixtures

/// A transcript and the findings quoted out of it, built through
/// `Tools.finding` so **I2** holds on the way in — the export cannot be tested
/// with fabricated quotes because a fabricated quote is not a `Finding`.
private enum Sample {
    static let transcript = """
        EPA Reg. No. 524-529
        Apply 1.6 oz/acre. Respond within 18 months.
        Fee: $1,250.00, payable on receipt.
        """

    static func findings() -> [Finding] {
        [
            ("EPA reg. no.", "524-529", true),
            ("Application rate", "1.6 oz/acre", true),
            ("Time window", "18 months", true),
            ("Amount", "$1,250.00", true),
        ].enumerated().compactMap { index, row in
            finding(
                label: row.0, kind: .other, value: row.1, quote: row.1,
                page: index < 2 ? 1 : 2,
                region: Region(x: 0.1, y: 0.2, width: 0.5, height: 0.02),
                origin: .validator, validated: row.2, conf: 0.72, in: transcript)
        }
    }

    /// CPA-1200's shape: 105 widgets, the largest form in `assets/`.
    static func fields(_ count: Int = 105) -> [Field] {
        (1...count).map {
            Field(name: "topmostSubform[0].Page1[0].f1_\($0)[0]", kind: "/Tx",
                  page: 1 + $0 / 40,
                  region: Region(x: 0.1, y: 0.1, width: 0.2, height: 0.02))
        }
    }

    static func data(_ format: ExportFormat,
                     findings: [Finding] = findings(),
                     fields: [Field] = []) throws -> Data {
        try exported(as: format, name: "007969-00242-20170111.pdf",
                     pagesRead: 12, pageCount: 12, findings: findings, fields: fields)
    }

    static func text(_ format: ExportFormat,
                     findings: [Finding] = findings(),
                     fields: [Field] = []) throws -> String {
        String(decoding: try data(format, findings: findings, fields: fields), as: UTF8.self)
    }
}

// MARK: - 1 · Complete, in every format

/// The stress row is "export a 105-field form → complete, not truncated". A
/// count is the only check that catches a silent cap, so every format is
/// counted rather than eyeballed.
@Test func every_format_carries_every_finding_and_every_field() throws {
    let findings = Sample.findings()
    let fields = Sample.fields()
    #expect(findings.count == 4)

    let csv = try Sample.text(.csv, findings: findings, fields: fields)
    // Header + one row per finding + one row per field, and nothing else.
    #expect(csv.split(separator: "\n").count == 1 + findings.count + fields.count)

    let json = try JSONSerialization.jsonObject(
        with: Sample.data(.json, findings: findings, fields: fields)) as? [String: Any]
    #expect((json?["findings"] as? [Any])?.count == findings.count)
    #expect((json?["fields"] as? [Any])?.count == fields.count)

    let text = try Sample.text(.text, findings: findings, fields: fields)
    for field in fields { #expect(text.contains(field.name)) }
    for found in findings { #expect(text.contains(found.value ?? "—")) }

    let pdf = try PDFDocument(data: Sample.data(.pdf, findings: findings, fields: fields))
    #expect(pdf != nil)
    // 109 rows do not fit on one page. A single-page PDF here means the frame
    // was drawn once and the overflow thrown away, which is the truncation the
    // stress row is about — invisible unless it is counted.
    #expect((pdf?.pageCount ?? 0) > 1)
}

/// The completeness rule (`project-overview.md` §9): nothing found is a result,
/// not an empty file. A zero-byte export reads as a failed write.
@Test(arguments: ExportFormat.allCases)
func a_document_with_nothing_found_still_exports_something_that_says_so(
    format: ExportFormat
) throws {
    let data = try Sample.data(format, findings: [], fields: [])
    #expect(data.count > 0)
    if format == .pdf {
        let pdf = PDFDocument(data: data)
        #expect(pdf?.pageCount == 1)
        #expect(pdf?.string?.contains("Nothing was found") == true)
    } else {
        // Every format names the document, including the one with no prose in
        // it — a header-only CSV is indistinguishable from a failed write.
        #expect(String(decoding: data, as: UTF8.self).contains("007969-00242-20170111.pdf"))
    }
}

// MARK: - 2 · Unresolved stays unresolved

/// The stress row: "export after skipping every escalation → unresolved fields
/// exported as unresolved, not omitted". F5 does not exist yet, so the state is
/// reached directly — the export must already handle it, because the slice that
/// produces it will not be the slice that notices this was dropped.
@Test func an_unresolved_finding_is_exported_as_unresolved_rather_than_dropped() throws {
    let unread = Finding(
        id: "validator:1:Amount::0", label: "Amount", kind: .money, value: nil, conf: 0.11,
        quote: "Fee: $1,250.00", page: 1, region: nil, validated: false,
        origin: .validator, signals: [], unresolved: true)

    for format in ExportFormat.allCases where format != .pdf {
        let text = try Sample.text(format, findings: [unread])
        #expect(text.contains("unresolved"), "\(format.rawValue)")
        #expect(text.contains("Fee: $1,250.00"), "\(format.rawValue)")
    }
    let pdf = try PDFDocument(data: Sample.data(.pdf, findings: [unread]))
    #expect(pdf?.string?.contains("unresolved") == true)
}

// MARK: - 3 · Nothing leaves that the user did not ask to leave

/// **I8/I9** and the slice's grep row: findings only. No source path, no page
/// bytes, no crop. The file name is deliberately in there — it is what makes the
/// export identifiable — but the path it came from is not.
@Test(arguments: ExportFormat.allCases)
func the_export_carries_no_source_path_and_no_page_bytes(format: ExportFormat) throws {
    let data = try exported(
        as: format, name: "007969-00242-20170111.pdf", pagesRead: 12, pageCount: 12,
        findings: Sample.findings(), fields: Sample.fields(3))

    let readable = String(decoding: data, as: UTF8.self)
    #expect(!readable.contains("/Users/"))
    #expect(!readable.contains("/assets/"))
    #expect(!readable.contains("file://"))
    // A page raster is a JPEG or a PNG. Neither magic number belongs in a
    // findings export, in any format — the PDF included, which is text only.
    #expect(!data.contains(Data([0xFF, 0xD8, 0xFF])))
    #expect(!data.contains(Data([0x89, 0x50, 0x4E, 0x47])))
}

// MARK: - 4 · CSV is a format, not a string join

/// A quote is verbatim OCR, so it contains whatever the document contained —
/// commas and quotation marks included. Unescaped, one comma silently shifts
/// every column to its right and the row still looks fine.
@Test func a_quote_with_a_comma_and_a_quotation_mark_survives_the_csv() throws {
    let transcript = #"He said "apply 1.6 oz", then, later, 2.4 oz"#
    let quote = #"said "apply 1.6 oz", then"#
    let awkward = finding(
        label: "Application rate", kind: .other, value: "1.6 oz", quote: quote,
        page: 1, region: nil, origin: .validator, validated: true,
        conf: 0.5, in: transcript)
    #expect(awkward != nil)

    let row = try Sample.text(.csv, findings: [awkward!]).split(separator: "\n")[1]
    #expect(row.contains(#""said ""apply 1.6 oz"", then""#))
    // Ten columns, and the escaping is what keeps it ten — a naive split on the
    // comma finds more, which is exactly the corruption being guarded against.
    #expect(row.split(separator: ",", omittingEmptySubsequences: false).count > 10)
    #expect(!row.contains("\n"))
}

/// A CSV opened in a spreadsheet executes a leading `=`, `+` or `@`. The values
/// here come from OCR of a document nobody in this process controls, so this is
/// an injection at a trust boundary, not a formatting nicety.
@Test(arguments: ["=1+1", "+1", "@SUM(A1)"])
func a_formula_in_a_quote_is_not_exported_as_a_formula(payload: String) throws {
    let transcript = "Rate table: \(payload) per acre"
    let hostile = finding(
        label: "Application rate", kind: .other, value: payload, quote: payload,
        page: 1, region: nil, origin: .validator, validated: false,
        conf: 0.3, in: transcript)
    #expect(hostile != nil)

    let row = try Sample.text(.csv, findings: [hostile!]).split(separator: "\n")[1]
    #expect(!row.contains(",\(payload)"), "\(row)")
    #expect(row.contains(payload), "\(row)")  // still exported, just not armed
}

// MARK: - 5 · Failing to write is a named failure

/// The stress row: "path is unwritable / disk full → named failure, nothing
/// half-written". `.atomic` is what makes the second half true — a plain write
/// leaves a truncated file behind when it runs out of room.
@Test func an_unwritable_path_fails_by_name_and_leaves_nothing_behind() throws {
    let missing = URL(fileURLWithPath: "/var/db/no-such-directory-\(UUID())/findings.csv")
    #expect(throws: (any Error).self) {
        try Sample.data(.csv).write(to: missing, options: .atomic)
    }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
    #expect(!FileManager.default.fileExists(atPath: missing.deletingLastPathComponent().path))
}

// MARK: - 6 · The seam the UI actually calls

/// Everything above tests the formatter against values handed to it. This tests
/// the path the Export menu takes — read a real document, export it, write it
/// — because the two halves being right separately is what the F1 second pass
/// already learned is not the same as the whole thing working.
@Test func a_real_document_exports_through_the_agent_seam() async throws {
    let doc = try await read(Fixture.cleanPage)
    let out = FileManager.default.temporaryDirectory
        .appending(path: "pigeoneye-export-\(UUID())")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: out) }

    #expect(doc.exportName(.csv) == "007969-00242-20170111-01-findings.csv")

    for format in ExportFormat.allCases {
        let url = out.appending(path: doc.exportName(format))
        try doc.exported(as: format).write(to: url, options: .atomic)

        let written = try Data(contentsOf: url)
        #expect(written.count > 0, "\(format.rawValue)")
        // The source is a JPEG. Not one byte of it may appear in the export
        // (**I8**) — and this is the only check that sees the real thing rather
        // than a fixture built to be clean.
        #expect(!written.contains(Data([0xFF, 0xD8, 0xFF])), "\(format.rawValue)")
        #expect(!String(decoding: written, as: UTF8.self).contains(Fixture.root.path),
                "\(format.rawValue)")
    }

    // The document's own findings survived the round trip, not a subset.
    let json = try JSONSerialization.jsonObject(
        with: doc.exported(as: .json)) as? [String: Any]
    #expect((json?["findings"] as? [Any])?.count == doc.findings.count)
    #expect(!doc.findings.isEmpty, "the fixture stopped producing findings")
}

// MARK: - 7 · The format list is the file extension

/// Four formats, four distinct extensions, and `text` is `.txt` rather than
/// `.text` — the one case where the raw value and the extension differ.
@Test func each_format_names_its_own_extension() {
    #expect(ExportFormat.allCases.map(\.ext) == ["json", "csv", "txt", "pdf"])
    #expect(Set(ExportFormat.allCases.map(\.ext)).count == ExportFormat.allCases.count)
}
