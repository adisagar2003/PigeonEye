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

    public var page = 1 { didSet { Task { await loadPageImage() } } }
    public var zoom = 1.0
    /// The field the overlay outlines, or nil. Selection is a UI concern only —
    /// the field list itself is ground truth from the file and never changes.
    public private(set) var selectedField: Field?
    public var transcriptOpen = false
    public var inspectorOpen = false

    public init() {}

    /// The two fixtures are real documents from `assets/`, opened the same way
    /// the file picker opens anything else. The design's third fixture is a
    /// university registrar notice, which is outside scope §7.
    public struct Fixture: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let path: String
    }

    /// `007969-00242-...-01.jpg` used to sit behind "Bad scan" and is not one —
    /// it is a clean digital render, and the `WEAL PROTECTED` misread recorded
    /// against it comes from the circular seal, not from scan damage. A fixture
    /// button whose label is false about its own document is the exact failure
    /// `project-overview.md` §9 forbids.
    ///
    /// The replacement is the whole 40-page photocopy rather than one page of
    /// it: degradation is not uniform down a document, and one good page proves
    /// nothing about the confidence reading on page 39.
    public static let fixtures: [Fixture] = [
        .init(id: "label", label: "EPA letter", path: "assets/epa-labels/000524-00529-20241120.pdf"),
        .init(id: "scan", label: "Bad scan", path: "assets/epa-labels/007969-00186-20080911.pdf"),
    ]

    public var activeFixture: String? {
        guard let doc else { return nil }
        return Self.fixtures.first { doc.url.path.hasSuffix($0.path) }?.id
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

        do {
            let document = try await read(url) { [weak self] done, total in
                Task { @MainActor in
                    guard self?.requestID == id else { return }
                    self?.phase = .reading(done: done, total: total)
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

    public func openFixture(_ fixture: Fixture) async {
        await open(Self.repoRoot.appending(path: fixture.path))
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
        page = min(max(1, page + delta), doc.pagesRead)
    }

    public func zoomBy(_ delta: Double) {
        zoom = Zoom.stepped(from: zoom, by: delta)
    }

    /// Jump to a field's page and outline it. Assigning `page` is what loads the
    /// image — the existing `didSet` owns that, so there is no second load path
    /// here to fall out of step with it.
    public func select(_ field: Field) {
        selectedField = field
        if page != field.page { page = field.page }
    }

    private func loadPageImage() async {
        guard let document = doc, page >= 1, page <= document.pagesRead else {
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

    /// ponytail: fixtures are found relative to the source tree, because a
    /// SwiftPM executable has no bundle to put resources in. The day this ships
    /// as a signed .app, they become bundle resources or the buttons go away.
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // UI
        .deletingLastPathComponent()  // Sources
        .deletingLastPathComponent()  // repo root
}
