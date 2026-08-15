import Contracts
import Foundation

// Layer 3. **The only place in this package where bytes leave the machine.**
//
// Until this file existed the trust claim was not a promise, it was the absence
// of an API — checkable with one grep. That is no longer true, so the claim now
// rests on this file being short enough to read in full and on
// `scripts/layers.sh` keeping `URLSession` out of everywhere else.
//
// Two functions send: `answer` (F9, a question about a page) and `explain`
// (F4.2, what the document is). They share one transport, one budget assertion
// and one key header on purpose — two egress paths with two sets of rules is
// how one of them quietly grows a third.
//
// What crosses, and only this (`architecture.md` §6, Trust row):
//   • transcript text — the pages asked about, or the document being explained
//   • the values already recognised in that text, with their quotes
// What never crosses, at any tier:
//   • the source file's bytes, its name, its path
//   • any page image or crop — neither feature sends an image at all
//   • the key, anywhere but the Authorization header
//
// Nothing here runs on open. It runs when the reader types a question, or
// presses Explain, having granted the send for this document
// (`project-overview.md` §4.1).

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
        /// asking at all. A box that cannot send is worse than no box.
        ///
        /// Both key names are accepted because the repo already contains both:
        /// `.env` holds `OPENAI_KEY`, `eval/openai_run.py` reads
        /// `OPENAI_API_KEY`. Picking one and calling the other a mistake would
        /// break whichever half of the repo lost.
        public static func fromEnvironment(_ env: [String: String]) -> Config? {
            let key = (env["OPENAI_KEY"] ?? env["OPENAI_API_KEY"] ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }

            let host = env["OPENAI_BASE_URL"] ?? "https://api.openai.com/v1"
            guard let baseURL = URL(string: host) else { return nil }
            return Config(baseURL: baseURL, model: env["OPENAI_MODEL"] ?? "gpt-4o-mini", key: key)
        }

        /// Named on screen before a word is sent, so "it went to a model" is
        /// never something the reader has to infer.
        public var host: String { baseURL.host() ?? baseURL.absoluteString }
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
        /// Refused **before** the request goes out. The distinction matters to
        /// more than error text: `.http` means the server answered, so bytes
        /// left the machine; this one means nothing did.
        case promptTooLarge

        public var errorDescription: String? {
            switch self {
            case .http(let status) where status == 401: "the API key was refused"
            case .http(let status) where status == 429: "the API is rate-limiting us"
            case .http(let status): "the API answered \(status)"
            case .malformedReply: "the API answered in a shape we do not understand"
            case .promptTooLarge: "the question and its page are larger than one request allows"
            }
        }

        /// Whether this failure happened after the request had already gone.
        /// The inspector needs to know: reporting that nothing left when it did
        /// is the dangerous direction for a privacy-first reader to be wrong.
        public var afterSending: Bool {
            switch self {
            case .http, .malformedReply: true
            case .promptTooLarge: false
            }
        }
    }

    /// What one round trip came back with: prose, a request to read a page, or
    /// both. Never neither — an empty reply is `malformedReply`, because a blank
    /// bubble rendered as success is the failure `project-overview.md` §9 names.
    public struct Reply: Sendable, Equatable {
        public let text: String
        public let calls: [Call]
    }

    /// A character-count estimate of tokens.
    ///
    /// ponytail: not a tokeniser. ~4 characters per token over-counts ordinary
    /// English, which errs toward sending *less* than allowed — the safe
    /// direction for a limit that fails silently (**I13**).
    public static func estimatedTokens(_ text: String) -> Int {
        text.count / 4
    }

    /// Ask the model a question about pages it has been given, optionally
    /// offering it the one tool that can fetch another page.
    ///
    /// One round trip. The loop that decides whether to go round again lives in
    /// layer 4, where the `Document` those pages come from is in scope — layer 3
    /// knows about bytes on a wire and nothing else.
    public static func answer(
        _ turns: [Turn],
        system: String,
        offerTool: Bool,
        config: Config,
        transport: Transport = Gate.defaultTransport
    ) async throws -> Reply {
        func body(_ turns: [Turn]) throws -> Data {
            var payload: [String: Any] = [
                "model": config.model,
                "temperature": 0,
                "messages": [["role": "system", "content": system]] + turns.map(wire),
            ]
            if offerTool { payload["tools"] = [readPageTool] }
            return try JSONSerialization.data(withJSONObject: payload)
        }

        // I13 — the budget is asserted against **the bytes that actually go
        // out**, before they go out. Budgeting the prompt text alone leaves the
        // JSON envelope unaccounted for, which is how a request lands just over
        // a limit that fails silently.
        //
        // Bounded, per I10: drop the oldest turn and re-measure, never a
        // while-true. The turn holding the current page is the *last* one, so
        // what goes first is the conversation's history — the part the reader
        // can most afford to lose.
        var carried = turns
        var payload = try body(carried)
        while estimatedTokens(String(decoding: payload, as: UTF8.self)) > Limits.maxPromptTokens,
              carried.count > 1 {
            carried.removeFirst()
            payload = try body(carried)
        }

        // **I13 is an assertion, not an effort.** Dropping history cannot help
        // when the *newest* turn is itself over budget, and the loop above
        // stops at one turn — so without this guard an oversized page or a
        // pasted wall of text was trimmed as far as possible and then posted
        // anyway. The limit fails silently at the far end, which is exactly why
        // it is checked at this one.
        guard estimatedTokens(String(decoding: payload, as: UTF8.self)) <= Limits.maxPromptTokens
        else { throw Failure.promptTooLarge }

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
        return try decode(data)
    }

    /// Ask the model what the document is (F4.2).
    ///
    /// The caller has already assembled a complete local explanation — this is
    /// additive to it, never a prerequisite (**I6**). Throwing here costs the
    /// reader nothing but the upgrade.
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

        // **I13 is an assertion, not an effort**, and the loop above is only an
        // effort: it trims the transcript, so a large fixed block — the
        // instructions plus 60 evidence lines with long quotes — can still sit
        // over the ceiling once the transcript has been cut to nothing. Without
        // this guard that request went out anyway, to fail silently at the far
        // end. `.promptTooLarge` is the one failure that means *nothing left the
        // machine*, which is why it is checked here rather than after.
        guard estimatedTokens(String(decoding: payload, as: UTF8.self)) <= Limits.maxPromptTokens
        else { throw Failure.promptTooLarge }

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
        struct Envelope: Decodable {
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

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let content = envelope.choices.first?.message.content,
              let payload = try? JSONDecoder().decode(Payload.self, from: Data(content.utf8))
        else { throw Failure.malformedReply }

        func filled(_ items: [String]?) -> [String] {
            (items ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let summary = filled(payload.summary)
        let nextSteps = filled(payload.next_steps)

        // **A partial reply is a failure, not a result.** The caller replaces a
        // complete local explanation with this one, so accepting a response that
        // decoded but said nothing — an absent summary defaulting to `[]`, an
        // unrecognised urgency defaulting to `.informational` — blanks the
        // checklist or downgrades the urgency while reporting success. That is a
        // worse outcome than no cloud call at all, and it violates I6: the local
        // result may only ever be *added to*. Every Tier 1 field is required.
        guard let whatItIs = payload.what_it_is,
              !whatItIs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !summary.isEmpty,
              !nextSteps.isEmpty,
              let urgency = payload.urgency.flatMap(Urgency.init(rawValue:))
        else { throw Failure.malformedReply }

        return Explanation(
            docType: payload.doc_type ?? "Document",
            whatItIs: whatItIs,
            summary: summary,
            urgency: urgency,
            nextSteps: nextSteps,
            source: .model,
            provider: provider,
            // Carried so the inspector can show it, and **never sufficient on
            // its own** (**I4**). The caller adds the non-model signal that
            // actually decides the band.
            signals: payload.confidence.map { [Signal(Signal.model, $0)] } ?? [],
            note: note)
    }

    /// The one tool. Shaped as the Chat Completions API defines it:
    /// `{type, function: {name, description, parameters}}`, parameters being a
    /// JSON Schema object.
    private static var readPageTool: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": Call.readPage,
                "description": """
                    Read the full text of another page of this document. Use it when the answer \
                    is not on the page the reader is looking at. Say which page an answer came from.
                    """,
                "parameters": [
                    "type": "object",
                    "properties": ["page": ["type": "integer", "description": "1-based page number"]],
                    "required": ["page"],
                ],
            ],
        ]
    }

    /// One turn, in the shape the API expects. A `.tool` turn is paired to its
    /// request by `tool_call_id`; an `.assistant` turn that asked for a page
    /// carries `tool_calls` and may carry no content at all.
    private static func wire(_ turn: Turn) -> [String: Any] {
        switch turn.role {
        case .user:
            return ["role": "user", "content": turn.text]
        case .tool:
            return ["role": "tool", "tool_call_id": turn.callID ?? "", "content": turn.text]
        case .assistant:
            var message: [String: Any] = ["role": "assistant", "content": turn.text]
            if !turn.calls.isEmpty {
                message["tool_calls"] = turn.calls.map { call in
                    ["id": call.id, "type": "function",
                     "function": ["name": call.name, "arguments": call.arguments]] as [String: Any]
                }
            }
            return message
        }
    }

    private static func decode(_ data: Data) throws -> Reply {
        struct Envelope: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    struct ToolCall: Decodable {
                        struct Function: Decodable { let name: String; let arguments: String }
                        let id: String
                        let function: Function
                    }
                    let content: String?
                    let tool_calls: [ToolCall]?
                }
                let message: Message
            }
            let choices: [Choice]
        }

        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let message = envelope.choices.first?.message
        else { throw Failure.malformedReply }

        let calls = (message.tool_calls ?? []).map {
            Call(id: $0.id, name: $0.function.name, arguments: $0.function.arguments)
        }
        let text = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        // Neither prose nor a request to read something is not an answer. 200
        // with an empty body is the case `issues.md` 4.2 names explicitly.
        guard !text.isEmpty || !calls.isEmpty else { throw Failure.malformedReply }
        return Reply(text: text, calls: calls)
    }
}
