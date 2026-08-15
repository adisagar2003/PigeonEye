import Contracts
import Foundation

// Layer 3. **The only place in this package where bytes leave the machine.**
//
// Until this file existed, the trust claim was not a promise — it was the
// absence of an API, checkable with one grep. That is no longer true, so the
// claim now rests on this file being small enough to read in full and on
// `scripts/layers.sh` keeping `URLSession` out of everywhere else.
//
// What crosses, and only this (`architecture.md` §6, Trust row):
//   • the transcript text
//   • the recognised values and their quotes
// What never crosses, at any tier:
//   • the source file's bytes, the filename, the path
//   • any page image or crop (this slice sends no image at all)
//   • the key, anywhere but the Authorization header
//
// Consent is taken at import for the whole document in cloud tier
// (`project-overview.md` §4.1), and nothing here runs until the reader asks for
// it — the request is made by an explicit action, never on open.

public enum Gate {
    /// Where the request goes, and with what. OpenAI-compatible on purpose: the
    /// base URL is swappable, so a local server is the same code path with a
    /// different host (`progress-tracker.md`, "Agent is model-agnostic").
    public struct Config: Sendable, Equatable {
        public let baseURL: URL
        public let model: String
        public let key: String

        public init(baseURL: URL, model: String, key: String) {
            self.baseURL = baseURL; self.model = model; self.key = key
        }

        /// Read the configuration from the environment, or `nil` when there is
        /// no key.
        ///
        /// `nil` is load-bearing: the UI uses it to decide whether to *offer*
        /// the cloud leg at all. An app that shows a button which cannot work is
        /// worse than one that shows no button.
        public static func fromEnvironment(_ env: [String: String]) -> Config? {
            let key = (env["OPENAI_KEY"] ?? env["OPENAI_API_KEY"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }

            let host = env["OPENAI_BASE_URL"] ?? "https://api.openai.com/v1"
            guard let baseURL = URL(string: host) else { return nil }
            return Config(baseURL: baseURL, model: env["OPENAI_MODEL"] ?? "gpt-4o-mini", key: key)
        }
    }

    /// Injected so tests never touch the network, and so the one network call in
    /// the package has exactly one seam.
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// The real one. Exposed so callers can default to it **without naming
    /// `URLSession` themselves** — `scripts/layers.sh` greps for that symbol
    /// outside this directory and is right to: a default argument in layer 4 is
    /// still layer 4 holding a socket.
    public static let defaultTransport: Transport = { try await URLSession.shared.data(for: $0) }

    public enum Failure: Error, LocalizedError, Equatable {
        case http(status: Int)
        case malformedReply

        public var errorDescription: String? {
            switch self {
            case .http(let status) where status == 401: "the API key was refused"
            case .http(let status) where status == 429: "the API is rate-limiting us"
            case .http(let status): "the API answered \(status)"
            case .malformedReply: "the API answered in a shape we do not understand"
            }
        }
    }

    /// A character-count estimate of tokens.
    ///
    /// ponytail: not a tokeniser. ~4 characters per token over-counts ordinary
    /// English, which errs toward sending *less* than allowed — the safe
    /// direction for a limit that fails silently (**I13**).
    public static func estimatedTokens(_ text: String) -> Int {
        text.count / 4
    }

    /// Ask the model what the document is. The single egress function.
    public static func explain(
        transcript: String,
        findings: [Finding],
        isForm: Bool,
        fieldCount: Int,
        config: Config,
        transport: Transport = Gate.defaultTransport
    ) async throws -> Explanation {
        let evidence = findings.prefix(60).map { "\($0.label): \($0.value ?? "—") — \"\($0.quote)\"" }
        let instructions = prompt(isForm: isForm, fieldCount: fieldCount, evidence: evidence)

        func body(_ text: String) throws -> Data {
            try JSONSerialization.data(withJSONObject: [
                "model": config.model,
                "temperature": 0,
                "response_format": ["type": "json_object"],
                "messages": [
                    ["role": "system", "content": instructions],
                    ["role": "user", "content": text],
                ],
            ])
        }

        // I13 — the budget is asserted against **the bytes that actually go
        // out**, before they go out. Budgeting the prompt alone leaves the JSON
        // envelope unaccounted for, which is how a request lands 41 tokens over
        // a limit that fails silently.
        //
        // Bounded, per I10: three corrective passes, never a while-true. JSON
        // escaping changes length slightly as text is cut, so one pass can
        // undershoot.
        var text = transcript
        var payload = try body(text)
        var note: String?
        for _ in 0..<3 where estimatedTokens(String(decoding: payload, as: UTF8.self)) > Limits.maxPromptTokens {
            let over = estimatedTokens(String(decoding: payload, as: UTF8.self)) - Limits.maxPromptTokens
            text = String(text.prefix(max(0, text.count - (over * 4 + 512))))
            payload = try body(text)
            // Said out loud. A silent cut reads as "it read all of it", which is
            // the failure `project-overview.md` §9 is written against.
            note = "Only the first part of the text was sent — the document is longer than one request allows."
        }

        var request = URLRequest(url: config.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The key goes here and nowhere else. Never in the body, never in a log.
        request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        request.httpBody = payload

        let (data, response) = try await transport(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.http(status: http.statusCode)
        }
        return try decode(data, note: note, provider: "OpenAI · \(config.model)")
    }

    /// What we ask for, and the two things we forbid.
    private static func prompt(isForm: Bool, fieldCount: Int, evidence: [String]) -> String {
        var lines = [
            "You explain government documents to someone who must comply with them and has no",
            "specialist training. They are not skimming — they need to understand what this",
            "document does to them.",
            "",
            "Answer only about the text you are given. If it does not say something, do not supply it.",
            "Never invent a date, an amount, a rate or a deadline. Quote or omit.",
            "Say 'the document does not say' where it does not say.",
            "",
            "Reply as JSON with these keys:",
            "  doc_type      — what kind of document this is",
            "  what_it_is    — two or three sentences: what it is, who sent it, what it does to the reader",
            "  summary       — 6 to 10 items. Each a COMPLETE SENTENCE, not a fragment. Between them,",
            "                  cover: every obligation and who it falls on; every time limit and what it",
            "                  runs from; every restriction, quantity or rate; what happens if it is",
            "                  ignored; and anything a reader would be penalised for missing. Where the",
            "                  document gives a specific figure or period, put it in the sentence.",
            "  urgency       — one of \"act now\", \"soon\", \"informational\", assigned by CONSEQUENCE and",
            "                  not by how near a date is. A binding restriction with no date can still be",
            "                  \"act now\".",
            "  next_steps    — concrete actions the reader can take, in order. No advice, no hedging.",
            "  confidence    — 0 to 1: how well the text supported this reading. Be honest; a low number",
            "                  here is useful and is not held against you.",
            "",
            "Write plainly. Do not pad, and do not repeat the same obligation in two items.",
        ]
        if isForm {
            lines.append("This is a fillable form with \(fieldCount) fields; say what it is for and who files it.")
        }
        if !evidence.isEmpty {
            lines.append("Values already recognised deterministically, with their quotes:")
            lines.append(contentsOf: evidence)
        }
        return lines.joined(separator: "\n")
    }

    private static func decode(_ data: Data, note: String?, provider: String) throws -> Explanation {
        struct Reply: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
            let choices: [Choice]
        }
        struct Payload: Decodable {
            let doc_type: String?
            let what_it_is: String?
            let summary: [String]?
            let urgency: String?
            let next_steps: [String]?
            let confidence: Double?
        }

        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let content = reply.choices.first?.message.content,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(content.utf8)),
              let whatItIs = payload.what_it_is, !whatItIs.isEmpty
        else { throw Failure.malformedReply }

        return Explanation(
            docType: payload.doc_type ?? "Document",
            whatItIs: whatItIs,
            summary: payload.summary ?? [],
            urgency: Urgency(rawValue: payload.urgency ?? "") ?? .informational,
            nextSteps: payload.next_steps ?? [],
            source: .model,
            provider: provider,
            // Carried so the inspector can show it, and **never sufficient on
            // its own** (**I4**). The caller adds the non-model signal that
            // actually decides the band.
            signals: payload.confidence.map { [Signal(Signal.model, $0)] } ?? [],
            note: note)
    }
}
