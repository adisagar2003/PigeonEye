import Agent
import Contracts
import CoreGraphics
import Foundation
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

    public init(
        read: @escaping @Sendable (URL, (@Sendable (Int, Int) -> Void)?) async throws -> Document
            = Agent.read
    ) {
        self.read = read
    }

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
