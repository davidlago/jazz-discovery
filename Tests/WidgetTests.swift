import Foundation
import Testing

@MainActor
@Suite("Widgets")
struct WidgetTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)
    let cal = Calendar(identifier: .gregorian)
    func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
    func passport() -> Passport { Passport(fileURL: nil, catalog: Passport.bundledCatalog(in: TestBundle.bundle)) }

    @Test("Today in Jazz: the lead, its link and its one-line version")
    func today() throws {
        let c = try #require(library.todayWidget(on: date(2026, 5, 26), calendar: cal))
        #expect(c.label == "TODAY IN JAZZ")
        #expect(c.line == "Miles Davis was born 100 years ago today, in 1926.")
        #expect(c.short == "Miles Davis · born 1926")
        #expect(c.link.absoluteString == "jazzdiscovery://artist/miles-davis")
        #expect(c.artistID == "miles-davis" && c.albumID == nil)
    }

    @Test("A session links to its record")
    func session() throws {
        let c = try #require(library.todayWidget(on: date(2026, 3, 2), calendar: cal))
        #expect(c.albumID == "kind-of-blue")
        #expect(c.link.absoluteString == "jazzdiscovery://album/kind-of-blue")
    }

    @Test("Every day of the year has something to show, today or nearby")
    func everyDay() {
        var empty: [String] = []
        for offset in 0..<366 {
            let d = cal.date(byAdding: .day, value: offset, to: date(2028, 1, 1))!
            guard let c = library.todayWidget(on: d, calendar: cal) else {
                empty.append(d.formatted(.dateTime.month().day())); continue
            }
            #expect(!c.line.isEmpty && !c.short.contains("Someone") && !c.short.contains("someone"))
            #expect(DeepLink(c.link, library: library) != nil, "\(c.link)")
        }
        // The almanac has gaps of more than three days; those show the app's own fallback text.
        #expect(empty.count < 60, "\(empty)")
    }

    @Test("An empty day shows the nearest one, labelled")
    func nearest() throws {
        let day = try #require((1...366).lazy.map { self.cal.date(byAdding: .day, value: $0, to: self.date(2026, 1, 1))! }
            .first { library.calendar.events(on: $0, calendar: cal).isEmpty && library.calendar.nearest(to: $0, calendar: cal) != nil })
        let c = try #require(library.todayWidget(on: day, calendar: cal))
        #expect(c.label != "TODAY IN JAZZ")
        #expect(!cal.isDate(c.day, inSameDayAs: day))
    }

    @Test("The snapshot: the path in progress and its next stop")
    func pathSnapshot() throws {
        let p = passport()
        let path = try #require(library.journey("nineteen-fifty-nine"))
        p.setStop(path.stops[0].key, of: path.id, done: true)
        let s = WidgetSnapshot(passport: p, library: library)
        let state = try #require(s.path)
        #expect(state.id == path.id && state.title == path.title)
        #expect(state.done >= 1 && state.total == path.stops.count)
        let next = library.title(of: path.stops[try #require(p.progress(on: path, library: library).next)])
        #expect(state.nextTitle == next.title)
        #expect(s.link.absoluteString == "jazzdiscovery://path/\(path.id)")
    }

    @Test("The snapshot: the stamp nearest to inking in")
    func eraSnapshot() throws {
        let p = passport()
        // Records on no path, so hearing them starts none.
        let onPaths = Set(library.paths.flatMap(\.stops).filter { $0.kind == .album }.map(\.ref))
        let bebop = library.albums(inEra: "bebop").filter { !onPaths.contains($0.id) }
        try #require(bebop.count >= 2)
        p.setHeard(bebop[0].id, true)
        p.setHeard(bebop[1].id, true)
        if let other = library.albums.first(where: { $0.era != "bebop" && !onPaths.contains($0.id) }) { p.setHeard(other.id, true) }
        let s = WidgetSnapshot(passport: p, library: library)
        #expect(s.path == nil)
        #expect(s.era?.id == "bebop" && s.era?.heard == 2)
        #expect(s.heard.count == 3 && s.heardCount == 3)
        #expect(s.link.absoluteString == "jazzdiscovery://era/bebop")
        // Round trip, as the widget reads it.
        let back = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test("Saved and heard records rank the day as the app does")
    func ranking() throws {
        // A day with more than one event of the lead's kind, so saving the second one moves it up.
        let day = try #require((1...366).lazy.map { self.cal.date(byAdding: .day, value: $0, to: self.date(2026, 1, 1))! }
            .first { d in
                let events = library.calendar.events(on: d, calendar: cal).filter { $0.kind == .recorded && $0.album != nil }
                return events.count >= 2 && !events.contains { Almanac.isRound(library.calendar.years($0, on: d, calendar: cal)) }
            })
        let plain = try #require(library.todayWidget(on: day, calendar: cal))
        let others = library.calendar.events(on: day, calendar: cal).compactMap(\.album).filter { $0 != plain.albumID }
        let other = try #require(others.first)
        var snapshot = WidgetSnapshot()
        snapshot.saved = [other]
        let ranked = try #require(library.todayWidget(on: day, snapshot: snapshot, calendar: cal))
        #expect(ranked.albumID == other)
    }

    @Test("Nothing heard yet: no stamp, so the widget invites you to Start Here")
    func emptySnapshot() {
        let s = WidgetSnapshot(passport: passport(), library: library)
        #expect(s.path == nil && s.era == nil)
        #expect(s.link.absoluteString == "jazzdiscovery://paths")
    }

    @Test("No app group, nothing written (tests and unsigned builds)")
    func noGroup() {
        #expect(AppGroup.identifier == nil)
        #expect(AppGroup.write(WidgetSnapshot()) == false)
        #expect(AppGroup.read() == nil)
    }
}
