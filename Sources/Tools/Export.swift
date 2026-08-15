import Contracts
import CoreGraphics
import CoreText
import Foundation

// F8 slice 8.1 — the app's only write, and the only place bytes leave this
// process at all in the local tier.
//
// What goes out is findings and fields: values, quotes, pages, confidence.
// **Not** the source file, not a page raster, not a crop (**I8**, **I9**) — the
// arguments below are the whole surface, and there is no page image among them.
// The file name is the one identifying string that does go, because an export
// nobody can match back to a document is not worth saving; the *path* it came
// from does not (`coding-standards.md` §5.2's reasoning, applied to a file the
// user chose to write).
//
// Pure over its arguments: no I/O here. The caller picks the path and writes,
// which is what keeps this testable without a temp directory.

/// What went wrong writing an export.
public enum ExportFailure: Error, LocalizedError, Equatable {
    /// Core Graphics refused a PDF context. There is no recovery and no partial
    /// file — the caller has nothing to write.
    case pdfUnavailable

    public var errorDescription: String? {
        switch self {
        case .pdfUnavailable: "The PDF could not be built. Try another format."
        }
    }
}

/// The findings and fields of one document, in `format`.
///
/// - Parameters:
///   - name: the document's file name, not its path.
///   - pagesRead: how many pages were read, and `pageCount` how many it has —
///     both, because **I5**'s claim is the pair, and an export that says "45
///     findings" without saying "of 12 pages read out of 45" is the same lie a
///     hidden pages-read line would be.
public func exported(
    as format: ExportFormat,
    name: String,
    pagesRead: Int,
    pageCount: Int,
    findings: [Finding],
    fields: [Field]
) throws -> Data {
    switch format {
    case .json:
        let encoder = JSONEncoder()
        // Sorted so two exports of one document are byte-identical, which is
        // what makes them diffable and this file testable.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            Export(document: name, pagesRead: pagesRead, pageCount: pageCount,
                   findings: findings, fields: fields))
    case .csv:
        return Data(csv(name: name, findings: findings, fields: fields).utf8)
    case .text:
        return Data(plainText(name: name, pagesRead: pagesRead, pageCount: pageCount,
                              findings: findings, fields: fields).utf8)
    case .pdf:
        return try pdf(plainText(name: name, pagesRead: pagesRead, pageCount: pageCount,
                                 findings: findings, fields: fields))
    }
}

// MARK: - JSON

/// The JSON document shape. A struct rather than a dictionary so the encoder
/// enforces it — `coding-standards.md` §1.1 rules out ad-hoc JSON shapes, and a
/// `[String: Any]` here would be exactly that.
///
/// `Encodable` only, matching `Finding`: there is no import path, so a
/// `Decodable` would be a way to build findings with no transcript to check
/// them against.
private struct Export: Encodable {
    let document: String
    let pagesRead: Int
    let pageCount: Int
    let findings: [Finding]
    let fields: [Field]
}

// MARK: - CSV

/// One header and one row per item, findings and fields in a single table.
///
/// One table rather than two, because a CSV with two headers in it is not a
/// spreadsheet, it is two spreadsheets in a trenchcoat. The `kind` column is
/// what tells them apart, and the columns a field has no answer for are empty
/// rather than invented — a field carries no confidence by construction
/// (`architecture.md` §9.1).
///
/// `document` is a column rather than a preamble for the same reason: a comment
/// line above the header is not CSV, and a table that names its own document on
/// every row is one that survives being concatenated with another.
private func csv(name: String, findings: [Finding], fields: [Field]) -> String {
    var rows = ["document,kind,label,value,page,confidence,validated,origin,unresolved,quote"]

    for found in findings {
        rows.append([
            name,
            "finding",
            found.label,
            found.unresolved ? "unresolved" : (found.value ?? "unresolved"),
            "\(found.page)",
            String(format: "%.3f", found.conf),
            found.validated.map { $0 ? "yes" : "no" } ?? "",
            found.origin.rawValue,
            found.unresolved ? "yes" : "no",
            found.quote,
        ].map(cell).joined(separator: ","))
    }

    for field in fields {
        rows.append([
            name, "field to fill", field.name, "", "\(field.page)", "", "",
            Origin.acroform.rawValue, "", "",
        ].map(cell).joined(separator: ","))
    }

    // The completeness rule, in the one format that has no prose to put it in.
    // A header-only file is indistinguishable from an export that failed
    // silently, and it does not even say which document produced it.
    if findings.isEmpty, fields.isEmpty {
        rows.append([name, "nothing found", "", "", "", "", "", "", "", ""].map(cell)
            .joined(separator: ","))
    }

    return rows.joined(separator: "\n") + "\n"
}

/// One CSV cell: RFC 4180 quoting, plus formula neutralisation.
///
/// The second half is a security fix, not tidiness. Every value here is
/// verbatim OCR of a document this process did not write, and a spreadsheet
/// executes a cell beginning `=`, `+` or `@` on open. Quoting alone does not
/// stop it — Excel parses the formula inside the quotes — so the cell is
/// prefixed with an apostrophe, which spreadsheets read as "this is text".
///
/// ponytail: `-` is deliberately not in the danger set, because `-1.6` is a
/// rate and prefixing it would corrupt a real value on every numeric export.
/// That leaves `-1+1` armed. Upgrade path is a numeric test before the prefix,
/// which is worth writing the day an export is fed to something that matters
/// more than a human reading a column.
private func cell(_ value: String) -> String {
    var text = value
    if let first = text.first, "=+@\t\r".contains(first) { text = "'" + text }
    guard text.contains(where: { ",\"\n\r".contains($0) }) else { return text }
    return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

// MARK: - Plain text, and the PDF that renders it

/// The human-readable export, which the PDF also renders — one body of text,
/// one set of wording, so the two formats cannot drift apart.
private func plainText(
    name: String, pagesRead: Int, pageCount: Int,
    findings: [Finding], fields: [Field]
) -> String {
    var out = """
        PIGEONEYE — WHAT IT FOUND

        Document     \(name)
        Pages read   \(pagesRead) of \(pageCount)
        Findings     \(findings.count)
        Fields       \(fields.count)

        Every value below is quoted verbatim from the text that was read.
        No part of the document itself is in this file.

        """

    out += "\n— FINDINGS —\n\n"
    if findings.isEmpty {
        // The completeness rule (`project-overview.md` §9). A blank section
        // reads as a failed export; "nothing was found" is a result.
        out += "Nothing was found in this document.\n"
    }
    for (index, found) in findings.enumerated() {
        let value = found.unresolved ? "unresolved" : (found.value ?? "unresolved")
        let checked = found.validated.map { $0 ? " · checked" : " · failed its format check" } ?? ""
        out += """
            \(index + 1). \(found.label)
               \(value)
               page \(found.page) · confidence \(String(format: "%.2f", found.conf)) \
            · \(found.origin.rawValue)\(checked)
               “\(found.quote)”

            """
    }

    if !fields.isEmpty {
        out += "\n— FIELDS TO FILL —\n\n"
        out += "Read from the file's own form definition. Nothing inferred.\n\n"
        for (index, field) in fields.enumerated() {
            out += "\(index + 1). \(field.name)  (\(field.kind))  page \(field.page)\n"
        }
    }
    return out
}

/// `text`, paginated onto US Letter pages.
///
/// Core Text against a PDF context rather than a print operation: this returns
/// `Data` with no window, no main-thread requirement and no print panel, which
/// is what lets the pagination be asserted by a test instead of by looking at
/// it. Symbols verified against the active SDK's `CGPDFContext.h` and
/// `CTFrame.h` (`ai-workflow.md` §6).
private func pdf(_ text: String) throws -> Data {
    var media = CGRect(x: 0, y: 0, width: 612, height: 792)  // US Letter at 72 dpi
    let column = media.insetBy(dx: 54, dy: 54)               // 0.75in margins
    let out = NSMutableData()

    guard let consumer = CGDataConsumer(data: out),
          let context = CGContext(consumer: consumer, mediaBox: &media, nil)
    else { throw ExportFailure.pdfUnavailable }

    let body = NSAttributedString(string: text, attributes: [
        kCTFontAttributeName as NSAttributedString.Key:
            CTFontCreateWithName("Menlo" as CFString, 9, nil)
    ])
    let setter = CTFramesetterCreateWithAttributedString(body)
    let path = CGPath(rect: column, transform: nil)
    var start = 0

    repeat {
        context.beginPDFPage(nil)
        let frame = CTFramesetterCreateFrame(
            setter, CFRange(location: start, length: 0), path, nil)
        CTFrameDraw(frame, context)
        let drawn = CTFrameGetVisibleStringRange(frame).length
        context.endPDFPage()
        // A frame that fits nothing would otherwise spin forever emitting blank
        // pages — the failure mode of every hand-rolled paginator.
        guard drawn > 0 else { break }
        start += drawn
    } while start < body.length

    context.closePDF()
    return out as Data
}
