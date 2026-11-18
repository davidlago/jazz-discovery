import Foundation

// The words the album pages show for a session: when and where it was recorded, who was behind the glass, and which
// tracks a player is on. Shared so the Mac and iPhone say the same thing.

extension Session {
    /// "March 2 and April 22, 1959 · CBS 30th Street Studio, New York", or for a compilation "1925–1929, across many
    /// sessions". Nil when nothing is known.
    var recordedText: String? {
        if isCompilation, let span = recordedBetween, let first = span.first, let last = span.last {
            return (first == last ? "\(first)" : "\(first)–\(last)") + ", across many sessions"
        }
        let entries = recorded ?? []
        let dates = Self.datesText(entries.compactMap(\.date))
        var places: [String] = []
        for case let place? in entries.map(\.place) where !places.contains(place) { places.append(place) }
        let parts = [dates, places.isEmpty ? nil : Self.joinedList(places)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Produced by Irving Townsend · Engineered by Fred Plaut", in a fixed order of roles.
    var crewText: String? {
        let order: [(role: String, verb: String)] = [("producer", "Produced by"), ("arranger", "Arranged by"),
                                                     ("conductor", "Conducted by"), ("engineer", "Engineered by"),
                                                     ("design", "Design by"), ("photography", "Photography by")]
        let crew = crew ?? []
        let parts: [String] = order.compactMap { role, verb in
            var names: [String] = []
            for c in crew where c.role == role && !names.contains(c.name) { names.append(c.name) }
            return names.isEmpty ? nil : "\(verb) \(Self.joinedList(names))"
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Whether the credits say who plays on which track (so a track's players can be picked out).
    var hasPerTrackCredits: Bool {
        !isCompilation && personnel.contains { $0.only != nil || $0.except != nil }
    }

    // MARK: Dates

    /// Dates grouped by year: "March 2 and April 22, 1959", "May 6–27, 1957", "December 1976; January 1977".
    static func datesText(_ dates: [String]) -> String? {
        let parsed = dates.compactMap(ParsedDate.init)
        guard !parsed.isEmpty else { return nil }
        var years: [Int] = []
        for d in parsed where !years.contains(d.year) { years.append(d.year) }
        let groups = years.map { y in parsed.filter { $0.year == y } }
        return groups.map(yearText).joined(separator: "; ")
    }

    private static func yearText(_ dates: [ParsedDate]) -> String {
        let year = String(dates[0].year)
        let unique = dates.reduce(into: [ParsedDate]()) { if !$0.contains($1) { $0.append($1) } }
        if unique.allSatisfy({ $0.month == nil }) { return year }
        if unique.count > 3 {
            let months = unique.compactMap(\.month)
            if Set(months).count == 1, let m = months.first {
                let days = unique.compactMap(\.day)
                if let lo = days.min(), let hi = days.max(), days.count == unique.count {
                    return "\(monthName(m)) \(lo)–\(hi), \(year)"
                }
                return "\(monthName(m)) \(year)"
            }
            if let lo = months.min(), let hi = months.max() { return "\(monthName(lo))–\(monthName(hi)) \(year)" }
        }
        let items = unique.map { d -> String in
            guard let m = d.month else { return "" }
            return d.day.map { "\(monthName(m)) \($0)" } ?? monthName(m)
        }.filter { !$0.isEmpty }
        let anyDay = unique.contains { $0.day != nil }
        return joinedList(items) + (anyDay ? ", " : " ") + year
    }

    private struct ParsedDate: Equatable {
        let year: Int, month: Int?, day: Int?
        init?(_ s: String) {
            let p = s.split(separator: "-").map { Int($0) }
            guard let y = p.first ?? nil else { return nil }
            year = y
            month = p.count > 1 ? p[1] : nil
            day = p.count > 2 ? p[2] : nil
        }
    }

    private static func monthName(_ m: Int) -> String {
        let names = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
                     "November", "December"]
        return (1...12).contains(m) ? names[m - 1] : ""
    }

    /// "A", "A and B", "A, B and C".
    static func joinedList(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }
}

extension Credit {
    /// "tenor saxophone, soprano saxophone".
    var instrumentsText: String { instruments.joined(separator: ", ") }

    /// Which tracks, when not all: "only on “So What”", "not on 3 tracks", "4 of 93 tracks". Nil for every track.
    func tracksText(of trackCount: Int) -> String? {
        func quoted(_ titles: [String]) -> String { Session.joinedList(titles.map { "“\($0)”" }) }
        if let n = tracks {
            return n >= trackCount && trackCount > 0 ? nil : "\(n) of \(trackCount) tracks"
        }
        if let only {
            return only.count <= 3 ? "only on \(quoted(only))" : "on \(only.count) of \(trackCount) tracks"
        }
        if let except {
            return except.count <= 2 ? "not on \(quoted(except))" : "not on \(except.count) tracks"
        }
        return nil
    }
}
