import Foundation

/// Something that happened on a day of the year (almanac.json, built by scripts/build-almanac.py).
struct DayEvent: Codable, Hashable {
    enum Kind: String, Codable { case born, died, recorded }
    let kind: Kind
    let year: Int
    var artist: String? = nil
    var album: String? = nil
    /// Where a session was recorded.
    var place: String? = nil
    /// A hand-written line that replaces the template.
    var line: String? = nil
}

struct AlmanacData: Codable {
    var days: [String: [DayEvent]] = [:]
    /// Exact birth and death dates ("1926-05-26"), for artist pages.
    var artists: [String: [String: String]] = [:]
}

/// The calendar: what happened on any day, which event to feature, and how to say it.
struct Almanac {
    let data: AlmanacData

    static func key(month: Int, day: Int) -> String { String(format: "%02d-%02d", month, day) }

    func events(month: Int, day: Int) -> [DayEvent] {
        var out = data.days[Self.key(month: month, day: day)] ?? []
        // February 29 also shows on February 28 in other years.
        if month == 2, day == 28 { out += data.days["02-29"] ?? [] }
        return out
    }

    func events(on date: Date, calendar: Calendar = .current) -> [DayEvent] {
        let c = calendar.dateComponents([.month, .day, .year], from: date)
        guard let m = c.month, let d = c.day else { return [] }
        var out = events(month: m, day: d)
        if m == 2, d == 28, let y = c.year, isLeap(y) { out.removeAll { e in data.days["02-29"]?.contains(e) == true } }
        return out
    }

    private func isLeap(_ y: Int) -> Bool { (y % 4 == 0 && y % 100 != 0) || y % 400 == 0 }

    /// How many years ago an event was, as of `date`.
    func years(_ e: DayEvent, on date: Date, calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.year], from: date).year ?? e.year) - e.year
    }

    static func isRound(_ years: Int) -> Bool { years > 0 && years % 25 == 0 }

    /// The event to feature on a day: a round anniversary first, then sessions (they come with something to play),
    /// then births, then deaths; among equals, saved things, then unheard ones, then the older event.
    func lead(on date: Date, isSaved: (DayEvent) -> Bool = { _ in false }, isHeard: (DayEvent) -> Bool = { _ in false },
              calendar: Calendar = .current) -> DayEvent? {
        rank(events(on: date, calendar: calendar), on: date, isSaved: isSaved, isHeard: isHeard, calendar: calendar).first
    }

    func rank(_ events: [DayEvent], on date: Date, isSaved: (DayEvent) -> Bool = { _ in false },
              isHeard: (DayEvent) -> Bool = { _ in false }, calendar: Calendar = .current) -> [DayEvent] {
        let kindOrder: [DayEvent.Kind: Int] = [.recorded: 0, .born: 1, .died: 2]
        return events.sorted { a, b in
            let ra = Self.isRound(years(a, on: date, calendar: calendar)), rb = Self.isRound(years(b, on: date, calendar: calendar))
            if ra != rb { return ra }
            if kindOrder[a.kind]! != kindOrder[b.kind]! { return kindOrder[a.kind]! < kindOrder[b.kind]! }
            if isSaved(a) != isSaved(b) { return isSaved(a) }
            if isHeard(a) != isHeard(b) { return !isHeard(a) }
            return a.year < b.year
        }
    }

    /// The nearest day within three either side that has something, for an empty day.
    func nearest(to date: Date, calendar: Calendar = .current) -> (date: Date, offset: Int)? {
        for offset in [1, -1, 2, -2, 3, -3] {
            if let d = calendar.date(byAdding: .day, value: offset, to: date), !events(on: d, calendar: calendar).isEmpty {
                return (d, offset)
            }
        }
        return nil
    }

    /// The next `days` days (from tomorrow) and their leads.
    func upcoming(from date: Date, days: Int = 7, calendar: Calendar = .current) -> [(date: Date, event: DayEvent)] {
        (1...days).compactMap { i in
            guard let d = calendar.date(byAdding: .day, value: i, to: date), let e = lead(on: d, calendar: calendar) else { return nil }
            return (d, e)
        }
    }
}

extension JazzLibrary {
    var calendar: Almanac { Almanac(data: almanac) }

    /// "Miles Davis was born 100 years ago today, in 1926."
    func line(for e: DayEvent, on date: Date, today: Bool = true, calendar: Calendar = .current) -> String {
        if let l = e.line { return l }
        let n = self.calendar.years(e, on: date, calendar: calendar)
        let when = today ? "today" : "on this day"
        let ago = n == 1 ? "a year ago" : "\(n) years ago"
        switch e.kind {
        case .born:
            let name = e.artist.flatMap { artist($0)?.name } ?? "Someone"
            return Almanac.isRound(n) ? "\(name) was born \(ago) \(when), in \(String(e.year))." : "\(name) was born on this day in \(String(e.year))."
        case .died:
            let name = e.artist.flatMap { artist($0)?.name } ?? "Someone"
            return "Remembering \(name), who died on this day in \(String(e.year))."
        case .recorded:
            guard let a = e.album.flatMap({ album($0) }) else { return "A session on this day in \(String(e.year))." }
            let place = e.place.map { " at \($0.components(separatedBy: ",").first ?? $0)" } ?? ""
            let lead = Almanac.isRound(n) ? "\(ago.prefix(1).uppercased() + ago.dropFirst()) \(when)" : "On this day in \(String(e.year))"
            // A record made over several days: say which part of it this was.
            let days = (session(for: a.id)?.recorded ?? []).compactMap(\.date).filter { $0.count == 10 }.sorted()
            let mmdd = String(format: "%02d-%02d", calendar.component(.month, from: date), calendar.component(.day, from: date))
            let verb: String
            if days.count > 1, let first = days.first, let last = days.last {
                verb = first.hasSuffix(mmdd) && first.hasPrefix(String(e.year)) ? "began recording"
                    : last.hasSuffix(mmdd) && last.hasPrefix(String(e.year)) ? "finished recording" : "was back in the studio for"
            } else {
                verb = "recorded"
            }
            return "\(lead), \(a.artistName) \(verb) \(a.title)\(place)."
        }
    }

    /// "May 26, 1926 – September 28, 1991", when both dates are known.
    func fullDates(of artistID: String) -> String? {
        guard let d = almanac.artists[artistID], let born = d["born"] else { return nil }
        let f = { (s: String) -> String in
            let parts = s.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3, let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            else { return s }
            return date.formatted(.dateTime.month(.wide).day().year())
        }
        return d["died"].map { "\(f(born)) – \(f($0))" } ?? "Born \(f(born))"
    }

    /// The page an event belongs to.
    func route(for e: DayEvent) -> Route? {
        if let a = e.album { return .album(a) }
        if let a = e.artist { return .artist(a) }
        return nil
    }
}
