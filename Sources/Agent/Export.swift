import Contracts
import Foundation
import Tools

// F8 slice 8.1 — the seam that lets the UI export without reaching into layer 1.
//
// `Tools.exported` takes loose values on purpose: it is a pure formatter and
// knows nothing about a `Document`. `Document` is layer 2 and the UI already
// holds one, so the adapter belongs here — four lines, and the layer rule in
// `coding-standards.md` §1 stays mechanical rather than negotiated.

extension Document {
    /// This document's findings and fields, in `format`, ready to write.
    ///
    /// The document's *bytes* are not among them (**I8**, **I9**) — `pages` and
    /// `pageImage` are not passed, and there is no argument they could be
    /// passed as.
    public func exported(as format: ExportFormat) throws -> Data {
        try Tools.exported(as: format, name: fileName, pagesRead: pagesRead,
                           pageCount: pageCount, findings: findings, fields: fields)
    }

    /// What to call the exported file: the document's name with its extension
    /// swapped, so `007969-00242.pdf` exports as `007969-00242-findings.csv`
    /// and two documents never propose the same name.
    public func exportName(_ format: ExportFormat) -> String {
        let stem = (fileName as NSString).deletingPathExtension
        return "\(stem.isEmpty ? "findings" : stem)-findings.\(format.ext)"
    }
}
