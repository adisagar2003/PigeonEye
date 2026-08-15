import Agent
import Contracts
import Foundation
import Gate

// The cloud leg is **additive only** (**I6**). This is the one place that is
// true or false, so it is a free function with an injected transport rather than
// something buried in a view: a test can hold it to the promise.
//
// It lives in layer 4 because it is the only layer allowed to see both Agent
// (which produces the local explanation) and Gate (which is the egress).
// `coding-standards.md` §1 — Agent may not import Gate, and must not: an agent
// that opens a socket is a bug against **I1**, not a style issue.

/// Explain a document, preferring the model and never depending on it.
///
/// Any failure — refused key, rate limit, 500, offline, a reply in a shape we do
/// not understand — returns the local explanation with the reason attached. The
/// cloud can add to the screen; it can never take it away.
public func explained(
    _ doc: Document,
    config: Gate.Config,
    transport: @escaping Gate.Transport = Gate.defaultTransport
) async -> Explanation {
    let local = explain(doc)
    do {
        let answer = try await Gate.explain(
            transcript: doc.transcript,
            findings: doc.findings,
            isForm: doc.isForm,
            fieldCount: doc.fields.count,
            config: config,
            transport: transport)

        // The model came back with, at most, its own opinion of itself. **I4**
        // says that can never be the whole basis of a score, so the measured
        // signal — how well the text under the summary was actually read — is
        // added here, where the Document is in scope.
        return Explanation(
            docType: answer.docType, whatItIs: answer.whatItIs, summary: answer.summary,
            urgency: answer.urgency, nextSteps: answer.nextSteps, source: answer.source,
            provider: answer.provider,
            signals: explanationSignals(doc) + answer.signals,
            note: answer.note)
    } catch {
        let why = (error as? LocalizedError)?.errorDescription
            ?? (error as? URLError).map { _ in "the machine could not reach the API" }
            ?? "the request did not complete"
        return Explanation(
            docType: local.docType, whatItIs: local.whatItIs, summary: local.summary,
            urgency: local.urgency, nextSteps: local.nextSteps, source: .local,
            provider: local.provider, signals: local.signals,
            // Named, not swallowed. The reader is told the screen is the local
            // reading and why, rather than being shown a quietly worse answer.
            note: "Read on this machine only — \(why).")
    }
}
