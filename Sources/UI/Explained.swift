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
///
/// Returns the ledger alongside the explanation, in the same shape `answered`
/// uses, because **whether bytes left is not the same question as whether the
/// call succeeded.** A 401, a 429, a 500 or a reply we could not parse all mean
/// the transcript already crossed; only a refusal raised before the request was
/// built means nothing did. Deciding that here is what stops the inspector from
/// reporting "nothing left" over a send that happened.
public func explained(
    _ doc: Document,
    config: Gate.Config,
    transport: @escaping Gate.Transport = Gate.defaultTransport
) async -> (explanation: Explanation, sends: [String]) {
    let local = explain(doc)
    let carried = doc.transcript.count
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
        return (Explanation(
            docType: answer.docType, whatItIs: answer.whatItIs, summary: answer.summary,
            urgency: answer.urgency, nextSteps: answer.nextSteps, source: answer.source,
            provider: answer.provider,
            signals: explanationSignals(doc) + answer.signals,
            note: answer.note),
            sentLedger(chars: carried, values: doc.findings.count, to: config.host, sent: .yes))
    } catch {
        let departed = sent(error)
        return (Explanation(
            docType: local.docType, whatItIs: local.whatItIs, summary: local.summary,
            urgency: local.urgency, nextSteps: local.nextSteps, source: .local,
            provider: local.provider, signals: local.signals,
            // Named, not swallowed. The reader is told the screen is the local
            // reading and why, rather than being shown a quietly worse answer.
            //
            // **The wording turns on whether the request went out**, because
            // "read on this machine only" over a 500 is a false privacy claim —
            // the transcript was already at the far end when the error came
            // back. Saying the reading is local is only true when nothing left.
            note: departed == .no
                ? "Read on this machine only — \(why(error))."
                : "The text was sent, but the reply could not be used — \(why(error)). "
                    + "The explanation below was assembled on this machine."),
            sentLedger(chars: carried, values: doc.findings.count, to: config.host, sent: departed))
    }
}

/// What the inspector may say about an explain send: how much text, how many
/// values, where it went, and whether it arrived. Never the words themselves,
/// never the filename, never the key (`coding-standards.md` §5.2).
private func sentLedger(chars: Int, values: Int, to host: String, sent: Sent) -> [String] {
    guard sent != .no else { return [] }
    let line = "transcript + \(values) recognised values → \(host) · \(chars) chars"
    return [sent == .yes ? line : line + " · send failed, may not have arrived"]
}
