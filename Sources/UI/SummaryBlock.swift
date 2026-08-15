import SwiftUI

/// An AI summary of *some* of the document — the page you are on, a span you
/// pick, or all of it.
///
/// **This block is a demo shell. Nothing in it calls a model and nothing in it
/// leaves the machine.** The existing "What this is" block already summarises
/// the whole document honestly; this one exists to show what per-page scoping
/// would look like on the rail before the reading path is built to support it.
/// Every line it prints is canned and says so on screen, because a fabricated
/// summary that *looks* like a real one is the one failure mode this product
/// cannot ship (`project-overview.md` §9).
///
/// ponytail: canned output, no Gate call, no scoped transcript. Swap
/// `demoSummary` for a real per-range explain once a build-order row asks for
/// one — the scope picker and `pages(...)` below are the only parts worth
/// keeping.
struct SummaryBlock: View {
    /// The page the reader is looking at, so `.thisPage` means what it says.
    let page: Int
    /// How far the picker may go. A page count rather than the `Document`,
    /// because that is the only thing about it this block needs to know.
    let lastPage: Int

    enum Scope: String, CaseIterable, Identifiable {
        case thisPage = "This page"
        case range = "Some pages"
        case whole = "Everything"

        var id: String { rawValue }
    }

    @State private var scope: Scope = .thisPage
    @State private var from = 1
    @State private var to = 1
    @State private var working = false
    @State private var summary: [String]?

    /// Which pages the current scope covers. Pure and static so the ordering
    /// rules — a backwards range, a bound past the end — are testable without a
    /// window.
    nonisolated static func pages(scope: Scope, page: Int, from: Int, to: Int, last: Int) -> [Int] {
        let clamp = { (n: Int) in min(max(1, n), max(1, last)) }
        switch scope {
        case .thisPage: return [clamp(page)]
        // Entered either way round: a reader who picks "to 4" before "from 2"
        // has not made a mistake, they have filled the fields in the order they
        // read them.
        case .range: return Array(min(clamp(from), clamp(to))...max(clamp(from), clamp(to)))
        case .whole: return Array(1...max(1, last))
        }
    }

    private var covered: [Int] {
        Self.pages(scope: scope, page: page, from: from, to: to, last: max(1, lastPage))
    }

    /// `pages 3–7` / `page 4` — said the same way everywhere, so the button, the
    /// result header and the disclosure line cannot drift apart.
    nonisolated static func label(_ pages: [Int]) -> String {
        guard let first = pages.first, let last = pages.last else { return "no pages" }
        return first == last ? "page \(first)" : "pages \(first)–\(last)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Summarise")
                .font(.heading(12.5)).tracking(0.9).textCase(.uppercase)
                .foregroundStyle(Ink.accent700)
                .padding(.bottom, 2)
            Text("Pick how much of it you want read back to you.")
                .font(.body(12)).foregroundStyle(Ink.neutral600)
                .padding(.bottom, 10)

            scopeTabs.padding(.bottom, scope == .range ? 8 : 10)
            if scope == .range { rangePicker.padding(.bottom, 10) }

            summariseButton

            if let summary { result(summary).padding(.top, 12) }
        }
        .padding(18)
        .overlay(Rectangle().fill(Ink.divider).frame(height: 1), alignment: .bottom)
        // A summary of page 3 left on screen while page 9 is showing is a
        // caption under the wrong photograph. Same for re-scoping.
        .onChange(of: page) { _, _ in if scope == .thisPage { summary = nil } }
        .onChange(of: scope) { _, picked in
            summary = nil
            // Opening the range picker on the page the reader is already on is
            // one fewer thing to set before it means anything.
            if picked == .range, from == 1, to == 1 {
                from = page
                to = min(page + 2, max(1, lastPage))
            }
        }
    }

    // MARK: - Scope

    private var scopeTabs: some View {
        HStack(spacing: 0) {
            ForEach(Scope.allCases) { each in
                let on = scope == each
                Button { scope = each } label: {
                    Text(each.rawValue)
                        .font(.heading(11.5)).tracking(0.7).textCase(.uppercase)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(on ? Ink.bg : Ink.neutral700)
                        .background(on ? Ink.accent : .clear)
                        .overlay(Rectangle().stroke(on ? Ink.accent : Ink.divider, lineWidth: 1))
                }
                .buttonStyle(.flat)
            }
            Spacer(minLength: 0)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            bound("from", $from)
            bound("to", $to)
            Text(covered.count == 1 ? "1 page" : "\(covered.count) pages")
                .font(.mono(11)).monospacedDigit().foregroundStyle(Ink.neutral600)
            Spacer(minLength: 0)
        }
    }

    /// A native `Stepper` rather than a hand-rolled pair of buttons: it already
    /// holds the bound, repeats on press-and-hold, and is reachable by keyboard.
    private func bound(_ name: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 5) {
            Text(name)
                .font(.body(10.5)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(Ink.neutral600)
            Text("\(value.wrappedValue)")
                .font(.mono(12)).monospacedDigit()
                .foregroundStyle(Ink.text).frame(minWidth: 18, alignment: .trailing)
            Stepper("", value: value, in: 1...max(1, lastPage))
                .labelsHidden().controlSize(.mini)
        }
        .padding(.leading, 7).padding(.trailing, 4).padding(.vertical, 3)
        .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
        .accessibilityLabel("\(name) page")
    }

    // MARK: - Ask for it

    private var summariseButton: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: summarise) {
                Text(working ? "Summarising…" : "Summarise \(Self.label(covered))")
                    .font(.heading(12)).tracking(1.1).textCase(.uppercase)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(working ? Ink.neutral300 : Ink.accent)
                    .foregroundStyle(Ink.bg)
            }
            .buttonStyle(.flat)
            .disabled(working)

            Text("Demo only — no model is called and nothing leaves this Mac.")
                .font(.body(11)).foregroundStyle(Ink.neutral600)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summarise() {
        working = true
        summary = nil
        let pages = covered
        Task {
            // Long enough to read as work happening, short enough not to be a
            // pause anyone sits through twice.
            try? await Task.sleep(for: .milliseconds(700))
            summary = Self.demoSummary(pages)
            working = false
        }
    }

    nonisolated static func demoSummary(_ pages: [Int]) -> [String] {
        [
            "Placeholder summary for \(label(pages)). Wire this block to a real "
                + "explain call and this line is where its first paragraph lands.",
            "One bullet per point the model made, in the order it made them.",
            "Anything it was unsure about would be marked here rather than dropped.",
        ]
    }

    // MARK: - Result

    private func result(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "text.append")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Ink.neutral600)
                Text("sample text · nothing was read")
                    .font(.mono(10)).tracking(0.4).textCase(.uppercase)
                    .foregroundStyle(Ink.neutral600)
                Spacer(minLength: 0)
                Button { summary = nil } label: {
                    Text("clear")
                        .font(.body(11)).foregroundStyle(Ink.neutral700)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
                }
                .buttonStyle(.flat)
            }
            .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("·").font(.body(12)).foregroundStyle(Ink.accent400)
                        Text(line)
                            .font(.body(13)).foregroundStyle(Ink.neutral800)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("covers \(Self.label(covered)) of \(max(1, lastPage))")
                .font(.mono(10.5)).foregroundStyle(Ink.neutral600)
                .padding(.top, 10)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.neutral200)
        .blueprint(stroke: Ink.divider)
    }
}
