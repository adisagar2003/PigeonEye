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

    public init() {}

    /// The two fixtures are real documents from `assets/`, opened the same way
    /// the file picker opens anything else. The design's third fixture is a
    /// university registrar notice, which is outside scope §7.
    public struct Fixture: Identifiable, Sendable {
        public let id: String
        public let label: String
        public let path: String
    }

    public static let fixtures: [Fixture] = [
        .init(id: "label", label: "EPA letter", path: "assets/epa-labels/000524-00529-20241120.pdf"),
        .init(id: "scan", label: "Bad scan", path: "assets/scans/007969-00242-20170111-01.jpg"),
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

    public func open(_ url: URL) async {
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
            phase = .failed(failure.errorDescription ?? "That file could not be read.")
        } catch {
            guard requestID == id else { return }
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
