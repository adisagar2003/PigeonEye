import Contracts
import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// Vision cannot read a PDF. Measured, not assumed:
//   ./ocr assets/gov-forms/IRS-ScheduleF-farm-profit-loss.pdf
//   -> invalidImage("Zero-dimensioned image (0.0 x 0.0)")
// So every PDF page is rasterised first. Images skip this entirely.

/// Pages in a PDF. Throws a named refusal rather than returning 0.
public func pageCount(pdf url: URL) throws -> Int {
    try withDocument(url) { $0.pageCount }
}

/// Render one page, 1-based, at `dpi`. Rendered on demand and discarded by the
/// caller: a 150 dpi US-Letter page is ~8 MB, so holding 45 of them would cost
/// 380 MB for no reason (architecture.md §7 — memory, session-scoped).
public func rasterise(pdf url: URL, page number: Int, dpi: Double = Limits.dpi) throws -> CGImage {
    try withDocument(url) { doc in
        guard number >= 1, let page = doc.page(at: number - 1) else {
            throw ReadFailure.unreadable(name: url.lastPathComponent, why: "page \(number) does not exist")
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 1, bounds.height > 1 else {
            throw ReadFailure.unreadable(name: url.lastPathComponent, why: "page \(number) has no size")
        }

        let scale = dpi / 72
        // ponytail: quarter-turn pages swap the raster's aspect; PDFKit's own
        // draw applies the rotation. Nothing in assets/ is rotated, so this is
        // untested against a real fixture.
        let quarterTurned = (page.rotation / 90) % 2 != 0
        let size = quarterTurned ? CGSize(width: bounds.height, height: bounds.width) : bounds.size
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())

        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ReadFailure.unreadable(name: url.lastPathComponent, why: "page \(number) could not be rendered")
        }

        // Paper is white. Without this the page renders onto black and Vision
        // reads a fraction of it.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        guard let image = context.makeImage() else {
            throw ReadFailure.unreadable(name: url.lastPathComponent, why: "page \(number) could not be rendered")
        }
        return image
    }
}

/// Load a PNG or JPEG straight through — Vision takes it natively, so the
/// image path is less code than the PDF path, not more.
public func image(at url: URL) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          CGImageSourceGetCount(source) > 0,
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw ReadFailure.unreadable(name: url.lastPathComponent, why: "it is not a readable image")
    }
    return image
}

/// Opens read-only and hands the document to `body`. **I7** — there is no
/// write path to the input anywhere in this file.
///
/// Internal rather than private so `Form.swift` opens PDFs the same way: the
/// not-a-PDF, password-protected and no-pages refusals have one home
/// (`coding-standards.md` §1.1), not one per caller.
func withDocument<T>(_ url: URL, _ body: (PDFDocument) throws -> T) throws -> T {
    guard let doc = PDFDocument(url: url) else {
        throw ReadFailure.unreadable(name: url.lastPathComponent, why: "it is not a readable PDF")
    }
    guard !doc.isLocked else {
        throw ReadFailure.unreadable(name: url.lastPathComponent, why: "it is password-protected")
    }
    guard doc.pageCount > 0 else {
        throw ReadFailure.noPages(name: url.lastPathComponent)
    }
    return try body(doc)
}
