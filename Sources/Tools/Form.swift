import Contracts
import CoreGraphics
import Foundation
import PDFKit

// The mode test is the file's own answer, not a guess: does any page carry a
// `Widget` annotation? Measured across the corpus by `spike_form.swift` —
// IRS-4835 63, Schedule F 89, CPA-1200 105, and 0 across 45 pages of EPA label.
//
// Nothing here touches Vision. Form fields come from the file, so this path is
// independent of the OCR pass and of the TextRecognition crash the tracker
// records against it.

/// Every fillable field in a PDF, in page order. The list is read live on every
/// call and never cached — `coding-standards.md` §1.1: the file *is* the ground
/// truth, and a cached copy would be a second one.
public func formFields(pdf url: URL) throws -> [Field] {
    try withDocument(url) { doc in
        var fields: [Field] = []
        for index in 0..<doc.pageCount {
            guard let page = doc.page(at: index) else { continue }
            let box = page.bounds(for: .mediaBox)
            // A page with no size cannot place a rect, and dividing by it yields
            // NaN rather than a refusal. Rasterisation already refuses this page.
            guard box.width > 0, box.height > 0 else { continue }

            for annotation in page.annotations where annotation.type == "Widget" {
                // Per widget, not per field name: radio members share a name and
                // differ only by index (`c1_1[0]`, `c1_1[1]`), so collapsing on
                // the name would drop half of every group.
                fields.append(
                    Field(
                        name: annotation.fieldName ?? "",
                        kind: annotation.widgetFieldType.rawValue,
                        page: index + 1,
                        region: region(of: annotation.bounds, in: box, rotation: page.rotation)))
            }
        }
        return fields
    }
}

/// Convert an annotation rect into the one coordinate origin (**I12**,
/// `architecture.md` §8.1).
///
/// `PDFAnnotation.bounds` is PDF user space: origin lower-left, unnormalised
/// points, offset by the mediaBox origin. `Region` is normalised with the origin
/// upper-left — the space `Tools.ocr` already converts Vision's corners into.
/// Getting the flip backwards mirrors every highlight vertically, which survives
/// eyeballing on a symmetric form and is the same defect I12 exists for.
///
/// Pure and separately tested because there is no rotated fixture in `assets/`,
/// so a table of hand-computed rectangles is the only honest check on the
/// quarter-turn cases.
///
/// - Precondition: `box` has non-zero width and height. `formFields` skips a
///   page that fails it rather than dividing into a NaN region.
func region(of rect: CGRect, in box: CGRect, rotation: Int) -> Region {
    let x = (rect.minX - box.minX) / box.width
    let y = (box.maxY - rect.maxY) / box.height  // the flip
    let width = rect.width / box.width
    let height = rect.height / box.height

    // `/Rotate` turns the page clockwise for display and `rasterise` lets PDFKit
    // apply it, so the region turns with the pixels or the highlight lands on
    // the wrong quarter of the page.
    switch ((rotation % 360) + 360) % 360 {
    case 90: return Region(x: 1 - y - height, y: x, width: height, height: width)
    case 180: return Region(x: 1 - x - width, y: 1 - y - height, width: width, height: height)
    case 270: return Region(x: y, y: 1 - x - width, width: height, height: width)
    default: return Region(x: x, y: y, width: width, height: height)
    }
}
