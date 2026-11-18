import Foundation
import Testing

@Suite("Term linker")
struct TermLinkerTests {
    static func term(_ id: String, _ term: String, also: [String] = [], explicitOnly: Bool? = nil) -> GlossaryTerm {
        GlossaryTerm(id: id, term: term, also: also, category: "Form", explicitOnly: explicitOnly, short: "", long: "", examples: [])
    }
    let linker = TermLinker(terms: [
        term("rhythm-changes", "Rhythm changes"),
        term("changes", "Changes", also: ["chord changes"]),
        term("modal", "Modal jazz", also: ["modal"]),
        term("swing", "Swing", explicitOnly: true),
        term("stride", "Stride piano", also: ["stride"]),
    ], protectedNames: ["Giant Steps", "Modal Jazz", "Steps Ahead"])

    func ids(_ s: String) -> [String] { linker.links(in: s).map(\.id) }

    @Test("Longest match wins") func longest() { #expect(ids("It's built on rhythm changes.") == ["rhythm-changes"]) }
    @Test("Only the first time in a paragraph") func firstOnly() { #expect(ids("modal here, modal there") == ["modal"]) }
    @Test("Never inside a name") func protected() {
        #expect(ids("Giant Steps has changes everywhere").first == "changes")
        #expect(ids("Modal Jazz began in 1958.").isEmpty)
    }
    @Test("Common words only when asked") func explicit() { #expect(ids("They swing hard.").isEmpty) }
    @Test("Whole words only") func words() { #expect(ids("The striders went by.").isEmpty && ids("Harlem stride, loud.") == ["stride"]) }
    @Test("Links don't overlap, and come back in order") func order() {
        let found = linker.links(in: "Stride piano and chord changes")
        #expect(found.map(\.id) == ["stride", "changes"])
        #expect(!found[0].range.overlaps(found[1].range))
    }
}

@Suite("Lineages and glossary data")
struct LineageDataTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Every link's ends are in its lineage, have a note, and go forward in time unless a reaction")
    func links() {
        #expect(library.lineages.count >= 5)
        for l in library.lineages {
            let ids = Set(l.players.map(\.artist))
            for link in l.links {
                #expect(ids.contains(link.from) && ids.contains(link.to), "\(l.id): \(link.id)")
                #expect(link.from != link.to && !link.note.isEmpty)
                if link.kind != .reaction {
                    #expect(library.comingOfAge(link.from) <= library.comingOfAge(link.to), "\(l.id): \(link.id)")
                }
            }
            for p in l.players { #expect(library.artist(p.artist) != nil, "\(p.artist)") }
        }
    }

    @Test("The tree layout is deterministic and no two faces in a lane are too close")
    func layout() {
        for l in library.lineages {
            let a = LineageLayout(lineage: l, library: library), b = LineageLayout(lineage: l, library: library)
            #expect(a.nodes == b.nodes)
            for lane in 0..<a.lanes {
                let xs = a.nodes.filter { $0.lane == lane }.map(\.x).sorted()
                for (x, y) in zip(xs, xs.dropFirst()) { #expect(y - x >= 9, "\(l.id) lane \(lane)") }
            }
        }
    }

    @Test("Most lineage tracks and every glossary example resolve")
    func tracks() {
        let refs = library.lineages.flatMap(\.players).compactMap(\.track)
        #expect(Double(refs.filter { library.tracks[$0] != nil }.count) / Double(refs.count) > 0.9)
        for t in library.glossary.terms {
            #expect(!t.examples.isEmpty, "\(t.id)")
            for e in t.examples { #expect(library.tracks[e.track] != nil, "\(t.id): \(e.track)") }
            for r in t.related { #expect(library.term(r) != nil, "\(t.id) → \(r)") }
        }
    }

    @Test("No glossary link lands inside a name anywhere in the bundled text")
    func noLinksInNames() {
        let names = library.artists.map(\.name) + library.albums.map(\.title) + library.tunes.map(\.title)
        let texts = library.eras.map(\.summary) + library.albums.map(\.why) + library.tunes.map(\.summary)
        for text in texts {
            for (range, _) in library.termLinker.links(in: text) {
                let lower = text.lowercased()
                for n in names.map({ $0.lowercased() }) where n.count > 2 {
                    var start = lower.startIndex
                    while let r = lower.range(of: n, range: start..<lower.endIndex) {
                        #expect(!r.overlaps(range), "'\(text[range])' inside '\(n)'")
                        start = r.upperBound
                    }
                }
            }
        }
    }
}
