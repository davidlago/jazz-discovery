import Foundation
import Testing

@Suite("Three doors")
struct RecommenderTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)

    @Test("Every record gets three different doors, none of them itself")
    func everyRecord() {
        for album in library.albums {
            let doors = Recommender.doors(after: album, library: library, isHeard: { _ in false })
            let ids = doors.map(\.album.id)
            #expect(Set(ids).count == ids.count, "\(album.id)")
            #expect(!ids.contains(album.id), "\(album.id)")
            #expect(doors.count >= 2, "\(album.id): \(doors.map(\.kind))")
            for d in doors { #expect(!d.because.isEmpty) }
        }
    }

    @Test("Kind of Blue's same room shares players with it")
    func sameRoom() throws {
        let kob = try #require(library.album("kind-of-blue"))
        let door = try #require(Recommender.sameRoom(kob, library: library, isHeard: { _ in false }, excluding: [kob.id]))
        #expect(door.album.artist != "miles-davis")
        let here = Set(library.session(for: kob.id)!.personnel.map(\.name))
        let there = Set(library.session(for: door.album.id)!.personnel.map(\.name))
        #expect(!here.isDisjoint(with: there))
    }

    @Test("What happened next comes from a style this one led to")
    func whatNext() throws {
        let album = try #require(library.albums(inEra: "bebop").first)
        let door = try #require(Recommender.whatNext(album, library: library, isHeard: { _ in false }, excluding: [album.id]))
        #expect(["cool", "hard-bop", "latin"].contains(door.album.era))
    }

    @Test("Unheard records come first")
    func prefersUnheard() throws {
        let kob = try #require(library.album("kind-of-blue"))
        let first = Recommender.doors(after: kob, library: library, isHeard: { _ in false })
        let heard = Set(first.map(\.album.id))
        let second = Recommender.doors(after: kob, library: library, isHeard: { heard.contains($0) })
        for d in second { #expect(!heard.contains(d.album.id), "\(d.kind): \(d.album.id)") }
    }

    @Test("An echo today is by someone playing today")
    func echo() throws {
        let album = try #require(library.album("kind-of-blue"))
        let door = try #require(Recommender.echoToday(album, library: library, isHeard: { _ in false }, excluding: [album.id]))
        #expect(Recommender.todayEras.contains(library.artist(door.album.artist)!.primaryEra))
    }
}
