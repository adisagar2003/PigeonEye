import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Gate
@testable import UI

// F4 — the explanation, and the one place bytes leave the machine.
//
// Slice 4.1 is deterministic and makes no model call at all, so a missing or
// broken model can never blank the screen (**I6**). Slice 4.2 adds the cloud leg
// on top, additively.
//
// No test here touches the network: the transport is injected.

private let okResponse = HTTPURLResponse(
    url: URL(string: "https://api.openai.com/v1/chat/completions")!,
    statusCode: 200, httpVersion: nil, headerFields: nil)!

/// A minimal chat-completions reply carrying the JSON payload we ask for.
private let replyData: Data = {
    let payload = """
    {"doc_type":"EPA pesticide label notification",\
    "what_it_is":"A pesticide label amendment acceptance letter.",\
    "summary":["The amended label is accepted.","You may sell the old labelling for 18 months."],\
    "urgency":"soon",\
    "next_steps":["Submit one copy of the final printed labelling."]}
    """
    let envelope = ["choices": [["message": ["content": payload]]]]
    return try! JSONSerialization.data(withJSONObject: envelope)
}()

private func document(
    fields: Int = 0, findings: [Finding] = [], pages: Int = 3
) -> Document {
    Document(
        url: URL(fileURLWithPath: "/tmp/pigeoneye-test.pdf"), kind: .pdf,
        pageCount: pages, pagesRead: pages, capped: false,
        pages: [Page(transcript: "EPA Registration Number: 7969-242",
                     lines: [], tables: 0, lists: 0, data: [:])],
        failedPages: [],
        fields: (0..<fields).map {
            Field(name: "f\($0)", kind: "/Tx", page: 1,
                  region: Region(x: 0.1, y: 0.1, width: 0.2, height: 0.02))
        },
        findings: findings, log: [])
}

private func config() throws -> Gate.Config {
    try #require(Gate.Config.fromEnvironment(["OPENAI_KEY": "sk-test"]))
}

// MARK: - 1 · 4.1 · The local explanation, with no model anywhere

/// **The completeness rule.** A document that yielded nothing still gets an
/// explanation — `project-overview.md` §9: never withhold the explanation
/// because a field is missing. Mark gaps; don't hide behind them.
@Test func a_document_with_nothing_found_still_explains_itself() {
    let e = explain(document())
    #expect(!e.whatItIs.isEmpty)
    #expect(!e.summary.isEmpty, "an empty summary is a blank screen with extra steps")
    #expect(e.source == .local)
}

/// A form's primary output is the fields, not prose (`project-overview.md` §6).
@Test func a_form_is_explained_as_a_form_and_counts_its_fields() {
    let e = explain(document(fields: 105))
    #expect(e.docType.lowercased().contains("form"))
    #expect(e.summary.contains { $0.contains("105") }, "the field count is the headline and it is missing")
    #expect(e.nextSteps.contains { $0.lowercased().contains("fill") })
}

/// Pages read is surfaced wherever the document is described (**I5**).
@Test func the_local_explanation_states_how_much_was_read() {
    let e = explain(document(pages: 45))
    #expect(e.summary.contains { $0.contains("45") })
}

// MARK: - 2 · 4.2 · Nothing leaves without a key

/// No key is a named absence, not a crash and not a silent no-op. The UI uses it
/// to decide whether to offer the cloud leg at all.
@Test func no_key_means_no_configuration_and_no_call() {
    #expect(Gate.Config.fromEnvironment([:]) == nil)
    #expect(Gate.Config.fromEnvironment(["OPENAI_KEY": ""]) == nil)
    #expect(Gate.Config.fromEnvironment(["OPENAI_KEY": "   "]) == nil)
    #expect(Gate.Config.fromEnvironment(["OPENAI_KEY": "sk-test"]) != nil)
}

// MARK: - 3 · I1 — what crosses the boundary, and what never does

/// **The invariant the whole architecture is built around.** The payload carries
/// the transcript and the findings under the import-time grant — never the
/// filename, never the path, never the source bytes, never a page image
/// (`architecture.md` §6, Trust row).
@Test func the_payload_never_carries_the_filename_or_the_path() async throws {
    let box = Box()
    let transport: Gate.Transport = { request in
        await box.set(request.httpBody)
        return (replyData, okResponse)
    }

    _ = try await Gate.explain(
        transcript: "EPA Registration Number: 7969-242",
        findings: [], isForm: false, fieldCount: 0,
        config: try config(), transport: transport)

    let body = try #require(await box.value.map { String(decoding: $0, as: UTF8.self) })
    #expect(!body.contains("pigeoneye-test.pdf"), "the filename crossed the boundary")
    #expect(!body.contains("/tmp/"), "a path crossed the boundary")
    #expect(!body.contains("sk-test"), "the key is in the body as well as the header")
    #expect(body.contains("7969-242"), "the transcript did not cross, so there was nothing to explain")
}

/// The key travels in the Authorization header and nowhere else.
@Test func the_key_travels_in_the_header_only() async throws {
    let box = Box()
    let transport: Gate.Transport = { request in
        await box.set(Data((request.value(forHTTPHeaderField: "Authorization") ?? "").utf8))
        return (replyData, okResponse)
    }
    _ = try await Gate.explain(
        transcript: "hello", findings: [], isForm: false, fieldCount: 0,
        config: try config(), transport: transport)

    #expect(await box.value.map { String(decoding: $0, as: UTF8.self) } == "Bearer sk-test")
}

// MARK: - 4 · I13 — the context window is asserted before the call, not after

/// The 45-page label is ~32,000 tokens of transcript against a ceiling that
/// fails silently when crossed. The estimate is made *before* sending, and the
/// cut is **said out loud** — a silent truncation reads as "it read all of it".
@Test func an_oversized_transcript_is_cut_before_sending_and_says_so() async throws {
    let box = Box()
    let transport: Gate.Transport = { request in
        await box.set(request.httpBody)
        return (replyData, okResponse)
    }
    let huge = String(repeating: "government paperwork ", count: 40_000)

    let explanation = try await Gate.explain(
        transcript: huge, findings: [], isForm: false, fieldCount: 0,
        config: try config(), transport: transport)

    let body = try #require(await box.value)
    #expect(Gate.estimatedTokens(String(decoding: body, as: UTF8.self)) <= Limits.maxPromptTokens,
            "the request went out over the token budget")
    #expect(explanation.note?.isEmpty == false, "the transcript was cut and the reader was not told")
}

@Test func the_token_estimate_grows_with_the_text() {
    #expect(Gate.estimatedTokens("") == 0)
    #expect(Gate.estimatedTokens(String(repeating: "a", count: 4000))
            > Gate.estimatedTokens("short"))
}

// MARK: - 5 · I6 — the local result survives any cloud failure

/// Timeout, 429, 500, a refused key, a garbled body: every one falls through to
/// the local explanation. The cloud leg is **additive only** — it can add, it can
/// never take the screen away.
@Test(arguments: [401, 429, 500, 503])
func a_cloud_failure_falls_back_to_the_local_explanation(status: Int) async throws {
    let transport: Gate.Transport = { request in
        (Data("{}".utf8),
         HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    let doc = document(fields: 63)
    let local = explain(doc)

    let (result, _) = await explained(doc, config: try config(), transport: transport)

    #expect(result.source == .local, "a \(status) took the screen away")
    #expect(result.summary == local.summary, "the local reading was lost on a cloud failure")
    #expect(result.note?.isEmpty == false, "the failure was silent")
}

/// And a transport that throws outright — the offline case.
@Test func an_unreachable_endpoint_falls_back_too() async throws {
    let transport: Gate.Transport = { _ in throw URLError(.notConnectedToInternet) }
    let (result, _) = await explained(document(), config: try config(), transport: transport)

    #expect(result.source == .local)
    #expect(result.note?.isEmpty == false)
}

/// A reply that is valid HTTP but not the shape we asked for.
@Test func a_garbled_reply_falls_back_too() async throws {
    let transport: Gate.Transport = { _ in (Data("not json at all".utf8), okResponse) }
    let (result, _) = await explained(document(), config: try config(), transport: transport)

    #expect(result.source == .local)
    #expect(result.note?.isEmpty == false)
}

/// The happy path, so the fallback tests are not passing for the wrong reason.
@Test func a_good_reply_replaces_the_local_explanation() async throws {
    let transport: Gate.Transport = { _ in (replyData, okResponse) }
    let (result, _) = await explained(document(), config: try config(), transport: transport)

    #expect(result.source == .model)
    #expect(result.whatItIs.contains("pesticide"))
    #expect(result.summary.count == 2)
    #expect(result.urgency == .soon)
}

/// A tiny actor, because the transport closure is `@Sendable` and the test needs
/// to read what it captured.
private actor Box {
    private(set) var value: Data?
    func set(_ data: Data?) { value = data }
}
