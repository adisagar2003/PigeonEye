// Apple Vision OCR. Ships with macOS 26+, runs on the Neural Engine, nothing to download.
//   swiftc -O ocr.swift -o ocr && ./ocr assets/scans/*.jpg
//
// RecognizeDocumentsRequest (not VNRecognizeTextRequest) because it returns reading
// order — on a two-column form the older API interleaves the columns into nonsense.
import Foundation
import Vision

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write("usage: ocr <image> [image...]\n".data(using: .utf8)!)
    exit(2)
}

let req = RecognizeDocumentsRequest()
for path in CommandLine.arguments.dropFirst() {
    do {
        let obs = try await req.perform(on: URL(fileURLWithPath: path))
        guard let doc = obs.first?.document else { continue }
        print(doc.text.transcript)
    } catch {
        FileHandle.standardError.write("skip \(path): \(error)\n".data(using: .utf8)!)
    }
}
