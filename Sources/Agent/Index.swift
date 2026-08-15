import Contracts
import Foundation

// Layer 2. The findings index — one row per distinct value, with the pages it
// appears on. Pure functions over a Document that is already read; no OCR, no
// model, nothing to await.
//
// Why it lives here and not in the view: grouping is a claim about the document
// ("these three matches are the same value"), and a view that made that claim
// would be layer 2 leaking into layer 4 (`coding-standards.md` §1). It is also
// the only way to test it without SwiftUI.

/// One value the document contains, and everywhere it says it.
///
/// The book-index shape, and the name is literal: a term, and the pages. A
/// per-page findings list answers "what is on this page"; a reader with a
/// 120-page tax guide is asking the opposite question, and 2,064 findings is
/// not an answer to it.
public struct IndexEntry: Identifiable, Sendable {
    /// The value as it was read. Identical strings are one entry — the whole
    /// point — so this is the identity, together with the kind.
    public let value: String
    public let kind: Kind
    /// What the producer called it. The first occurrence's label wins; they are
    /// the same string in practice, because `kind` is what differs between
    /// producers and it is part of the identity.
    public let label: String
    /// Every occurrence, in page order.
    public let occurrences: [Finding]

    public var id: String { "\(kind.rawValue):\(value)" }
    public var count: Int { occurrences.count }
    /// Distinct pages, ascending. A value found twice on page 4 lists `4` once.
    public var pages: [Int] { occurrences.map(\.page).reduced() }
    /// True when a format validator passed *any* occurrence. **I3** still holds:
    /// this licenses no colour on its own, it reports that a rule ran and said
    /// yes somewhere.
    public var checked: Bool { occurrences.contains { $0.validated == true } }

    /// The occurrence to jump to from `page`, wrapping at the end.
    ///
    /// Wrapping rather than stopping, because a row that lists seven pages and
    /// goes dead on the seventh click reads as broken. `nil` means "not yet
    /// anywhere" — the first click.
    public func occurrence(after page: Int?) -> Finding {
        guard let page else { return occurrences[0] }
        return occurrences.first { $0.page > page } ?? occurrences[0]
    }
}

private extension [Int] {
    /// Ascending, without repeats. (`Set` then `sorted` twice over is the
    /// version this replaces; occurrences are already in page order.)
    func reduced() -> [Int] {
        reduce(into: []) { out, page in if out.last != page { out.append(page) } }
    }
}

public extension Document {
    /// Every distinct value the document contains, in document order.
    ///
    /// Document order rather than frequency: the reader is looking something up
    /// in a document they are also reading, and "where it first appears" is the
    /// only ordering both views agree on.
    var index: [IndexEntry] {
        var order: [String] = []
        var groups: [String: [Finding]] = [:]

        // A **stable** sort by page, spelled out because `sorted(by:)` is not
        // one: two findings on the same page must keep the order they were
        // produced in, which is line order down the page. An unstable sort would
        // shuffle a page's rows between runs, and an index that reorders itself
        // is not an index.
        let ordered = findings.enumerated()
            .sorted { ($0.element.page, $0.offset) < ($1.element.page, $1.offset) }
            .map(\.element)

        for found in ordered {
            guard let value = found.value, !value.isEmpty else { continue }
            let key = "\(found.kind.rawValue):\(value)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(found)
        }

        return order.compactMap { key in
            guard let group = groups[key], let first = group.first else { return nil }
            return IndexEntry(value: first.value ?? "", kind: first.kind,
                              label: first.label, occurrences: group)
        }
    }

    /// The index narrowed by a search query and a kind chip, either of which may
    /// be empty.
    ///
    /// Case- and diacritic-insensitive, over the value **and** its label: a
    /// reader hunting a deadline types "date", not "April". Both filters apply
    /// together — a chip is a narrowing, not a mode.
    // `Contracts.Kind` spelled out: inside an extension on `Document`, a bare
    // `Kind` is `Document.Kind` — pdf or image — which is a different question.
    func index(matching query: String, kind: Contracts.Kind?) -> [IndexEntry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return index.filter { entry in
            guard kind == nil || entry.kind == kind else { return false }
            guard !needle.isEmpty else { return true }
            return entry.value.matches(needle) || entry.label.matches(needle)
        }
    }
}

private extension String {
    /// Substring match a person would expect from a search box: ignores case and
    /// accents, so `Résumé` answers to `resume`.
    func matches(_ needle: String) -> Bool {
        range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
