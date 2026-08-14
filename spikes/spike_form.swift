// Spike: do the government form PDFs expose fillable AcroForm fields via
// PDFKit? If yes, "required fields to fill" + "jump to page" come free with
// exact page index and rect - no OCR, no ML, no heuristics.
//
//   swiftc -O spikes/spike_form.swift -o spike_form
//   ./spike_form assets/gov-forms/*.pdf
import Foundation
import PDFKit

for path in CommandLine.arguments.dropFirst() {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: path)) else {
        print("\(path): CANNOT OPEN"); continue
    }
    var widgets = 0, named = 0, byType: [String: Int] = [:]
    var samples: [String] = []

    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i) else { continue }
        for a in page.annotations {
            let sub = a.type ?? "nil"
            byType[sub, default: 0] += 1
            guard sub == "Widget" else { continue }
            widgets += 1
            if let name = a.fieldName {
                named += 1
                if samples.count < 6 {
                    let ctl = a.widgetControlType
                    samples.append("p\(i + 1) \(name) [\(a.widgetFieldType.rawValue)/\(ctl.rawValue)] rect=\(a.bounds.integral)")
                }
            }
        }
    }
    print("\n\(path.split(separator: "/").last!)")
    print("  pages=\(doc.pageCount) widgets=\(widgets) named=\(named)")
    print("  annotationTypes=\(byType)")
    for s in samples { print("    \(s)") }
}
