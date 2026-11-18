import Foundation
import Testing

@MainActor
@Suite("Search, Songbook forms, Crate by label, passport fields")
struct LooseEndsTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Search finds places, labels, glossary terms, paths and listening guides")
    func search() {
        #expect(library.search("vanguard").places.contains { $0.name.contains("Vanguard") })
        #expect(library.search("blue note").labels.contains { $0.id == "blue-note" })
        #expect(library.search("comping").terms.contains { $0.id == "comping" })
        #expect(library.search("late night").paths.contains { $0.id == "late-night" })
        #expect(library.search("so what").guides.contains { $0.id == "so-what" })
        #expect(!library.search("so what").isEmpty)
    }

    @Test("Same form: the blues together, 32-bar AABA songs together, the rest on their own")
    func sameForm() throws {
        let monk = try #require(library.tune("blue-monk"))
        #expect(monk.formFamily == "blues")
        #expect(library.sameForm(as: monk).map(\.id).contains("straight-no-chaser"))
        #expect(!library.sameForm(as: monk).contains(monk))
        let misty = try #require(library.tune("misty"))
        #expect(library.sameForm(as: misty).map(\.id).contains("body-and-soul"))
        #expect(library.tune("lush-life")?.formFamily == nil)
    }

    @Test("The Crate by label: every record once, labels with pages first in founding order")
    func byLabel() {
        let groups = library.groupedByLabel(library.albums)
        #expect(groups.flatMap(\.albums).count == library.albums.count)
        let founded = groups.compactMap { $0.label?.founded }
        #expect(founded == founded.sorted())
        #expect(groups.last?.label == nil || groups.allSatisfy { $0.label != nil })
    }

    @Test("Guides are found from a track's song ID")
    func guideForSong() throws {
        let t = try #require(library.tracks["Dave Brubeck|Take Five"])
        #expect(library.guide(forSongID: t.id)?.id == "take-five")
    }

    @Test("Fields from a newer version survive reading, merging and writing")
    func unknownFields() throws {
        let json = #"{"albums":{},"artists":{},"future":{"a":[1,"two",true,null]},"note":"hi"}"#
        let mine = try JSONDecoder().decode(PassportData.self, from: Data(json.utf8))
        #expect(mine.unknown?["note"] == .string("hi"))
        let merged = PassportData.merged(mine, PassportData())
        #expect(merged == PassportData.merged(PassportData(), mine))
        let out = String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        #expect(out.contains("\"future\"") && out.contains("\"note\""))
        let back = try JSONDecoder().decode(PassportData.self, from: Data(out.utf8))
        #expect(back.unknown == mine.unknown)
    }
}
