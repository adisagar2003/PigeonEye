import Contracts
import Foundation

// Layer 3. **The only place in this package where bytes leave the machine.**
//
// Until this file existed the trust claim was not a promise, it was the absence
// of an API — checkable with one grep. That is no longer true, so the claim now
// rests on this file being short enough to read in full and on
// `scripts/layers.sh` keeping `URLSession` out of everywhere else.
//
// What crosses, and only this (`architecture.md` §6, Trust row):
//   • the text of pages the reader asked a question about
//   • the values already recognised on those pages, with their quotes
// What never crosses, at any tier:
//   • the source file's bytes, its name, its path
//   • any page image or crop — this feature sends no image at all
//   • the key, anywhere but the Authorization header
//
// Nothing here runs on open. It runs when the reader types a question and has
// granted the send for this document (`project-overview.md` §4.1).

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

        public var errorDescription: String? {
            switch self {
            case .http(let status) where status == 401: "the API key was refused"
            case .http(let status) where status == 429: "the API is rate-limiting us"
            case .http(let status): "the API answered \(status)"
            case .malformedReply: "the API answered in a shape we do not understand"
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
