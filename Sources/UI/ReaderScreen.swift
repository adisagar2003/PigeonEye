import Agent
import Contracts
import SwiftUI
import UniformTypeIdentifiers

// The PigeonEye Reader v3 design, minus every block F1 cannot fill honestly.
// Urgency, title, confidence ring, findings, summary, next steps and the
// escalation dialog are not drawn — not stubbed, not filled with sample text.
// Each later feature turns one of them on. See
// context/features/01-read-it-locally.md §3.

public struct ReaderScreen: View {
    @State private var model = ReaderModel()
    @State private var picking = false

    /// ponytail: `UserDefaults` under the process name, because a SwiftPM
    /// executable has no bundle. This is now the *only* place that ceiling is
    /// still felt — the fixture paths that shared it are gone.
    /// It lands in `~/Library/Preferences/PigeonEye.plist` and
    /// survives a rebuild, which is what "first run only" has to mean. When
    /// this ships as a signed .app the key moves to the bundle's domain, and
    /// existing installs see the explainer once more.
    @AppStorage("onboardingSeen") private var onboardingSeen = false

    public init() {}

    public var body: some View {
        // Replaces the reader rather than sitting over it. An overlay left the
        // header's focus ring drawing on top of the card — and a reader you can
        // still tab into is not what a first run should offer.
        if onboardingSeen {
            reader
        } else {
            OnboardingScreen { onboardingSeen = true }
        }
    }

    private var reader: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                documentPane
                Rectangle().fill(Ink.divider).frame(width: 1)
                rail.frame(width: 452)
            }
        }
        .background(Ink.bg)
        .foregroundStyle(Ink.text)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.pdf, .png, .jpeg]) { result in
            if case let .success(url) = result {
                Task { await model.open(url) }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("PigeonEye")
                    .font(.heading(20)).tracking(3.2).textCase(.uppercase)
                    .foregroundStyle(Ink.bg)
                // True in F1 by construction: there is no Gate layer to call.
                Text("Reads locally")
                    .font(.heading(12, .semibold)).tracking(1.1).textCase(.uppercase)
                    .foregroundStyle(Ink.accent300)
            }
            Spacer()

            Button { picking = true } label: {
                Text("Open…")
                    .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .foregroundStyle(Ink.accent200)
                    .overlay(Rectangle().stroke(Ink.accent600, lineWidth: 1))
            }
            .buttonStyle(.flat)
            .keyboardShortcut("o")
            .help("Open a file (⌘O)")

            Button { model.inspectorOpen.toggle() } label: {
                Text("Inspector")
                    .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(model.inspectorOpen ? Ink.accent300 : .clear)
                    .foregroundStyle(model.inspectorOpen ? Ink.accent900 : Ink.accent200)
                    .overlay(Rectangle().stroke(model.inspectorOpen ? Ink.accent300 : Ink.accent600, lineWidth: 1))
            }
            .buttonStyle(.flat)
            .keyboardShortcut("i")
            .help("Inspector (⌘I)")
        }
        .padding(.horizontal, 18).padding(.vertical, 10)
        .background(Ink.accent900)
    }

    // MARK: - Document pane

    private var documentPane: some View {
        VStack(spacing: 0) {
            if let doc = model.doc {
                toolbar(doc)
                Rectangle().fill(Ink.divider).frame(height: 1)
            }
            ZStack {
                Ink.neutral200
                switch model.phase {
                case .idle: welcome
                case let .reading(done, total): reading(done: done, total: total)
                case .failed(let message): refusal(message)
                case .ready: pageView
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toolbar(_ doc: Document) -> some View {
        HStack(spacing: 10) {
            Text(doc.fileName)
                .font(.heading(13)).tracking(0.8).textCase(.uppercase)
                .foregroundStyle(Ink.neutral800).lineLimit(1)

            // I5 — rendered unconditionally, never behind a disclosure.
            Text(doc.pagesReadLine)
                .font(.body(10.5)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(Ink.accent700)
                .padding(.horizontal, 7).padding(.vertical, 1)
                .overlay(Rectangle().stroke(Ink.accent400, lineWidth: 1))
                .fixedSize()

            if doc.capped {
                Text("capped at \(doc.pagesRead)")
                    .font(.body(10.5)).tracking(0.5).textCase(.uppercase)
                    .foregroundStyle(Ink.neutral700)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .overlay(Rectangle().stroke(Ink.neutral400, lineWidth: 1))
                    .fixedSize()
            }

            // A damaged page is reported next to the pages-read chip, not only
            // in the inspector log: the consumer has to know a page is missing
            // from what they are reading (`features/01-read-it-locally.md` §7).
            if !doc.failedPages.isEmpty {
                Text(doc.failedPages.count == 1
                     ? "page \(doc.failedPages[0]) unreadable"
                     : "\(doc.failedPages.count) pages unreadable")
                    .font(.body(10.5)).tracking(0.5).textCase(.uppercase)
                    // ponytail: no warning hue exists in the token set, and
                    // inventing one is a design decision context/ has not taken
                    // (F1 §8). Weight carries it instead — darker text and a
                    // heavier rule than the `capped` chip beside it.
                    .foregroundStyle(Ink.neutral900)
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .overlay(Rectangle().stroke(Ink.neutral600, lineWidth: 1))
                    .fixedSize()
                    .help("These pages could not be rendered. Everything else was read.")
            }

            Spacer()

            step("‹", .leftArrow, "⌘←") { model.step(-1) }
            Text("page \(model.page) / \(doc.pagesRead)")
                .font(.body(11.5)).monospacedDigit()
                .foregroundStyle(Ink.neutral700).frame(minWidth: 78)
            step("›", .rightArrow, "⌘→") { model.step(1) }

            Rectangle().fill(Ink.divider).frame(width: 1, height: 16)

            step("−", "-", "⌘−") { model.zoomBy(-Zoom.step) }
            Text("\(Int((model.zoom * 100).rounded()))%")
                .font(.body(11.5)).monospacedDigit()
                .foregroundStyle(Ink.neutral700).frame(minWidth: 38)
            // "=" not "+", so zooming in does not also require shift.
            step("+", "=", "⌘+") { model.zoomBy(Zoom.step) }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Ink.bg)
    }

    private func step(_ glyph: String, _ key: KeyEquivalent, _ hint: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.body(13)).foregroundStyle(Ink.neutral700)
                .frame(minWidth: 26).padding(.vertical, 3)
                .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
        }
        .buttonStyle(.flat)
        .keyboardShortcut(key)
        .help(hint)
    }

    private var pageView: some View {
        ScrollView([.vertical, .horizontal]) {
            Group {
                if let image = model.pageImage {
                    Image(decorative: image, scale: 1)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 720 * model.zoom)
                        .background(.white)
                        .blueprint(stroke: Ink.neutral500)
                        .shadow(color: Ink.neutral900.opacity(0.16), radius: 5, y: 3)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(26)
            .frame(maxWidth: .infinity)
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Text("Read a document")
                .font(.heading(25)).tracking(0.5)
            Text("It is read on this machine. Nothing is uploaded, nothing is kept.")
                .font(.body(13.5)).foregroundStyle(Ink.neutral700)

            Button { picking = true } label: {
                Text("Open a file")
                    .font(.heading(15)).tracking(1.4).textCase(.uppercase)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Ink.accent).foregroundStyle(Ink.bg)
                    .blueprint(stroke: Ink.accent)
            }
            .buttonStyle(.flat)
            .padding(.top, 6)

            Text("PDF, PNG or JPEG · up to 20 MB")
                .font(.body(12)).foregroundStyle(Ink.neutral600)
        }
        .padding(40)
        .background(Ink.bg)
        .blueprint()
        .padding(40)
    }

    private func reading(done: Int, total: Int) -> some View {
        VStack(spacing: 12) {
            Text(total == 0 ? "Opening" : "Reading page \(done) of \(total)")
                .font(.heading(19)).tracking(1).textCase(.uppercase)
            // A 45-page label takes ~15s. The design has no reading state; a
            // frozen window for 15 seconds is not a design choice.
            ProgressView(value: total == 0 ? 0 : Double(done), total: Double(max(total, 1)))
                .frame(width: 260).tint(Ink.accent)
            Text("On this machine · no network")
                .font(.body(12)).foregroundStyle(Ink.neutral600)
        }
        .padding(36)
        .background(Ink.bg)
        .blueprint()
    }

    private func refusal(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not read").kicker(12, tracking: 1.1, color: Ink.accent800)
            Text(message).font(.body(14.5)).foregroundStyle(Ink.accent900)
            Button { picking = true } label: {
                Text("Choose another file")
                    .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                    .foregroundStyle(Ink.accent700)
                    .overlay(Rectangle().fill(Ink.accent400).frame(height: 1), alignment: .bottom)
            }
            .buttonStyle(.flat)
        }
        .frame(maxWidth: 420, alignment: .leading)
        .padding(24)
        .background(Ink.accent100)
        .blueprint(stroke: Ink.accent400)
        .padding(40)
    }

    // MARK: - Rail

    private var rail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let doc = model.doc {
                    transcriptBlock(doc)
                    if model.inspectorOpen { inspectorBlock(doc) }
                } else {
                    Text("Nothing read yet.")
                        .font(.body(13)).foregroundStyle(Ink.neutral600)
                        .padding(18)
                }
                Spacer(minLength: 0)
                footer
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Ink.bg)
    }

    private func transcriptBlock(_ doc: Document) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.transcriptOpen.toggle() } label: {
                Text(model.transcriptOpen ? "Hide transcript" : "Show the text it read")
                    .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                    .foregroundStyle(Ink.accent700)
                    .overlay(Rectangle().fill(Ink.accent400).frame(height: 1), alignment: .bottom)
            }
            .buttonStyle(.flat)
            .keyboardShortcut("t")
            .help("Show the text it read (⌘T)")

            if model.transcriptOpen {
                // One `Text` holding the joined transcript is what froze the
                // window: 45 pages is ~130 KB, SwiftUI lays all of it out in a
                // single pass, and text layout cannot leave the main thread —
                // so a background task would have moved the join (~1 ms) and
                // left the freeze exactly where it was. A LazyVStack lays out
                // the pages actually on screen. The cost is that a selection
                // drag no longer spans two pages.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(doc.pages.indices, id: \.self) { index in
                            if !doc.pages[index].transcript.isEmpty {
                                Text(doc.pages[index].transcript)
                                    .font(.mono(11)).foregroundStyle(Ink.neutral800)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 320)
                .background(Ink.neutral200)
                .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(Ink.divider).frame(height: 1), alignment: .bottom)
    }

    private func inspectorBlock(_ doc: Document) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Inspector").kicker(12, tracking: 1.2, color: Ink.neutral700)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(doc.log) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Text(entry.stamp).foregroundStyle(Ink.neutral600).frame(width: 44, alignment: .leading)
                        Text(entry.message).frame(maxWidth: .infinity, alignment: .leading)
                        Text(entry.tag.rawValue)
                            .foregroundStyle(entry.tag == .local ? Ink.accent700 : Ink.neutral700)
                    }
                    .font(.mono(10.5))
                }
            }

            Rectangle().fill(Ink.divider).frame(height: 1)

            // True by construction in F1: no Gate layer exists to send anything.
            HStack(spacing: 4) {
                Text("Left this machine:").font(.body(11.5)).foregroundStyle(Ink.neutral700)
                Text("nothing. Everything above was read here.")
                    .font(.body(11.5)).foregroundStyle(Ink.accent700)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.neutral200)
        .overlay(Rectangle().fill(Ink.divider).frame(height: 1), alignment: .bottom)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Export findings")
                .font(.heading(13)).tracking(0.9).textCase(.uppercase)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
                .foregroundStyle(Ink.neutral500)
            Text("Findings only — never document bytes.")
                .font(.body(11)).foregroundStyle(Ink.neutral600)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(Rectangle().fill(Ink.divider).frame(height: 1), alignment: .top)
    }
}
