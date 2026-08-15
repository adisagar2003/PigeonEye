import Contracts
import Foundation

// F9 — how a question about one page is put to a model. Layer 2, and **pure**:
// it builds strings out of a `Document` and opens nothing.
//
// It lives here rather than beside either caller because there are two callers
// and one fact. The cloud leg (layer 4, over `Gate`) and the on-device leg
// (`LocalModel.swift`, layer 2) must ground a question the *same* way — same
// page text, same evidence, same rule about not inventing a date. Two copies of
// that would drift, and the copy that drifted would be the one that made
// something up (`coding-standards.md` §1.1).

extension Document {
    /// One page's text, capped. `nil` when the page is outside what was read —
    /// which is what makes a badly-aimed `read_page` call answerable rather
    /// than fatal.
    public func askPageText(_ number: Int) -> String? {
        guard number >= 1, number <= pages.count else { return nil }
        return String(pages[number - 1].transcript.prefix(Limits.askPageChars))
    }

    /// What the model is for, and the two things it may not do.
    ///
    /// The wording is the one this repo already agreed twice —
    /// `spikes/spike_fm.swift` and `eval/openai_run.py` carry it byte-for-byte,
    /// and their own comment says to change all of them together.
    ///
    /// `canFetchPages` is the one real difference between the tiers. The
    /// on-device model gets a 4096-token window for prompt *and* answer
    /// (`architecture.md` §3), which one page and a question already fill — so
    /// telling it about a tool it cannot afford to use would only invite it to
    /// promise a page it will never read.
    public func askInstructions(canFetchPages: Bool) -> String {
        var lines = [
            """
            You explain official government documents to someone who must comply with them \
            and has no specialist training. They are looking at one page and asking about it.
            """,
            "",
            """
            Use only what the document says. If a detail is not in the text, say it is not \
            stated. Never invent a date, a number, a rate or a name. Quote or omit.
            """,
            "",
        ]
        if canFetchPages {
            lines.append("""
                Name the page every claim came from. If the answer is not on the page in front \
                of them, use \(Call.readPage) to look at another page rather than guessing — \
                this document has \(pagesRead) readable pages.
                """)
        } else {
            lines.append("""
                You can see only the page below, out of \(pagesRead). If the answer is not on \
                it, say so and say which page is likely to carry it — do not guess at what \
                another page says.
                """)
        }
        lines.append("")
        lines.append("""
            Answer in two or three sentences unless more is genuinely needed. Do not give \
            legal, tax or compliance advice; explain what the document says and stop there.
            """)
        return lines.joined(separator: "\n")
    }

    /// The question, with the page under it and the values already recognised on
    /// that page.
    ///
    /// Those values are the one part of the payload carrying provenance — each
    /// has been checked against the transcript at the single construction point
    /// that enforces **I2**. Sending them saves the model re-deriving what the
    /// machine already knows, and gives it a quote to cite.
    public func askOpening(page: Int, question: String, evidence: Bool = true) -> String {
        var lines = ["The reader is looking at page \(page). \(pagesReadLine)."]

        if let text = askPageText(page), !text.isEmpty {
            lines.append("")
            lines.append("--- page \(page) ---")
            lines.append(text)
            lines.append("--- end of page \(page) ---")
        } else {
            lines.append("")
            lines.append("Page \(page) has no readable text — it may have failed to render.")
        }

        let onPage = findings.filter { $0.page == page }
        if evidence, !onPage.isEmpty {
            lines.append("")
            lines.append("Values already recognised on this page, with the words they came from:")
            // Both bounds matter. A quote is a verbatim OCR line and a page can
            // carry many of them, so 40 unbounded quotes is an unbounded
            // payload — and an unbounded payload is what I13 is asserted
            // against downstream.
            lines.append(contentsOf: onPage.prefix(40).map {
                "  \($0.label): \($0.value ?? "—") — \"\($0.quote.prefix(Limits.askQuoteChars))\""
            })
        }

        lines.append("")
        lines.append("Their question: \(question.prefix(Limits.askQuestionChars))")
        return lines.joined(separator: "\n")
    }
}
