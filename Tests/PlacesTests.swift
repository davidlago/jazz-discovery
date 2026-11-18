import Foundation
import Testing

@Suite("Places and labels")
struct PlacesTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("A place is active from its first year to its last, or to now")
    func active() {
        let p = Place(id: "x", name: "X", kind: .venue, lat: 1, lon: 1, from: 1935, to: 1950, summary: "", eras: ["swing"])
        #expect(!p.active(in: 1934) && p.active(in: 1935) && p.active(in: 1950) && !p.active(in: 1951))
        let open = Place(id: "y", name: "Y", kind: .venue, lat: 1, lon: 1, from: 1957, summary: "", eras: ["modal"])
        #expect(open.active(in: 2025) && open.years == "1957 – now")
    }

    @Test("Records made at a studio, and in its city")
    func recordedAt() throws {
        let vg = library.albums(recordedAt: "van-gelder-studio").map(\.id)
        #expect(vg.contains("a-love-supreme") || vg.contains("moanin"))
        #expect(vg.count >= 10)
        let ny = Set(library.albums(recordedAt: "new-york").map(\.id))
        #expect(ny.contains("kind-of-blue"))
        #expect(Set(library.albums(recordedAt: "columbia-30th-street").map(\.id)).isSubset(of: ny))
    }

    @Test("Every album's label matches one label or none, and every label page has records")
    func labels() {
        for a in library.albums {
            let matching = library.labels.filter { $0.matches.contains(a.label) }
            #expect(matching.count <= 1, "\(a.id)")
        }
        for l in library.labels { #expect(library.albums(onLabel: l.id).count >= 2, "\(l.id)") }
        #expect(library.label(for: library.album("kind-of-blue")!)?.id == "columbia")
        #expect(!library.regulars(onLabel: "blue-note").isEmpty)
    }

    @Test("Rooms belong to cities")
    func rooms() {
        let rooms = library.places(in: "new-york").map(\.id)
        #expect(rooms.contains("village-vanguard") && rooms.contains("mintons-playhouse"))
        for p in library.places where p.city != nil { #expect(library.place(p.city!)?.isCity == true, "\(p.id)") }
    }
}
