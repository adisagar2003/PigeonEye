import Agent
import Contracts
import SwiftUI

/// The whole-document findings index: one row per distinct value, searchable,
/// filtered by kind, and every row jumps to the page it was read from.
///
/// Separate from the per-page list rather than replacing it, because they answer
/// opposite questions. The per-page list answers *what is on this page* and is
/// what the F3 demo beat needs. This answers *where does this document say X*,
/// which is the only usable question on a 120-page tax guide — IRS P17 produces
/// 2,064 findings, and no amount of scrolling makes that a lookup.
struct IndexPanel: View {
    let doc: Document
    @Binding var query: String
    @Binding var kind: Kind?
    let selected: String?
    let jump: (IndexEntry) -> Void

    @FocusState private var searching: Bool

    var body: some View {
        // The query narrows the chip counts too: a chip that says "Dates 9"
        // while the search shows two rows is counting a different document
        // from the one on screen.
        let matched = doc.index(matching: query, kind: nil)
        let rows = kind.map { k in matched.filter { $0.kind == k } } ?? matched

        VStack(alignment: .leading, spacing: 0) {
            search
            chips(matched)

            if rows.isEmpty {
                // The completeness rule again: an empty panel reads as a
                // failure to run (`project-overview.md` §9).
                Text(query.isEmpty
                     ? "Nothing of that kind in this document."
                     : "Nothing matches “\(query)”.")
                    .font(.body(12.5)).foregroundStyle(Ink.neutral700)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { row($0) }
                    }
                }
                .frame(maxHeight: 460)
                .blueprint(stroke: Ink.divider)
            }
        }
    }

    // MARK: - Search

    private var search: some View {
        HStack(spacing: 8) {
            // Not `.searchable`: that puts the field in the window toolbar,
            // which is a different surface from the rail it filters.
            TextField("Search this document", text: $query)
                .textFieldStyle(.plain)
                .font(.body(12.5))
                .focused($searching)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(Rectangle().stroke(searching ? Ink.accent600 : Ink.divider, lineWidth: 1))

            if !query.isEmpty {
                Button { query = "" } label: {
                    Text("clear")
                        .font(.body(11)).foregroundStyle(Ink.neutral700)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .overlay(Rectangle().stroke(Ink.divider, lineWidth: 1))
                }
                .buttonStyle(.flat)
            }
        }
        .padding(.bottom, 8)
        // Opening the tab is the whole gesture — a search box you then have to
        // click is two.
        .onAppear { searching = true }
    }

    // MARK: - Kind chips

    /// One chip per kind actually present, plus `All`. Kinds with nothing in
    /// them are not drawn: a row of empty chips is a capability list, which is
    /// the same mistake the demo-fixture buttons made.
    private func chips(_ matched: [IndexEntry]) -> some View {
        let counts = Dictionary(grouping: matched, by: \.kind).mapValues(\.count)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", count: matched.count, on: kind == nil) { kind = nil }
                ForEach(Kind.allCases.filter { counts[$0] != nil }) { each in
                    chip(each.label, count: counts[each] ?? 0, on: kind == each) {
                        // A second click on the active chip clears it, so the
                        // filter has an exit that is where the entrance was.
                        kind = kind == each ? nil : each
                    }
                }
            }
            .padding(.bottom, 10)
        }
    }

    private func chip(_ title: String, count: Int, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: 5) {
                Text(title).font(.heading(11.5)).tracking(0.6).textCase(.uppercase)
                Text("\(count)").font(.mono(10)).monospacedDigit()
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(on ? Ink.bg : Ink.neutral700)
            .background(on ? Ink.accent : .clear)
            .overlay(Rectangle().stroke(on ? Ink.accent : Ink.divider, lineWidth: 1))
        }
        .buttonStyle(.flat)
    }

    // MARK: - Rows

    private func row(_ entry: IndexEntry) -> some View {
        Button { jump(entry) } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.value)
                        .font(.mono(13)).foregroundStyle(Ink.text)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if entry.checked {
                        Text("checked").font(.mono(9.5)).foregroundStyle(Ink.accent700)
                    }
                    Chevron()
                }
                Text(where_(entry))
                    .font(.body(11)).foregroundStyle(Ink.neutral600)
                    .lineLimit(1)
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected == entry.id ? Ink.accent100 : Color.clear)
        }
        .buttonStyle(.row)
    }

    /// `AMOUNT · p1, p4, p7` — what it is, and where. Truncated at four pages
    /// with a count, because a value on 40 pages would otherwise push the label
    /// off the row it belongs to.
    private func where_(_ entry: IndexEntry) -> String {
        let pages = entry.pages
        let shown = pages.prefix(4).map { "p\($0)" }.joined(separator: ", ")
        let rest = pages.count > 4 ? " +\(pages.count - 4) more" : ""
        return "\(entry.label.uppercased()) · \(shown)\(rest)"
    }
}
