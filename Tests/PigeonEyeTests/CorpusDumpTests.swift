import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Tools

// Measurement, not assertion (`coding-standards.md` §4). Dumps every finding
// over every document in `assets/` to a TSV, which is how the slice 3.4 numbers
// in `context/progress-tracker.md` were produced — and how they get reproduced
// the next time a filter changes.
//
// Gated on an environment variable rather than a tag, because it reads ~500
// pages and takes ~12 minutes: an ordinary `swift test` must not pay for it.
//
//     CORPUS_DUMP=/tmp/findings.tsv swift test --filter dump_findings_over_the_corpus

@Test(.enabled(if: ProcessInfo.processInfo.environment["CORPUS_DUMP"] != nil))
func dump_findings_over_the_corpus() async throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CORPUS_DUMP"]!)
    var rows = "file\tpage\tkind\tlabel\tvalue\tconf\tvalidated\torigin\tquote\n"

    var files: [URL] = []
    for dir in ["assets/epa-labels", "assets/gov-forms", "assets/long-docs", "assets/scans"] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: Fixture.root.appending(path: dir), includingPropertiesForKeys: nil)
        files += (contents ?? [])
            .filter { ["pdf", "jpg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.path < $1.path }
    }

    for file in files {
        // A document that cannot be read is a fact about the corpus, not a
        // reason to abandon the run — the point is the whole distribution.
        guard let doc = try? await Agent.read(file) else {
            print("SKIP \(file.lastPathComponent)")
            continue
        }
        print("\(file.lastPathComponent)\t\(doc.pagesRead)p\t\(doc.findings.count) findings"
              + "\t\(doc.index.count) index rows\t\(doc.fields.count) fields")

        for found in doc.findings {
            rows += [file.lastPathComponent, "\(found.page)", found.kind.rawValue,
                     found.label, found.value ?? "", String(format: "%.3f", found.conf),
                     found.validated.map(String.init) ?? "nil", found.origin.rawValue, found.quote]
                .map { $0.replacingOccurrences(of: "\t", with: " ")
                         .replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: "\t") + "\n"
        }
        // Written per document, so a run interrupted at page 400 still leaves
        // everything it had already read.
        try rows.write(to: out, atomically: true, encoding: .utf8)
    }
}
