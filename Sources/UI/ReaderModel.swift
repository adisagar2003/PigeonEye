import Agent
import Contracts
import CoreGraphics
import Foundation
import Gate
import Observation

/// Everything the reader screen knows. Layer 4 — it holds no reading logic of
/// its own, it calls `Agent.read` and renders what comes back.
@MainActor
@Observable
public final class ReaderModel {
    public enum Phase {
        case idle
        case reading(done: Int, total: Int)
        case ready
        case failed(String)
    }

    public private(set) var phase: Phase = .idle
    public private(set) var doc: Document?
    public private(set) var pageImage: CGImage?

    /// Blanking the image is the point, not a side effect: without it a jump to
    /// another page draws the *new* page's highlight over the *old* page's
    /// raster until the render lands — the reader pointing confidently at the
    /// wrong place, which is the failure the highlight exists to avoid.
    public var page = 1 {
        didSet {
            guard page != oldValue else { return }
            pageImage = nil
            Task { await loadPageImage() }
        }
    }
    public var zoom = 1.0
    /// What the overlay outlines. Selection is a UI concern only — neither the
    /// field list nor the findings change because something is selected. At most
    /// one is set: selecting in either list clears the other, because two boxes
    /// on one page with no way to tell which is which is worse than one.
    public private(set) var selectedField: Field?
    public private(set) var selectedFinding: Finding?
    public var transcriptOpen = false
    public var inspectorOpen = false

    /// True when the page on screen is one that could not be rendered. A failed
    /// page has no image, and "no image" is otherwise indistinguishable from
    /// "still rendering" — see `ReaderScreen.pageView`.
    public var pageFailed: Bool { doc?.failedPages.contains(page) ?? false }

    /// How a document gets read. Injectable for exactly one reason: progress is
    /// delivered on unstructured tasks, so the only way to test what happens
    /// when one lands *after* the read has finished is to keep the handler and
    /// call it late. Production always gets `Agent.read`.
    private let read: @Sendable (URL, (@Sendable (Int, Int) -> Void)?) async throws -> Document

    /// `nil` when asking cannot happen — no key in the environment, or the
    /// reader picked a tier that does not send. The panel then offers no box to
    /// type in: a field that cannot send is worse than no field.
    ///
    /// Injectable for the same reason `read` is: a test that asserts nothing
    /// leaves the machine has to be able to watch the thing that would send it.
    public private(set) var cloud: Gate.Config?
    /// What the environment offers, before the tier has an opinion about it.
    private let configured: Gate.Config?
    private let transport: Gate.Transport
    private let respond: LocalModel.Respond

    /// The tier the reader picked at first run, and what it means here.
    public private(set) var tier: OnboardingScreen.Tier = .openAI
    /// Whether the on-device model can actually answer on this machine.
    /// Re-asked on every `honour`, because macOS downloads and evicts these
    /// assets on its own schedule.
    public private(set) var localReady = false
    /// Why the on-device tier cannot run, when it cannot. Rendered in the
    /// panel, because "asking is off" without a reason is not a disclosure.
    public private(set) var localBlocker: String?

    public init(
        read: @escaping @Sendable (URL, (@Sendable (Int, Int) -> Void)?) async throws -> Document
            = Agent.read,
        cloud: Gate.Config? = Gate.Config.fromEnvironment(ProcessInfo.processInfo.environment),
        transport: @escaping Gate.Transport = Gate.defaultTransport,
        respond: @escaping LocalModel.Respond = LocalModel.session
    ) {
        self.read = read
        self.configured = cloud
        self.cloud = cloud
        self.transport = transport
        self.respond = respond
    }

    /// Honour the tier the reader picked at first run.
    ///
    /// **This is what makes "On this Mac" mean anything.** Without it the tier
    /// was a stored preference that only the onboarding screen ever read, so
    /// choosing the local option still produced a cloud-backed ask panel — the
    /// exact "fallback you have to discover" `project-overview.md` §3.1 rules
    /// out, and worse, because the reader had explicitly declined it.
    public func honour(_ tier: OnboardingScreen.Tier, localReady: Bool? = nil) {
        self.tier = tier
        cloud = Self.askConfig(tier: tier, offered: configured)
        self.localReady = localReady ?? (tier == .local && localModelAvailable())
        localBlocker = tier == .local && !self.localReady
            ? (localModelBlocker() ?? "The on-device model is not available on this Mac.")
            : nil
    }

    /// Pure, so the rule is testable without a window. `.local` never resolves
    /// to a cloud endpoint — it answers on this machine or it says why it
    /// cannot.
    nonisolated public static func askConfig(tier: OnboardingScreen.Tier,
                                             offered: Gate.Config?) -> Gate.Config? {
        tier == .openAI ? offered : nil
    }

    /// Whether the panel has anything to offer, by either tier.
    public var canAsk: Bool { cloud != nil || localReady }

    /// **Nothing leaves the machine on the local tier**, so there is nothing to
    /// consent to. Asking permission to do something that does not happen is
    /// the same theatre `project-overview.md` §4.1 rules out for crops — it
    /// reads as evidence that something *is* being sent.
    public var needsGrant: Bool { !localReady && cloud != nil && !askGranted }

    /// Identifies the newest request. Every `await` in this file is a point where
    /// an older, slower read can come back and clobber a newer one — a 45-page
    /// label takes ~5x a one-page scan, so "open A, then open B" really does
    /// finish B-then-A. Without this the reader shows the *previous* document
    /// while its own state says otherwise, which for private documents is the
    /// worst way to be wrong.
    private var requestID = UUID()

    /// What is on screen, or on its way there — **path and modification date**.
    /// Path alone would latch onto a file that has since been re-saved, and the
    /// reader would show a transcript of bytes that no longer exist with no way
    /// to escape but opening something else first.
    private var current: (url: URL, modified: Date?)?

    /// Set when `open` declined to re-read what is already on screen. The screen
    /// renders it, because a click that produces nothing at all reads as a hang
    /// — and this app does not get to be silent about what it is doing.
    public private(set) var notice: String?
    private var noticeID = UUID()

    // MARK: - Asking about the page

    /// The conversation about this document. Memory only, dropped the moment
    /// another document is opened (**I9**) — there is no persistence path in
    /// this app and this feature does not add one.
    public private(set) var turns: [Turn] = []

    /// True while a question is in flight. The box stays visible and disabled
    /// rather than disappearing: a control that vanishes mid-action reads as a
    /// crash.
    public private(set) var answering = false

    /// Whether the reader has agreed that this document's pages may be sent.
    /// Taken once per document, in the panel, before the first question
    /// (`project-overview.md` §4.1 — consent at document scope, not per message,
    /// because a second prompt after the first send protects nothing).
    public private(set) var askGranted = false

    /// A question typed before the grant was given. Held rather than dropped, so
    /// agreeing sends the question the reader already wrote instead of making
    /// them type it again.
    public private(set) var askPending: String?

    /// What left the machine, for the inspector: page number, size, host. Never
    /// the words (`coding-standards.md` §5.2).
    public private(set) var sends: [String] = []

    /// Ask about the page currently on screen.
    ///
    /// Before the grant this only *holds* the question — the transport is not
    /// reached, which is what makes **I1** true here by construction rather than
    /// by a check somewhere downstream.
    public func ask(_ question: String) async {
        let asked = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !asked.isEmpty, doc != nil, canAsk, !answering else { return }
        // The grant covers egress, so the local tier does not need one — see
        // `needsGrant`.
        guard !needsGrant else {
            askPending = asked
            return
        }
        await send(asked)
    }

    /// Agree that this document's pages may be sent. Does not itself send.
    public func grantAsk() { askGranted = true }

    /// Send whatever was typed before the grant. Separate from `grantAsk` so the
    /// consent card can be dismissed without a request going out behind it.
    public func sendPending() async {
        guard askGranted, let held = askPending else { return }
        askPending = nil
        await send(held)
    }

    /// Throw away a question rather than sending it. The reader said no.
    public func cancelPending() { askPending = nil }

    private func send(_ question: String) async {
        guard let doc else { return }
        let id = requestID
        let asked = page

        turns.append(Turn(role: .user, text: question))
        answering = true

        // The on-device tier wins when it is available. That ordering is the
        // product: `project-overview.md` §3 promises that on a machine with a
        // local reasoning model nothing leaves at all, and a preference the
        // code consults second is a preference the code does not hold.
        let answer: Answer
        if localReady {
            answer = await answeredHere(doc, page: asked, question: question, respond: respond)
        } else if let cloud {
            answer = await answered(doc, page: asked, question: question,
                                    history: turns.dropLast(), config: cloud,
                                    transport: transport)
        } else {
            answering = false
            return
        }

        // The same generation check as every other await in this file: an answer
        // about the document that *was* open must not land on the one that is.
        guard requestID == id, self.doc?.url == doc.url else { return }

        turns.append(Turn(role: .assistant,
                          text: answer.note.map { "\(answer.text)\n\n\($0)" } ?? answer.text,
                          pages: answer.pagesUsed))
        sends.append(contentsOf: answer.sends)
        answering = false
    }

    // MARK: - Explaining the document

    /// What the document is. Present as soon as one is read, because it is
    /// assembled locally with no model call — **I6**, and the reason a missing
    /// key never blanks the screen.
    public private(set) var explanation: Explanation?
    public private(set) var asking = false

    /// Send the transcript and the recognised values to the model.
    ///
    /// **Nothing here runs on open.** The reader presses a button that says what
    /// leaves, and that press is the consent — `project-overview.md` §4.1 takes
    /// the grant for the whole document rather than per crop, and this is where
    /// it is taken. Any failure returns the local reading with the reason
    /// attached, never an empty screen (**I6**).
    ///
    /// `cloud` is `nil` on the local tier, so this cannot run there — the same
    /// gate `ask` goes through, for the same reason.
    public func explainWithCloud() async {
        guard let doc, let cloud, !asking else { return }
        let id = requestID
        asking = true

        // The ledger comes back from `explained` rather than being written
        // here, because only it knows whether the bytes reached the far end.
        // Recording egress is not conditional on success: a 500 means the
        // transcript left this machine, and the inspector saying otherwise is
        // the one direction this app must never be wrong in.
        let (result, ledger) = await explained(doc, config: cloud, transport: transport)

        // The same generation check as every other await in this file: a read
        // started after this one must not be overwritten by its answer.
        guard requestID == id, self.doc?.url == doc.url else { return }
        explanation = result
        sends.append(contentsOf: ledger)
        asking = false
    }

    public func open(_ url: URL) async {
        // Already read, or already reading. A second pass costs ~15s and cannot
        // return anything different, and because the pane is blanked first, it
        // showed as the current document vanishing and coming back.
        let stamp = Self.modified(url)
        guard current?.url != url || current?.modified != stamp else {
            return flash("Already open — read once, kept until you open another.")
        }
        current = (url, stamp)
        notice = nil

        let id = UUID()
        requestID = id

        phase = .reading(done: 0, total: 0)
        doc = nil
        pageImage = nil
        page = 1
        zoom = 1
        selectedField = nil
        selectedFinding = nil
        // The conversation, the grant, the explanation and the record of what
        // left all belong to the document that is going away (**I9**). A grant
        // that outlives its document is a grant for a document the reader never
        // agreed to send, and an explanation that outlives it describes the
        // wrong file.
        turns = []
        askGranted = false
        askPending = nil
        answering = false
        sends = []
        explanation = nil
        asking = false

        do {
            let document = try await read(url) { [weak self] done, total in
                Task { @MainActor in
                    // `requestID` only rejects a *different* open. A progress
                    // event from *this* read can still be queued on the main
                    // actor when the read returns, and would then push a
                    // finished document back to "Reading page…" with nothing
                    // left running to move it forward. Only a request that is
                    // still reading may move the bar.
                    guard let self, self.requestID == id, case .reading = self.phase
                    else { return }
                    self.phase = .reading(done: done, total: total)
                }
            }
            guard requestID == id else { return }
            doc = document
            // Local, immediate, no model call. The screen says something true
            // before anything has been offered the chance to leave the machine.
            explanation = explain(document)
            phase = .ready
            await loadPageImage()
        } catch let failure as ReadFailure {
            guard requestID == id else { return }
            // A refused file has to stay retryable — otherwise picking the same
            // file again from "Choose another file" would silently do nothing.
            current = nil
            phase = .failed(failure.errorDescription ?? "That file could not be read.")
        } catch {
            guard requestID == id else { return }
            current = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// Show a message and take it away again. Generation-token clearing for the
    /// same reason `requestID` exists: two presses in quick succession must not
    /// let the first one's timer wipe the second one's message.
    private func flash(_ message: String) {
        let id = UUID()
        noticeID = id
        notice = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, self.noticeID == id else { return }
            self.notice = nil
        }
    }

    /// The file's modification date, or nil if it cannot be read — in which case
    /// the latch falls back to comparing paths alone.
    private static func modified(_ url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }

    public func step(_ delta: Int) {
        guard let doc else { return }
        page = min(max(1, page + delta), doc.navigablePageCount)
    }

    public func zoomBy(_ delta: Double) {
        zoom = Zoom.stepped(from: zoom, by: delta)
    }

    /// Jump to a field's page and outline it. Assigning `page` is what loads the
    /// image — the existing `didSet` owns that, so there is no second load path
    /// here to fall out of step with it.
    public func select(_ field: Field) {
        selectedField = field
        selectedFinding = nil
        if page != field.page { page = field.page }
    }

    /// Jump to a finding's page and outline the region its quote came from.
    public func select(_ found: Finding) {
        selectedFinding = found
        selectedField = nil
        if page != found.page { page = found.page }
    }

    private func loadPageImage() async {
        guard let document = doc, page >= 1, page <= document.navigablePageCount else {
            pageImage = nil
            return
        }
        // Same race as `open`: page ‹ › held down spawns a render per press, and
        // they do not finish in order. Discard anything that is no longer what
        // the screen is asking for.
        let (id, requestedPage) = (requestID, page)
        let rendered = await Task.detached { try? document.pageImage(requestedPage) }.value
        guard requestID == id, page == requestedPage, doc?.url == document.url else { return }
        pageImage = rendered
    }
}
