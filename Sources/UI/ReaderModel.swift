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

    /// What is on screen, or on its way there. Held so that asking for the same
    /// document twice is free — see the guard in `open`.
    private var current: URL?

    public func open(_ url: URL) async {
        // Already read, or already reading. A second pass costs ~15s and cannot
        // return anything different, and because the pane is blanked first, it
        // showed as the current document vanishing and coming back.
        guard current != url else { return }
        current = url

        let id = UUID()
        requestID = id

        phase = .reading(done: 0, total: 0)
        doc = nil
        pageImage = nil
        page = 1
        zoom = 1

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

    public func openFixture(_ fixture: Fixture) async {
        await open(Self.repoRoot.appending(path: fixture.path))
    }

    public func step(_ delta: Int) {
        guard let doc else { return }
        page = min(max(1, page + delta), doc.pagesRead)
    }

    public func zoomBy(_ delta: Double) {
        zoom = Zoom.stepped(from: zoom, by: delta)
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
