import Contracts
import Foundation

// F4 slice 4.1 — the explanation assembled from what was already read, with
// **zero model calls**.
//
// This is not a fallback bolted on afterwards; it is the thing the cloud leg is
// additive to. **I6** says the local result survives any cloud failure, and the
// only way to mean that is for the local result to exist first and stand on its
// own. A missing key, a 429, an aeroplane — the screen still says something true.

/// Describe a document from what reading it produced. Deterministic: the same
/// document always explains itself the same way, and nothing here can invent a
/// fact that the findings do not already carry.
public func explain(_ doc: Document) -> Explanation {
    let validated = doc.findings.filter { $0.validated == true }
    let kinds = Set(doc.findings.map(\.label)).sorted()

    var summary: [String] = [doc.pagesReadLine]  // I5, wherever the document is described

    if doc.isForm {
        summary.append("\(doc.fields.count) fillable fields, read from the file itself — nothing inferred.")
    }
    if doc.findings.isEmpty {
        // The completeness rule: say that nothing was found, rather than saying
        // nothing (`project-overview.md` §9).
        summary.append("No dates, amounts, registration numbers or rates were recognised in the text.")
    } else {
        summary.append("\(doc.findings.count) values recognised" + (validated.isEmpty
            ? "; none matched a known format." : ", \(validated.count) matching a known format."))
        if !kinds.isEmpty { summary.append("Recognised: \(kinds.joined(separator: ", ")).") }
    }
    if !doc.failedPages.isEmpty {
        summary.append("\(doc.failedPages.count) page(s) could not be read and are missing from this.")
    }
    if doc.capped {
        summary.append("Only the first \(doc.pagesRead) of \(doc.pageCount) pages were read.")
    }

    return Explanation(
        docType: doc.isForm ? "Fillable form" : "Document",
        whatItIs: doc.isForm
            ? "A form with fields to complete. The list beside it is read from the file, so it is exact."
            : "A document read on this machine. Every value below quotes the words it came from.",
        summary: summary,
        // Urgency is assigned by consequence, and consequence is exactly what a
        // deterministic pass cannot judge (`architecture.md` §11). Claiming
        // anything else here would be the confident wrong answer this product
        // exists to avoid.
        urgency: .informational,
        nextSteps: doc.isForm
            ? ["Fill the \(doc.fields.count) fields listed. Click one to jump to it on the page."]
            : ["Check each recognised value against the page it came from."],
        source: .local,
        provider: "This machine",
        signals: explanationSignals(doc))
}

/// The honest, non-model signal behind an explanation's ring — for the local
/// pass and for the model's answer alike.
///
/// **A summary is only ever as good as the text under it.** A fluent paragraph
/// written from a badly OCR'd page is confidently wrong, which is precisely the
/// failure this product exists to catch, and no amount of the model rating
/// itself detects it. So the signal is the mean per-line recognition confidence
/// of the pages the summary was built from — measurable, non-model, and
/// therefore admissible under **I4**.
public func explanationSignals(_ doc: Document) -> [Signal] {
    let perPage = doc.pages.compactMap(\.meanConfidence)
    guard !perPage.isEmpty else { return [] }
    return [Signal(Signal.ocr, perPage.reduce(0, +) / Double(perPage.count))]
}
