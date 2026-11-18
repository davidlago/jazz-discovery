import Foundation
import MapKit
import Testing

@MainActor
@Suite("1.10: stations, map groups, paths in the player")
struct FeatureTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)
    func passport() -> Passport { Passport(fileURL: nil, catalog: Passport.bundledCatalog(in: TestBundle.bundle)) }

    @Test("Cities, rooms and labels get stations, each with enough to play")
    func placeAndLabelStations() throws {
        let stations = Programmer.placeAndLabelStations(library: library)
        #expect(stations.contains { $0.id == "label-blue-note" })
        #expect(stations.contains { if case .place = $0.kind { return true } else { return false } })
        for s in stations {
            let pool = Programmer.pool(for: s, library: library, isHeard: { _ in false })
            #expect(pool.count >= Programmer.minimumPlaceTracks, "\(s.id)")
            #expect(Programmer.station(id: s.id, library: library)?.id == s.id)
        }
        // A label's station plays only its records.
        let blueNote = try #require(stations.first { $0.id == "label-blue-note" })
        let records = Set(library.albums(onLabel: "blue-note").map(\.id))
        for t in Programmer.pool(for: blueNote, library: library, isHeard: { _ in false }) {
            #expect(t.album.map { records.contains($0) } == true, "\(t.ref)")
        }
    }

    @Test("Pins that would overlap are grouped, and apart when zoomed in")
    func mapGroups() {
        let all = library.places
        let far = JazzMap.groups(all, distance: 22_000_000)
        let near = JazzMap.groups(all, distance: 2_000)
        #expect(far.count < all.count)
        #expect(near.count > far.count)
        #expect(far.flatMap(\.places).count == all.count && near.flatMap(\.places).count == all.count)
        #expect(Set(far.map(\.id)).count == far.count)
    }

    @Test("Next stop skips the stops already done")
    func nextStop() throws {
        let p = passport()
        let path = try #require(library.journey("nineteen-fifty-nine"))
        try #require(path.stops.count >= 3)
        p.setStop(path.stops[1].key, of: path.id, done: true)
        let after = try #require(PathPlayback.after(.init(pathID: path.id, index: 0), library: library, passport: p))
        #expect(after.index == 2)
        // The last stop has nothing after it.
        #expect(PathPlayback.after(.init(pathID: path.id, index: path.stops.count - 1), library: library, passport: p) == nil)
    }

    @Test("Today is the real date without --today")
    func today() {
        #expect(abs(Today.date.timeIntervalSinceNow) < 24 * 3600)
    }
}
