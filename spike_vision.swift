// Spike for context/project-overview.md §12.2 and §12.4:
// does Apple Vision expose per-line confidence + bounding boxes, and what do
// the numbers actually look like on assets/scans/?
//
//   swiftc -O spike_vision.swift -o spike_vision && ./spike_vision assets/scans/*.jpg
//
// Emits JSON so the analysis can happen in Python. Throwaway - delete once the
// answer is recorded.
import Foundation
import Vision

struct Line: Codable {
    let text: String
    let confidence: Float
    // Normalised bbox, lower-left origin. Multiply by page size to crop.
    let x0: Double, y0: Double, x1: Double, y1: Double
    let isTitle: Bool
    let candidates: [String]   // alternative readings = a 2nd confidence signal
}

struct Page: Codable {
    let path: String
    let lines: [Line]
    let tables: Int
    let lists: Int
    let detectedData: Int      // native date/address/phone detection
}

let req = RecognizeDocumentsRequest()
var pages: [Page] = []

for path in CommandLine.arguments.dropFirst() {
    do {
        let obs = try await req.perform(on: URL(fileURLWithPath: path))
        guard let doc = obs.first?.document else { continue }

        let lines = doc.text.lines.map { l -> Line in
            let xs = [l.topLeft.x, l.topRight.x, l.bottomLeft.x, l.bottomRight.x]
            let ys = [l.topLeft.y, l.topRight.y, l.bottomLeft.y, l.bottomRight.y]
            return Line(
                text: l.transcript,
                confidence: l.confidence,
                x0: Double(xs.min()!), y0: Double(ys.min()!),
                x1: Double(xs.max()!), y1: Double(ys.max()!),
                isTitle: l.isTitle,
                candidates: l.topCandidates(3).map { $0.string }
            )
        }

        pages.append(Page(path: path, lines: lines,
                          tables: doc.tables.count,
                          lists: doc.lists.count,
                          detectedData: doc.text.detectedData.count))
    } catch {
        FileHandle.standardError.write("skip \(path): \(error)\n".data(using: .utf8)!)
    }
}

let enc = JSONEncoder()
enc.outputFormatting = [.sortedKeys]
print(String(data: try enc.encode(pages), encoding: .utf8)!)
