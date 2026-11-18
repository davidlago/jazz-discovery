import Foundation
import Testing

@Suite("On This Day")
struct AlmanacTests {
    let library = JazzLibrary.load(from: TestBundle.bundle)
    let cal = Calendar(identifier: .gregorian)
    func date(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }

    @Test("A birthday, a session day")
    func days() {
        let may26 = library.calendar.events(on: date(2026, 5, 26), calendar: cal)
        #expect(may26.contains { $0.kind == .born && $0.artist == "miles-davis" })
        let mar2 = library.calendar.events(on: date(2026, 3, 2), calendar: cal)
        #expect(mar2.contains { $0.kind == .recorded && $0.album == "kind-of-blue" })
    }

    @Test("Lines read right, with round anniversaries called out")
    func lines() {
        let e = DayEvent(kind: .born, year: 1926, artist: "miles-davis")
        #expect(library.line(for: e, on: date(2026, 5, 26), calendar: cal) == "Miles Davis was born 100 years ago today, in 1926.")
        #expect(library.line(for: e, on: date(2027, 5, 26), calendar: cal) == "Miles Davis was born on this day in 1926.")
        let kob = DayEvent(kind: .recorded, year: 1959, album: "kind-of-blue", place: "CBS 30th Street Studio, New York")
        #expect(library.line(for: kob, on: date(2026, 3, 2), calendar: cal)
                == "On this day in 1959, Miles Davis began recording Kind of Blue at CBS 30th Street Studio.")
        for (_, events) in library.almanac.days {
            for e in events {
                let l = library.line(for: e, on: date(2026, 6, 1), today: false, calendar: cal)
                #expect(!l.contains("Someone") && !l.isEmpty, "\(e)")
            }
        }
    }

    @Test("A round anniversary outranks an ordinary session; deaths come last")
    func ranking() {
        let a = DayEvent(kind: .recorded, year: 1960, album: "giant-steps")
        let b = DayEvent(kind: .born, year: 1926, artist: "miles-davis")
        let c = DayEvent(kind: .died, year: 1991, artist: "miles-davis")
        let ranked = library.calendar.rank([c, a, b], on: date(2026, 1, 1), calendar: cal)
        #expect(ranked.map(\.kind) == [.born, .recorded, .died])
    }

    @Test("An empty day falls back to the nearest one with something")
    func fallback() {
        let empty = (1...365).lazy.map { self.cal.date(byAdding: .day, value: $0, to: self.date(2025, 12, 31))! }
            .first { library.calendar.events(on: $0, calendar: cal).isEmpty }
        if let empty {
            if let near = library.calendar.nearest(to: empty, calendar: cal) {
                #expect(abs(near.offset) <= 3 && !library.calendar.events(on: near.date, calendar: cal).isEmpty)
            }
        }
        #expect(library.calendar.upcoming(from: date(2026, 5, 20), days: 7, calendar: cal).count >= 3)
    }

    @Test("Full dates on artist pages")
    func fullDates() {
        #expect(library.fullDates(of: "miles-davis") == "May 26, 1926 – September 28, 1991")
    }
}
