// What PDFKit's own text layer gives us for one page, free.
//
// Spike for the docling question. This is the alternative docling has to beat:
// zero dependencies, already linked, and the decision that rules it out today
// is "OCR every page, always" — a decision, not a capability gap.
//
// Dies when the tracker records an answer to the docling question, or when the
// text-layer decision is re-opened and this becomes `Tools.pageText`.
//
//     swift spikes/spike_pdftext.swift <pdf> <page>

import Foundation
import PDFKit

let args = CommandLine.arguments
guard args.count == 3, let page = Int(args[2]) else {
    FileHandle.standardError.write(Data("usage: spike_pdftext <pdf> <page>\n".utf8))
    exit(2)
}

guard let doc = PDFDocument(url: URL(fileURLWithPath: args[1])) else {
    FileHandle.standardError.write(Data("could not open the pdf\n".utf8))
    exit(1)
}

// 1-based on the command line, 0-based in PDFKit — the off-by-one that would
// silently score the wrong page.
guard page >= 1, page <= doc.pageCount, let target = doc.page(at: page - 1) else {
    FileHandle.standardError.write(Data("page \(page) is not in a \(doc.pageCount)-page document\n".utf8))
    exit(1)
}

print(target.string ?? "")
