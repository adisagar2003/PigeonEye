import AppKit
import Foundation
import Testing

@testable import Agent
@testable import Contracts
@testable import Gate
@testable import Tools
@testable import UI

// F9 — asking about the page that is open.
//
// The feature is a conversation grounded on one page, with the model allowed to
// ask for other pages it has not been shown. Three things have to hold, and each
// has a test below rather than a comment:
//
//   • **I1** — nothing leaves before the reader grants it, and only page text
//     leaves at all.
//   • **I10** — the hop loop is bounded. A model that keeps asking for pages
//     must be cut off and still produce an answer.
//   • **I6** — a failed or absent endpoint costs the answer, never the document.
//
// No test here touches the network: `Gate.Transport` is injected everywhere.

private let okResponse = HTTPURLResponse(
    url: URL(string: "https://api.openai.com/v1/chat/completions")!,
    statusCode: 200, httpVersion: nil, headerFields: nil)!

private func config() throws -> Gate.Config {
    try #require(Gate.Config.fromEnvironment(["OPENAI_KEY": "sk-test"]))
}

/// A chat-completions reply carrying prose.
private func says(_ text: String) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["role": "assistant", "content": text]]],
    ])
}

/// A chat-completions reply asking to read another page.
private func wantsPage(_ number: Int, id: String = "call_1") -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": [
            "role": "assistant",
            "content": NSNull(),
            "tool_calls": [[
                "id": id, "type": "function",
                "function": ["name": "read_page", "arguments": "{\"page\": \(number)}"],
            ]],
        ], "finish_reason": "tool_calls"]],
    ])
}

/// A three-page document whose pages are trivially distinguishable, so a test
/// can assert *which* page's words were sent.
private func document(pages: Int = 3, findings: [Finding] = []) -> Document {
    Document(
        url: URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"), kind: .pdf,
        pageCount: pages, pagesRead: pages, capped: false,
        pages: (1...pages).map {
            Page(transcript: "This is page \($0). Marker\($0)-\(String(repeating: "x", count: 20)).",
                 lines: [], tables: 0, lists: 0, data: [:])
        },
        failedPages: [], fields: [], findings: findings, log: [])
}

/// A box for "was this closure called?", because the closure is `@Sendable` and
/// a captured `var` is not.
private final class Reached: @unchecked Sendable {
    private(set) var value = false
    func mark() { value = true }
}

/// Keeps whatever a `@Sendable` closure was handed, so a test can inspect it.
private final class Captured: @unchecked Sendable {
    private(set) var value: String?
    func set(_ text: String) { value = text }
}

/// Records every request the code tried to make, and answers from a script.
private final class Recorder: @unchecked Sendable {
    private(set) var sent: [URLRequest] = []
    private var replies: [Data]

    init(_ replies: [Data]) { self.replies = replies }

    /// The last scripted reply repeats, so a bounded loop can be driven past its
    /// bound without the script having to know the bound.
    var transport: Gate.Transport {
        { [self] request in
            sent.append(request)
            let data = replies.count > 1 ? replies.removeFirst() : replies[0]
            return (data, okResponse)
        }
    }

    /// Every byte of every request body, as one string. What a scrape of the
    /// wire would see.
    var wire: String { sent.map { String(decoding: $0.httpBody ?? Data(), as: UTF8.self) }.joined() }
}

// MARK: - 1 · Grounding — the page you are looking at

/// The question is answered about the page on screen, so that page's words are
/// what go out — and no others go with them uninvited. Sending the whole
/// document on every question would make "this page's text is sent" a lie.
@Test func the_question_carries_the_open_page_and_not_the_rest() async throws {
    let tap = Recorder([says("The document does not say.")])
    _ = await answered(document(), page: 2, question: "what does this mean?",
                       history: [], config: try config(), transport: tap.transport)

    #expect(tap.wire.contains("Marker2"), "the open page's text never went out")
    #expect(!tap.wire.contains("Marker1"), "a page the reader was not looking at was sent")
    #expect(!tap.wire.contains("Marker3"), "a page the reader was not looking at was sent")
}

/// Values already recognised deterministically travel with the question, quotes
/// included. They are the one part of the payload that carries provenance, and
/// leaving them out asks the model to re-derive what the machine already knows.
@Test func recognised_values_on_the_page_travel_with_the_question() async throws {
    let transcript = document().pages[0].transcript
    let found = try #require(finding(
        label: "EPA reg. no.", kind: .identifier, value: "524-529", quote: transcript, page: 1,
        region: Region(x: 0, y: 0, width: 1, height: 0.1),
        origin: .validator, validated: true, conf: 0.7,
        in: transcript))

    let tap = Recorder([says("ok")])
    _ = await answered(document(findings: [found]), page: 1, question: "which registration?",
                       history: [], config: try config(), transport: tap.transport)

    #expect(tap.wire.contains("524-529"))
}

// MARK: - 2 · The hop — pages it was not shown

/// The whole point of the tool loop: the answer is on page 3, the reader is on
/// page 1, and the model can go and get it.
@Test func a_read_page_call_fetches_that_page_and_records_it() async throws {
    let tap = Recorder([wantsPage(3), says("It is on page 3.")])
    let answer = await answered(document(), page: 1, question: "where are the rates?",
                                history: [], config: try config(), transport: tap.transport)

    #expect(answer.text.contains("page 3"))
    #expect(answer.pagesUsed == [1, 3], "the pages an answer rests on are what the inspector shows")
    #expect(tap.wire.contains("Marker3"), "the fetched page's text never reached the model")
}

/// **I10.** A model that never stops asking is cut off, and the reader still
/// gets a sentence. An unbounded loop here is an unbounded bill and a hang.
@Test func a_model_that_only_ever_asks_for_pages_is_cut_off_and_still_answers() async throws {
    let tap = Recorder([wantsPage(2)])  // repeats forever
    let answer = await answered(document(), page: 1, question: "?",
                                history: [], config: try config(), transport: tap.transport)

    #expect(tap.sent.count <= Limits.askHops + 1, "the hop loop is not bounded")
    #expect(!answer.text.isEmpty, "a cut-off loop still owes the reader a sentence")
    #expect(answer.note != nil, "a cut-off loop that says nothing about it reads as a complete answer")
}

/// One bad call must not cost the turn. A page that was never read has no text,
/// and saying so is an answer the model can work with.
@Test func a_call_for_a_page_that_was_never_read_does_not_lose_the_answer() async throws {
    let tap = Recorder([wantsPage(99), says("Page 99 does not exist; on page 1 it says…")])
    let answer = await answered(document(), page: 1, question: "what about page 99?",
                                history: [], config: try config(), transport: tap.transport)

    #expect(!answer.text.isEmpty)
    #expect(answer.pagesUsed == [1], "a page that was never read cannot be a page the answer rests on")
}

// MARK: - 3 · I1 · Nothing leaves un-granted

/// The grant is per document and is taken once, in the panel, before the first
/// question — `project-overview.md` §4.1. Until it is taken, the transport is
/// never reached.
@MainActor
@Test func nothing_is_sent_before_the_reader_grants_it() async throws {
    let tap = Recorder([says("hello")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport)
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))

    await model.ask("what does this say?")
    #expect(tap.sent.isEmpty, "a question was sent before the reader agreed to send anything")
    #expect(model.askPending != nil, "the question was dropped instead of held for the grant")

    model.grantAsk()
    await model.sendPending()
    #expect(tap.sent.count == 1)
}

/// Opening another document drops the conversation and the grant with it
/// (**I9**). A grant that outlives its document is a grant for a document the
/// reader never saw.
@MainActor
@Test func opening_another_document_clears_the_chat_and_the_grant() async throws {
    let tap = Recorder([says("hello")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport)
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.grantAsk()
    await model.ask("hello?")
    #expect(!model.turns.isEmpty)

    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-other.pdf"))
    #expect(model.turns.isEmpty, "the previous document's conversation survived into this one")
    #expect(model.askGranted == false, "a grant for one document was reused for another")
    #expect(model.sends.isEmpty)
}

// MARK: - 4 · I6 · A broken endpoint costs the answer, never the document

@MainActor
@Test func a_refused_key_leaves_the_document_on_screen() async throws {
    let refuse: Gate.Transport = { request in
        (Data(), HTTPURLResponse(url: request.url!, statusCode: 401,
                                 httpVersion: nil, headerFields: nil)!)
    }
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: refuse)
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.grantAsk()
    await model.ask("anything?")

    #expect(model.doc != nil, "a failed question threw the document away")
    #expect(model.turns.last?.text.contains("key") == true, "the reason was swallowed")
}

/// A 200 with nothing in it is a failure, not an answer. Rendering an empty
/// bubble as success is the "empty result dressed as success" of
/// `project-overview.md` §9.
@Test func an_empty_reply_is_not_rendered_as_an_answer() async throws {
    let empty = Recorder([try! JSONSerialization.data(withJSONObject: ["choices": []])])
    let answer = await answered(document(), page: 1, question: "?",
                                history: [], config: try config(), transport: empty.transport)

    #expect(answer.note != nil, "an empty reply was passed off as an answer")
    #expect(!answer.text.isEmpty, "an empty reply left the reader with a blank bubble")
}

// MARK: - 5 · §5.2 · What the inspector may say

/// Inspector mode is a view, not an exemption. It shows that page 2's text went
/// out and how much of it — never the text.
@MainActor
@Test func the_send_record_names_the_page_and_never_its_words() async throws {
    let tap = Recorder([says("fine")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport)
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.grantAsk()
    model.page = 2
    await model.ask("what is this?")

    let record = model.sends.joined(separator: " ")
    #expect(record.contains("2"), "the record does not say which page left")
    #expect(!record.contains("Marker2"), "the document's own words are in the inspector record")
    #expect(!record.contains("sk-test"), "the key is in the inspector record")
    #expect(!record.contains("pigeoneye-ask"), "the filename is in the inspector record")
}

// MARK: - 6 · The tier the reader picked has to mean something

/// **The disclosure bug.** `readingTier` was a stored preference only the
/// onboarding screen ever read, so a reader who chose "On this Mac" was still
/// handed a cloud-backed ask panel. Worse than an undisclosed fallback: one the
/// reader had explicitly declined.
@Test func choosing_on_this_mac_turns_asking_off() throws {
    let offered = try config()
    #expect(ReaderModel.askConfig(tier: .openAI, offered: offered) == offered)
    #expect(ReaderModel.askConfig(tier: .local, offered: offered) == nil,
            "the local tier still resolves to a cloud endpoint")
}

@MainActor
@Test func the_local_tier_sends_nothing_even_with_a_key_in_the_environment() async throws {
    let tap = Recorder([says("hello")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport)
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.honour(.local)

    #expect(model.cloud == nil, "the panel would still offer a field")
    model.grantAsk()
    await model.ask("what does this say?")
    #expect(tap.sent.isEmpty, "the reader declined the cloud and it was sent anyway")
}

// MARK: - 7 · I13 is an assertion, not an effort

/// Dropping history cannot help when the *newest* turn is over budget, and the
/// trim loop stops at one turn — so an oversized page or a pasted wall of text
/// used to be trimmed as far as possible and then posted regardless.
@Test func an_oversized_question_is_refused_before_anything_is_sent() async throws {
    let tap = Recorder([says("never reached")])
    let huge = String(repeating: "x", count: Limits.maxPromptTokens * 8)

    await #expect(throws: Gate.Failure.promptTooLarge) {
        try await Gate.answer([Turn(role: .user, text: huge)], system: "s",
                              offerTool: false, config: try config(), transport: tap.transport)
    }
    #expect(tap.sent.isEmpty, "an over-budget request went out anyway (I13)")
}

/// The guard above is the backstop. The first line of defence is that the two
/// unbounded inputs — a pasted question, and quotes that are verbatim OCR lines
/// — are capped before they can reach it. Together they mean a real document
/// cannot produce a refused request, which is why the guard is unreachable in
/// practice and still worth having.
@Test func a_pasted_wall_of_text_is_capped_rather_than_refused() async throws {
    let tap = Recorder([says("fine")])
    let wall = String(repeating: "x", count: Limits.maxPromptTokens * 8)
    let answer = await answered(document(), page: 1, question: wall,
                                history: [], config: try config(), transport: tap.transport)

    #expect(tap.sent.count == 1, "a capped question should still be answerable")
    #expect(answer.text == "fine")
    #expect(Gate.estimatedTokens(tap.wire) <= Limits.maxPromptTokens,
            "the request went out over budget (I13)")
    #expect(tap.wire.count < wall.count, "the question was not capped")
}

// MARK: - 8 · The bound that counts what leaves

/// `askHops` bounds *rounds*, not pages. One reply may legally carry a hundred
/// `read_page` calls, and processing them all sends a whole document inside a
/// loop that calls itself bounded.
@Test func one_over_eager_reply_cannot_send_the_whole_document() async throws {
    // Ten pages, and a reply that asks for every one of them at once.
    let calls = (2...10).map { number in
        ["id": "call_\(number)", "type": "function",
         "function": ["name": "read_page", "arguments": "{\"page\": \(number)}"]] as [String: Any]
    }
    let greedy = try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["role": "assistant", "content": NSNull(), "tool_calls": calls]]],
    ])

    let tap = Recorder([greedy, says("done")])
    let answer = await answered(document(pages: 10), page: 1, question: "everything?",
                                history: [], config: try config(), transport: tap.transport)

    #expect(answer.pagesUsed.count <= Limits.askPages,
            "one reply sent \(answer.pagesUsed.count) pages past a bound of \(Limits.askPages)")
    for number in answer.pagesUsed where number > Limits.askPages + 1 {
        Issue.record("page \(number) left the machine despite the budget")
    }
}

// MARK: - 9 · The ledger records what left, not what was attempted

/// `sends` used to be written *before* the transport ran, so an offline machine
/// still produced "page 1 text → host". Claiming text left when it did not is
/// the dangerous direction for a privacy-first reader to be wrong in.
@Test func an_offline_machine_does_not_report_text_as_having_left() async throws {
    let offline: Gate.Transport = { _ in throw URLError(.notConnectedToInternet) }
    let answer = await answered(document(), page: 1, question: "?",
                                history: [], config: try config(), transport: offline)

    #expect(answer.sends.allSatisfy { $0.contains("may not have arrived") },
            "an unsent page is listed as having left the machine")
}

/// A 401 is the server answering, so the bytes did leave. Under-reporting that
/// is the same failure in the opposite direction.
@Test func a_rejected_request_still_reports_that_the_text_left() async throws {
    let refuse: Gate.Transport = { request in
        (Data(), HTTPURLResponse(url: request.url!, statusCode: 401,
                                 httpVersion: nil, headerFields: nil)!)
    }
    let answer = await answered(document(), page: 1, question: "?",
                                history: [], config: try config(), transport: refuse)

    #expect(answer.sends.count == 1)
    #expect(!answer.sends[0].contains("may not have arrived"),
            "the server answered, so the page did leave — saying otherwise under-reports egress")
}

// MARK: - 10 · The on-device tier, which is half the product's pitch

/// `project-overview.md` §3: *"On a machine with a local reasoning model,
/// nothing leaves — full stop."* The test for that sentence is that the
/// transport is never constructed, not that a comment says so.
@MainActor
@Test func the_local_tier_answers_without_touching_the_transport() async throws {
    let tap = Recorder([says("should never be reached")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport,
                            respond: { _, _ in "The restricted-entry interval is 12 hours." })
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.honour(.local, localReady: true)

    await model.ask("what is the REI?")

    #expect(tap.sent.isEmpty, "the local tier reached the network")
    #expect(model.turns.last?.text.contains("12 hours") == true)
    #expect(model.sends.isEmpty, "the inspector claims something left on a local answer")
}

/// **Nothing leaves, so there is nothing to consent to.** A card asking
/// permission for something that does not happen is the same theatre §4.1 rules
/// out for crops — it reads as evidence that something *is* being sent.
@MainActor
@Test func the_local_tier_asks_for_no_grant() async throws {
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: { _ in
                                Issue.record("the transport was reached"); return (Data(), okResponse)
                            },
                            respond: { _, _ in "answered here" })
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.honour(.local, localReady: true)

    #expect(model.needsGrant == false)
    await model.ask("no consent card should appear")
    #expect(model.askPending == nil, "the question was held for a grant that is not needed")
    #expect(model.turns.last?.text == "answered here")
}

/// The on-device model wins when it is there. A preference the code consults
/// second is a preference the code does not hold.
@MainActor
@Test func the_local_tier_is_preferred_over_a_configured_endpoint() async throws {
    let tap = Recorder([says("cloud")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport,
                            respond: { _, _ in "local" })
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.honour(.local, localReady: true)
    model.grantAsk()

    await model.ask("which tier?")
    #expect(model.turns.last?.text == "local")
    #expect(tap.sent.isEmpty)
}

/// The local tier can be *chosen* and still be unavailable — Apple Intelligence
/// is a System Settings toggle, and on this machine it is off. The panel has to
/// say which of the three reasons it is, because one is fixable in a minute and
/// one is not fixable at all.
@MainActor
@Test func a_chosen_but_unavailable_local_tier_says_why_and_sends_nothing() async throws {
    let tap = Recorder([says("cloud")])
    let model = ReaderModel(read: { _, _ in document() },
                            cloud: try config(), transport: tap.transport,
                            respond: { _, _ in "local" })
    await model.open(URL(fileURLWithPath: "/tmp/pigeoneye-ask.pdf"))
    model.honour(.local, localReady: false)

    #expect(model.canAsk == false, "an unavailable local tier still offered a field")
    #expect(model.localBlocker != nil, "asking is off and the reader is not told why")
    await model.ask("anything?")
    #expect(tap.sent.isEmpty, "it quietly fell back to the endpoint the reader declined")
}

/// **I13 on the tier the invariant was written for.** Apple's window is 4096
/// tokens for prompt *and* answer, and it fails as a thrown framework error at
/// the far end.
///
/// The page is already capped at `askPageChars`, so the block that can actually
/// overflow is the evidence: forty recognised values whose quotes are verbatim
/// OCR lines can be larger than the page they describe. Evidence gives way
/// first, because the model can re-derive it from the text underneath — the
/// page it cannot.
@Test func evidence_gives_way_before_the_page_does() async throws {
    let long = String(repeating: "quotation ", count: 400)   // ~4,000 chars
    let page = Page(transcript: long, lines: [], tables: 0, lists: 0, data: [:])
    let bulky = (0..<40).compactMap {
        finding(label: "value \($0)", kind: .other, value: "v", quote: long, page: 1,
                region: Region(x: 0, y: 0, width: 1, height: 0.1),
                origin: .validator, validated: true, conf: 0.7, in: long)
    }
    let doc = Document(
        url: URL(fileURLWithPath: "/tmp/pigeoneye-bulky.pdf"), kind: .pdf,
        pageCount: 1, pagesRead: 1, capped: false, pages: [page],
        failedPages: [], fields: [], findings: bulky, log: [])

    #expect(bulky.count == 40, "the fixture did not build the evidence it is testing")

    let seen = Captured()
    _ = try await answeredLocally(doc, page: 1, question: "what is this?",
                                  respond: { _, prompt in seen.set(prompt); return "answered" })

    let prompt = try #require(seen.value)
    #expect(Gate.estimatedTokens(prompt) <= Limits.localPromptTokens,
            "an over-window prompt was handed to the on-device model")
    #expect(prompt.contains("quotation"), "the page itself was dropped — that costs the answer")
    #expect(!prompt.contains("value 39"), "the evidence block was kept and the window blown")
}

/// A page that fits must actually go, or the guard above is just an off switch.
@Test func an_ordinary_page_fits_the_on_device_window() async throws {
    let text = try await answeredLocally(document(), page: 1, question: "what is this?",
                                         respond: { instructions, prompt in
        #expect(instructions.contains("only the page below"),
                "the on-device tier was told about a tool it cannot afford to use")
        #expect(prompt.contains("Marker1"))
        return "It is page 1."
    })
    #expect(text == "It is page 1.")
}

/// The failure has to name itself, and has to say the thing a reader will
/// otherwise assume did happen.
@Test func a_local_failure_says_nothing_left_the_machine() async throws {
    let answer = await answeredHere(document(), page: 1, question: "?",
                                    respond: { _, _ in throw LocalModel.Failure.empty })
    #expect(answer.sends.isEmpty)
    #expect(answer.note?.contains("Nothing left this machine") == true)
}

// MARK: - 11 · The `?` monitor, which now has a text field to share the app with

/// The bare-`?` monitor sees every keystroke in the app, including the ones
/// meant for the ask field. Before this, typing "what does ? mean" opened the
/// shortcuts sheet and ate the character.
@Test func a_question_mark_typed_into_a_field_is_a_question_mark() {
    #expect(ShortcutsSheet.opensList(characters: "?", modifiers: [], typing: false))
    #expect(!ShortcutsSheet.opensList(characters: "?", modifiers: [], typing: true),
            "the shortcuts sheet is eating characters out of the ask field")
}
