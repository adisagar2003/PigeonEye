// Spike for context/project-overview.md §12.1: can the on-device Apple
// Foundation Model do the *reasoning* tier - read OCR text of a government
// document and extract what matters - or do we need cloud for that?
//
//   swiftc -O spike_fm.swift -o spike_fm && ./ocr assets/scans/X.jpg | ./spike_fm
//
// Throwaway. Delete once the answer is recorded.
import Foundation
import FoundationModels

// Diagnostics go to stderr so stdout is clean for `| python eval/score.py`.
func note(_ s: String) {
    FileHandle.standardError.write("\(s)\n".data(using: .utf8)!)
}

let model = SystemLanguageModel.default
note("availability: \(model.availability)")
guard model.isAvailable else {
    note("UNAVAILABLE - on-device model cannot run here.")
    note("Enable it: System Settings -> Apple Intelligence & Siri. Device is eligible (M4).")
    exit(1)
}

let ocrText = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
guard !ocrText.isEmpty else {
    note("usage: ./ocr <img> | ./spike_fm")
    exit(2)
}
note("input: \(ocrText.count) chars")

let session = LanguageModelSession(instructions: """
    You explain official government documents to people who do not understand \
    them. Use only what the document says. If a detail is not in the text, say \
    it is not stated. Never invent dates, numbers, or names.
    """)

let prompt = """
    Here is the OCR text of a government document.

    1. What kind of document is this? One short phrase.
    2. What does it say? Two or three plain sentences.
    3. What, if anything, does the recipient have to DO? If nothing, say so.
    4. List any dates, reference numbers, or deadlines, exactly as written.

    ---
    \(ocrText)
    """

let t0 = Date()
do {
    let reply = try await session.respond(to: prompt)
    note("responded in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
    print(reply.content)          // stdout only - the answer itself
} catch {
    note("ERROR: \(error)")
    exit(1)
}
