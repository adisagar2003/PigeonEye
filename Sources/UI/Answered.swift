import Agent
import Contracts
import Foundation
import Gate

// F9 — the loop between "the reader asked something" and "bytes went out".
//
// It lives in layer 4 because it is the only layer allowed to see both Agent
// (which owns the `Document` the pages come from) and Gate (which is the
// egress). `coding-standards.md` §1 — Agent may not import Gate, and must not:
// an agent that opens a socket is a bug against **I1**, not a style issue.
//
// A free function rather than a method on the model, so a test can hold it to
// its promises without a view or a `@MainActor` anywhere near it.

/// What came back, and what it rests on.
public struct Answer: Sendable {
    public let text: String
    /// 1-based, in the order the pages were used. The page the reader was
    /// looking at is always first.
    public let pagesUsed: [Int]
    /// Said out loud when the answer is degraded — cut off at the hop bound,
    /// truncated, or produced without the model at all. Never nil for a
    /// degraded answer: a silent fallback reads as a complete reply.
    public let note: String?
    /// One line per page that left, for the inspector. Page numbers and sizes,
    /// never words — `coding-standards.md` §5.2, and inspector mode is a view,
    /// not an exemption from it.
    public let sends: [String]
}

/// Answer a question about the page the reader has open, letting the model fetch
/// other pages when the answer is not on this one.
///
/// Never throws. Every failure — refused key, rate limit, offline, a reply in a
/// shape we do not understand — comes back as an `Answer` naming the reason.
/// The document on screen is not this function's to take away (**I6**).
public func answered(
    _ doc: Document,
    page: Int,
    question: String,
    history: [Turn],
    config: Gate.Config,
    transport: @escaping Gate.Transport = Gate.defaultTransport
) async -> Answer {
    var turns = Array(history.suffix(Limits.askHistory))
    turns.append(Turn(role: .user, text: opening(doc, page: page, question: question)))

    var used = [page]
    var sends = [record(page: page, chars: pageText(doc, page)?.count ?? 0, to: config.host)]

    // Bounded (**I10**). The last pass withdraws the tool rather than
    // abandoning the turn, so the bound costs a hop, never the answer.
    for hop in 0...Limits.askHops {
        let last = hop == Limits.askHops
        let reply: Gate.Reply
        do {
            reply = try await Gate.answer(turns, system: instructions(doc),
                                          offerTool: !last, config: config, transport: transport)
        } catch {
            return Answer(text: "That question could not be answered — \(why(error)).",
                          pagesUsed: used,
                          note: "The document on screen is unchanged; nothing about it was lost.",
                          sends: sends)
        }

        guard !reply.calls.isEmpty else {
            return Answer(text: reply.text, pagesUsed: used,
                          note: last ? cutOff : nil, sends: sends)
        }

        turns.append(Turn(role: .assistant, text: reply.text, calls: reply.calls))
        for call in reply.calls {
            let wanted = call.requestedPage
            let text = wanted.flatMap { pageText(doc, $0) }
            if let wanted, let text {
                // Only count a page as used once, however often it is asked for.
                if !used.contains(wanted) { used.append(wanted) }
                sends.append(record(page: wanted, chars: text.count, to: config.host))
                turns.append(Turn(role: .tool, text: "Page \(wanted):\n\(text)", callID: call.id))
            } else {
                // A page that was never read has no text, and saying so is
                // something the model can work with. One bad call must not cost
                // the turn.
                turns.append(Turn(
                    role: .tool,
                    text: "That page is not available. This document has \(doc.pagesRead) readable pages.",
                    callID: call.id))
            }
        }
    }

    return Answer(text: "It kept asking for more pages instead of answering.",
                  pagesUsed: used, note: cutOff, sends: sends)
}

private let cutOff = """
    It asked to read more pages than one question allows, so it was stopped. \
    Try asking about a specific page.
    """

/// What the model is for, and the two things it may not do.
///
/// The wording is the one this repo already agreed twice — `spikes/spike_fm.swift`
/// and `eval/openai_run.py` carry it byte-for-byte, and their own comment says
/// to change all of them together. Extended here with the one rule a
/// page-grounded conversation adds: name the page.
private func instructions(_ doc: Document) -> String {
    """
    You explain official government documents to someone who must comply with them \
    and has no specialist training. They are looking at one page and asking about it.

    Use only what the document says. If a detail is not in the text, say it is not stated. \
    Never invent a date, a number, a rate or a name. Quote or omit.

    Name the page every claim came from. If the answer is not on the page in front of \
    them, use \(Call.readPage) to look at another page rather than guessing — this \
    document has \(doc.pagesRead) readable pages.

    Answer in two or three sentences unless more is genuinely needed. Do not give legal, \
    tax or compliance advice; explain what the document says and stop there.
    """
}

/// The question, with the page under it and the values already recognised on
/// that page.
///
/// Those values are the one part of the payload carrying provenance — each has
/// been checked against the transcript at the single construction point that
/// enforces **I2**. Sending them saves the model re-deriving what the machine
/// already knows, and gives it the quote to cite.
private func opening(_ doc: Document, page: Int, question: String) -> String {
    var lines = ["The reader is looking at page \(page). \(doc.pagesReadLine)."]

    if let text = pageText(doc, page), !text.isEmpty {
        lines.append("")
        lines.append("--- page \(page) ---")
        lines.append(text)
        lines.append("--- end of page \(page) ---")
    } else {
        lines.append("")
        lines.append("Page \(page) has no readable text — it may have failed to render.")
    }

    let onPage = doc.findings.filter { $0.page == page }
    if !onPage.isEmpty {
        lines.append("")
        lines.append("Values already recognised on this page, with the words they came from:")
        lines.append(contentsOf: onPage.prefix(40).map {
            "  \($0.label): \($0.value ?? "—") — \"\($0.quote)\""
        })
    }

    lines.append("")
    lines.append("Their question: \(question)")
    return lines.joined(separator: "\n")
}

/// One page's text, capped. Nil when the page is outside what was read — which
/// is what makes a bad `read_page` call answerable rather than fatal.
private func pageText(_ doc: Document, _ number: Int) -> String? {
    guard number >= 1, number <= doc.pages.count else { return nil }
    return String(doc.pages[number - 1].transcript.prefix(Limits.askPageChars))
}

/// What the inspector is allowed to say about a send: which page, how much of
/// it, and where it went. Never the words themselves, never the filename, never
/// the key (`coding-standards.md` §5.2).
private func record(page: Int, chars: Int, to host: String) -> String {
    "page \(page) text → \(host) · \(chars) chars"
}

private func why(_ error: Error) -> String {
    (error as? LocalizedError)?.errorDescription
        ?? (error as? URLError).map { _ in "the machine could not reach the API" }
        ?? "the request did not complete"
}
