// Apple Vision OCR, as a command. Ships with macOS 26+, runs on the Neural
// Engine, nothing to download.
//
//   ./ocr <image...>                     # the tracked launcher at the repo root
//   ./ocr assets/scans/*.jpg            # plain transcript, one page after another
//   ./ocr --json assets/scans/*.jpg     # JSON array, one object per page
//
// spikes/page_index.py and eval/ shell out to ./ocr and read this JSON, so its shape is a
// contract. The logic lives in Sources/Tools — this file is argv and stdout.
//
// CHANGED in F1: `bbox` is now `[x, y, width, height]` with an **upper-left**
// origin, not `[minX, minY, maxX, maxY]` lower-left. Nothing read bbox before
// (checked), and one origin everywhere is invariant I12.
import Contracts
import Foundation
import Tools

struct JSONPage: Encodable {
    let path: String
    let transcript: String
    let lines: [Line]
    let tables: Int
    let lists: Int
    let data: [String: Int]
}

var args = Array(CommandLine.arguments.dropFirst())
let asJSON = args.first == "--json"
if asJSON { args.removeFirst() }

guard !args.isEmpty else {
    FileHandle.standardError.write("usage: ocr [--json] <image> [image...]\n".data(using: .utf8)!)
    exit(2)
}

// Concurrent: 45 pages take ~15s this way against ~33s serial, and a 45-page
// EPA label is the normal case, not the edge case.
var byPath: [String: JSONPage] = [:]
await withTaskGroup(of: (String, JSONPage?).self) { group in
    for path in args {
        group.addTask {
            do {
                let page = try await ocr(image(at: URL(fileURLWithPath: path)))
                return (path, JSONPage(path: path, transcript: page.transcript, lines: page.lines,
                                       tables: page.tables, lists: page.lists, data: page.data))
            } catch {
                FileHandle.standardError.write("skip \(path): \(error)\n".data(using: .utf8)!)
                return (path, nil)
            }
        }
    }
    for await (path, page) in group { if let page { byPath[path] = page } }
}

// Restore the order the caller asked for; a TaskGroup finishes out of order.
let ordered = args.compactMap { byPath[$0] }

if asJSON {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    print(String(data: try encoder.encode(ordered), encoding: .utf8)!)
} else {
    for page in ordered { print(page.transcript) }
}
