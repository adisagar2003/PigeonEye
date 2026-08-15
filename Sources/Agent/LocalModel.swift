import Contracts
import Foundation
import FoundationModels

// Layer 2. The on-device reasoning tier — and the half of the product's pitch
// that had no code behind it until now.
//
// `project-overview.md` §3: *"On a machine with a local reasoning model, nothing
// leaves — full stop."* Before this file that sentence described an intention.
// A reader who picked "On this Mac" got an ask panel that was switched off, so
// the honest local option was also the useless one, and the only way to ask a
// question was to pick the cloud.
//
// **Why this feature is where the local tier becomes viable at all.** Apple's
// window is 4096 tokens for prompt *and* answer, fixed (`architecture.md` §3),
// and that is what makes whole-document explanation need chunking and
// map-reduce. But one page of an EPA label measures ~530 tokens. A single-page
// question plus its instructions and its answer fits inside the window with
// room to spare — so the constraint that makes F4 hard does not bind here. This
// is the one workload the on-device model can do today, unchunked.
//
// It holds no socket, and `scripts/layers.sh` keeps `import FoundationModels`
// in this directory. Inference in-process is not egress; that distinction is
// the whole reason this tier is worth having.

/// Whether macOS has the on-device model on this machine.
///
/// Deliberately a function and not a stored value: macOS downloads and evicts
/// these assets on its own schedule, so anything cached goes stale the moment
/// the user leaves for System Settings and comes back. Ask again instead.
public func localModelAvailable() -> Bool {
    SystemLanguageModel.default.isAvailable
}

/// Why the on-device model cannot run, in words a reader can act on.
///
/// The distinction matters and the SDK draws it: `deviceNotEligible` is a dead
/// end, `appleIntelligenceNotEnabled` is a settings toggle away. Telling
/// someone with an eligible Mac to buy a new one would be wrong, and telling
/// someone with an ineligible one to check settings would waste their time.
/// Measured on this machine: `appleIntelligenceNotEnabled` — the hardware is
/// fine (`progress-tracker.md`).
public func localModelBlocker() -> String? {
    switch SystemLanguageModel.default.availability {
    case .available:
        return nil
    case .unavailable(.appleIntelligenceNotEnabled):
        return "Apple Intelligence is switched off. Turn it on in System Settings to ask questions without anything leaving this Mac."
    case .unavailable(.modelNotReady):
        return "macOS is still downloading the on-device model. This finishes on its own."
    case .unavailable(.deviceNotEligible):
        return "This Mac cannot run the on-device model."
    case .unavailable:
        return "The on-device model is not available on this Mac."
    }
}

public enum LocalModel {
    /// The seam. Every other model call in this package is injectable so tests
    /// never reach the real thing — `Agent.read`, `Gate.Transport` — and this
    /// is the same idea for a framework that cannot be reached at all on a
    /// machine with Apple Intelligence switched off.
    public typealias Respond = @Sendable (_ instructions: String, _ prompt: String) async throws -> String

    /// The real one.
    public static let session: Respond = { instructions, prompt in
        let session = LanguageModelSession(instructions: instructions)
        return try await session.respond(to: prompt).content
    }

    public enum Failure: Error, LocalizedError, Equatable {
        case unavailable(String)
        case tooLong
        case empty

        public var errorDescription: String? {
            switch self {
            case .unavailable(let why): why
            case .tooLong: "this page is longer than the on-device model can hold at once"
            case .empty: "the on-device model returned nothing"
            }
        }
    }
}

/// Answer a question about one page **without anything leaving the machine**.
///
/// No tool loop and no page fetching, deliberately: the window that makes this
/// tier possible for one page is the same window that makes several pages
/// impossible. The instructions say so, so the model tells the reader which
/// page probably carries the answer instead of inventing what is on it.
public func answeredLocally(
    _ doc: Document,
    page: Int,
    question: String,
    respond: LocalModel.Respond = LocalModel.session
) async throws -> String {
    let instructions = doc.askInstructions(canFetchPages: false)

    // **I13, on the tier the invariant was written for.** 4096 tokens covers
    // prompt *and* answer and the SDK states no number, so the budget leaves
    // room for a reply rather than spending the whole window on the question.
    // The limit fails as a thrown `exceededContextWindowSize` at the far end;
    // checking here means the reader is told what happened rather than shown a
    // framework error.
    //
    // What gives way first is the **evidence**, not the page. A page can carry
    // forty recognised values whose quotes are verbatim OCR lines, and that
    // block can be larger than the page it describes — while the page itself is
    // already capped at `askPageChars`. Dropping the evidence costs the model a
    // shortcut it can re-derive from the text underneath; dropping the page
    // would cost it the answer.
    let overhead = Gateless.estimatedTokens(instructions)
    var prompt = doc.askOpening(page: page, question: question)
    if overhead + Gateless.estimatedTokens(prompt) > Limits.localPromptTokens {
        prompt = doc.askOpening(page: page, question: question, evidence: false)
    }
    guard overhead + Gateless.estimatedTokens(prompt) <= Limits.localPromptTokens
    else { throw LocalModel.Failure.tooLong }

    let answer = try await respond(instructions, prompt)
    let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw LocalModel.Failure.empty }
    return trimmed
}

/// A character-count estimate of tokens.
///
/// A second home for the same arithmetic as `Gate.estimatedTokens`, and that is
/// not a DRY failure — layer 2 may not import layer 3
/// (`coding-standards.md` §1), and the alternative is either an egress-capable
/// target in Agent's dependency list or a shared helper in Contracts that
/// exists to serve one line. Both are worse than four characters per token
/// written twice.
///
/// ponytail: not a tokeniser. It over-counts ordinary English, which errs
/// toward sending *less* than allowed — the safe direction for a limit that
/// fails silently.
enum Gateless {
    static func estimatedTokens(_ text: String) -> Int { text.count / 4 }
}
