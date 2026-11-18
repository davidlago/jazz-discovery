import Foundation

/// Finds glossary terms in prose and links them (`jazzdiscovery://term/<id>`): the longest match first, on word
/// boundaries, only the first time a term appears in a paragraph, never inside a protected name (an artist, album,
/// tune or era: "Giant Steps" isn't "steps", "Modal Jazz" the era isn't the term), and never for common words marked
/// `explicitOnly`.
struct TermLinker {
    private struct Pattern { let id: String; let text: String }
    private let patterns: [Pattern]
    private let protected: [String]

    init(terms: [GlossaryTerm], protectedNames: [String]) {
        patterns = terms.filter(\.linksAutomatically)
            .flatMap { t in ([t.term] + t.also).map { Pattern(id: t.id, text: $0.lowercased()) } }
            .sorted { $0.text.count > $1.text.count }
        protected = protectedNames.map { $0.lowercased() }.filter { $0.count > 2 }.sorted { $0.count > $1.count }
    }

    /// The links in a paragraph: character ranges and term IDs, in order.
    func links(in text: String) -> [(range: Range<String.Index>, id: String)] {
        let lower = text.lowercased()
        guard lower.count == text.count else { return [] }   // case-folding changed the length; don't risk it
        var taken: [Range<String.Index>] = []
        // Protected names are taken first, so nothing links inside them.
        for name in protected {
            var start = lower.startIndex
            while let r = lower.range(of: name, range: start..<lower.endIndex) {
                if !taken.contains(where: { $0.overlaps(r) }) { taken.append(r) }
                start = r.upperBound
            }
        }
        var found: [(Range<String.Index>, String)] = []
        var linkedIDs = Set<String>()
        for p in patterns where !linkedIDs.contains(p.id) {
            var start = lower.startIndex
            while let r = lower.range(of: p.text, range: start..<lower.endIndex) {
                start = r.upperBound
                guard isWordBoundary(lower, r), !taken.contains(where: { $0.overlaps(r) }) else { continue }
                found.append((r, p.id))
                taken.append(r)
                linkedIDs.insert(p.id)
                break
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { (range: $0.0, id: $0.1) }
    }

    /// The paragraph with its terms as links.
    func attributed(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        for (range, id) in links(in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].link = URL(string: "jazzdiscovery://term/\(id)")
        }
        return out
    }

    private func isWordBoundary(_ s: String, _ r: Range<String.Index>) -> Bool {
        let before = r.lowerBound == s.startIndex ? nil : s[s.index(before: r.lowerBound)]
        let after = r.upperBound == s.endIndex ? nil : s[r.upperBound]
        func isWord(_ c: Character?) -> Bool { c.map { $0.isLetter || $0.isNumber } ?? false }
        return !isWord(before) && !isWord(after)
    }
}
