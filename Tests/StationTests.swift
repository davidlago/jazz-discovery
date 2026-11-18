import Foundation
import Testing

@Suite("Radio")
struct StationTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Tracks are bundled, tied to the guide")
    func bundled() {
        #expect(library.tracks.count > 300)
        #expect(library.track("So What", by: "Miles Davis")?.album == "kind-of-blue")
        #expect(library.tracklists["kind-of-blue"]?.count ?? 0 >= 5)
    }

    @Test("Every era station has at least 12 tracks, or isn't offered")
    func eraStations() {
        let stations = Programmer.stations(library: library)
        #expect(stations.first?.kind == .longWay)
        for s in stations {
            #expect(Programmer.pool(for: s, library: library, isHeard: { _ in false }).count >= Programmer.minimumTracks, "\(s.id)")
        }
        let eras = stations.filter { if case .era = $0.kind { return true } else { return false } }
        #expect(eras.count >= 10)
    }

    @Test("No artist twice in a row, no record twice within five, across many seeds")
    func sequencing() throws {
        let station = try #require(Programmer.station(id: "era-bebop", library: library))
        let pool = Programmer.pool(for: station, library: library, isHeard: { _ in false })
        let essentials = Set(library.eras.flatMap(\.essentialTracks).map(\.id))
        for seed in UInt64(1)...200 {
            let seq = Programmer.sequence(pool, for: station, library: library, seed: seed, count: 40)
            #expect(seq.count == 40)
            #expect(essentials.contains(seq[0].ref), "seed \(seed) opens with \(seq[0].ref)")
            for i in seq.indices.dropFirst() {
                #expect(Programmer.artistKey(seq[i]) != Programmer.artistKey(seq[i - 1]), "seed \(seed) at \(i)")
                let window = seq[max(0, i - 5)..<i].compactMap(\.track.collectionId)
                if let c = seq[i].track.collectionId, window.contains(c) {
                    // Allowed only when the pool can't avoid it; bebop's can.
                    Issue.record("seed \(seed): \(seq[i].ref) repeats a record within five")
                }
            }
        }
    }

    @Test("The Long Way goes forward in time")
    func longWay() throws {
        let station = try #require(Programmer.station(id: "long-way", library: library))
        let pool = Programmer.pool(for: station, library: library, isHeard: { _ in false })
        let seq = Programmer.sequence(pool, for: station, library: library, seed: 7)
        let eraOrder = Dictionary(uniqueKeysWithValues: library.eras.enumerated().map { ($1.id, $0) })
        let order = seq.compactMap { RoundMaker.eraOf($0, library).flatMap { eraOrder[$0] } }
        #expect(order == order.sorted())
        #expect(seq.count >= 20)
    }

    @Test("Every track has a reason")
    func reasons() {
        for t in library.tracks.values { #expect(!Programmer.reason(for: t, library: library).isEmpty) }
    }
}

@Suite("Blindfold Test")
struct BlindfoldTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Ten questions, four distinct choices with the answer among them, no artist twice")
    func rounds() {
        for level in BlindLevel.allCases {
            for seed in UInt64(1)...40 {
                let round = RoundMaker.round(level: level, library: library, seed: seed)
                #expect(round.count == RoundMaker.length, "\(level) \(seed)")
                var artists = Set<String>()
                for q in round {
                    #expect(Set(q.choices.map(\.id)).count == q.choices.count)
                    #expect(q.choices.contains { $0.id == q.answer })
                    #expect(q.kind == .whichFirst ? q.choices.count == 2 : q.choices.count == 4)
                    #expect(q.clip.track.preview != nil)
                    #expect(artists.insert(Programmer.artistKey(q.clip)).inserted, "\(q.clip.ref)")
                    if let s = q.second { #expect(artists.insert(Programmer.artistKey(s)).inserted) }
                }
            }
        }
    }

    @Test("Hard era questions offer neighbouring eras")
    func hardNeighbours() {
        let round = RoundMaker.round(level: .hard, library: library, seed: 3)
        for q in round where q.kind == .era {
            let era = library.era(q.answer)!
            for c in q.choices where c.id != q.answer {
                let other = library.era(c.id)!
                #expect(abs((other.start + other.end) / 2 - (era.start + era.end) / 2) <= 40, "\(era.id) vs \(other.id)")
            }
        }
    }

    @Test("A round can focus on one era")
    func focus() {
        let round = RoundMaker.round(level: .easy, library: library, seed: 5, focus: "bebop")
        #expect(!round.isEmpty)
        for q in round { #expect(RoundMaker.eraOf(q.clip, library) == "bebop") }
    }
}
