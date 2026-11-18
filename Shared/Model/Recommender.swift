import Foundation

/// A way out of a record: three different records to hear next, each with a sentence saying why.
struct Door: Identifiable, Equatable {
    enum Kind: String, CaseIterable {
        case sameRoom, whatNext, echoToday

        var title: String {
            switch self {
            case .sameRoom: return "Same Room"
            case .whatNext: return "What Happened Next"
            case .echoToday: return "An Echo Today"
            }
        }
    }
    let kind: Kind
    let album: Album
    let because: String
    var id: String { kind.rawValue }
}

enum Recommender {
    /// Eras whose artists count as playing today.
    static let todayEras: Set<String> = ["post-bop", "contemporary"]

    /// Up to three doors out of `album`: the record sharing the most players with it, one from the style that came
    /// next, and one from a living line that leads back to its leader. Each prefers a record you haven't heard, and
    /// no record appears twice (or is the album itself).
    static func doors(after album: Album, library: JazzLibrary, isHeard: (String) -> Bool) -> [Door] {
        var used: Set<String> = [album.id]
        var doors: [Door] = []
        func take(_ door: Door?) {
            guard let door, !used.contains(door.album.id) else { return }
            used.insert(door.album.id)
            doors.append(door)
        }
        take(sameRoom(album, library: library, isHeard: isHeard, excluding: used))
        take(whatNext(album, library: library, isHeard: isHeard, excluding: used))
        take(echoToday(album, library: library, isHeard: isHeard, excluding: used))
        return doors
    }

    /// Unheard first, then by `rank` (lower is better).
    private static func best(_ albums: [Album], isHeard: (String) -> Bool, excluding: Set<String>,
                             rank: (Album) -> Double) -> Album? {
        albums.filter { !excluding.contains($0.id) }
            .min { a, b in
                let ha = isHeard(a.id), hb = isHeard(b.id)
                if ha != hb { return !ha }
                let ra = rank(a), rb = rank(b)
                return ra != rb ? ra < rb : a.year < b.year
            }
    }

    // MARK: Same room

    /// Who's credited on a record, by artist ID or (for players without a page) by name.
    private static func players(_ albumID: String, library: JazzLibrary) -> [String: String] {
        guard let s = library.session(for: albumID) else { return [:] }
        var out: [String: String] = [:]
        for c in s.personnel { out[c.artist ?? c.name.lowercased()] = c.name }
        return out
    }

    static func sameRoom(_ album: Album, library: JazzLibrary, isHeard: (String) -> Bool,
                         excluding: Set<String>) -> Door? {
        let here = players(album.id, library: library)
        if !here.isEmpty {
            var shared: [String: [String]] = [:]
            for other in library.albums where other.artist != album.artist && !excluding.contains(other.id) {
                let names = players(other.id, library: library).keys.filter { here[$0] != nil && $0 != album.artist }
                if !names.isEmpty { shared[other.id] = names.map { here[$0]! } }
            }
            if !shared.isEmpty {
                let candidates = library.albums.filter { shared[$0.id] != nil }
                if let pick = best(candidates, isHeard: isHeard, excluding: excluding,
                                   rank: { -Double(shared[$0.id]!.count) + Double(abs($0.year - album.year)) / 100 }) {
                    return Door(kind: .sameRoom, album: pick, because: sameRoomText(pick, shared: shared[pick.id]!, here: here))
                }
            }
        }
        // No credits to go on: the leader's closest tie, and their best record.
        for tie in library.ties(of: album.artist) {
            let other = tie.other(than: album.artist)
            guard let artist = library.artist(other) else { continue }
            let led = library.albums(by: other).filter { $0.artist == other }
            if let pick = best(led, isHeard: isHeard, excluding: excluding, rank: { $0.starter ? 0 : 1 }) {
                let because: String
                if let together = tie.albums.first {
                    because = "\(artist.name) played with \(album.artistName) on \(together.title)."
                } else if let note = tie.bond?.note {
                    because = note
                } else {
                    because = "\(artist.name) and \(album.artistName) played together."
                }
                return Door(kind: .sameRoom, album: pick, because: because)
            }
        }
        return nil
    }

    /// "Paul Chambers and Jimmy Cobb play on this one too." or "John Coltrane leads this one, with Paul Chambers along."
    private static func sameRoomText(_ pick: Album, shared: [String], here: [String: String]) -> String {
        let leader = here[pick.artist]
        let others = shared.filter { $0 != leader }.sorted()
        let list = others.count > 3 ? "\(others.prefix(2).joined(separator: ", ")) and \(others.count - 2) more"
                                    : Session.joinedList(others)
        switch (leader, others.isEmpty) {
        case (let l?, true): return "\(l), who plays here, leads this one."
        case (let l?, false): return "\(l), who plays here, leads this one, with \(list) along again."
        default: return "\(list) \(others.count == 1 ? "plays" : "play") on this one too."
        }
    }

    // MARK: What happened next

    static func whatNext(_ album: Album, library: JazzLibrary, isHeard: (String) -> Bool,
                         excluding: Set<String>) -> Door? {
        guard let era = library.era(album.era) else { return nil }
        let next = (era.leadsTo ?? []).compactMap { library.era($0) }
        let candidates = next.flatMap { library.albums(inEra: $0.id) }
        // The closest record after this one; starter picks first; records from before it last.
        let pick = best(candidates, isHeard: isHeard, excluding: excluding) { a in
            let gap = Double(a.year - album.year)
            return (gap < 0 ? 100 - gap : gap) - (a.starter ? 3 : 0)
        }
        if let pick, let to = library.era(pick.era) {
            return Door(kind: .whatNext, album: pick, because: "\(era.name) led to \(to.name): \(to.tagline).")
        }
        // The newest style: a later record from the same one.
        let later = library.albums(inEra: era.id).filter { $0.year > album.year }
        guard let p = best(later, isHeard: isHeard, excluding: excluding, rank: { Double($0.year - album.year) }) else { return nil }
        let n = p.year - album.year
        return Door(kind: .whatNext, album: p, because: "\(era.name), \(n) year\(n == 1 ? "" : "s") later.")
    }

    // MARK: An echo today

    static func echoToday(_ album: Album, library: JazzLibrary, isHeard: (String) -> Bool,
                          excluding: Set<String>) -> Door? {
        // Walk the ties outward from the leader, nearest first, to someone playing today who leads a record here.
        var seen: Set<String> = [album.artist]
        var frontier: [[String]] = [[album.artist]]
        // A heard record found along the line, kept in case nothing unheard turns up further out.
        var heardDoor: Door?
        // At most three links: further than that, the line says little.
        while !frontier.isEmpty && frontier[0].count <= 3 {
            var next: [[String]] = []
            var found: [(chain: [String], album: Album)] = []
            for chain in frontier {
                for tie in library.ties(of: chain.last!) {
                    let other = tie.other(than: chain.last!)
                    guard !seen.contains(other) else { continue }
                    seen.insert(other)
                    let path = chain + [other]
                    if let a = library.artist(other), todayEras.contains(a.primaryEra) {
                        let led = library.albums(by: other).filter { $0.artist == other }
                        if let pick = best(led, isHeard: isHeard, excluding: excluding, rank: { $0.starter ? 0 : 1 }) {
                            found.append((path, pick))
                        }
                    }
                    next.append(path)
                }
            }
            if let f = found.min(by: { a, b in
                let ha = isHeard(a.album.id), hb = isHeard(b.album.id)
                return ha != hb ? !ha : a.album.year > b.album.year
            }) {
                let names = f.chain.compactMap { library.artist($0)?.name }
                let because = names.count == 2
                    ? "\(names[1]) carries it on: \(names[0]) and \(names[1]) are linked directly."
                    : "Linked through \(names.dropFirst().dropLast().joined(separator: " and ")): \(names.joined(separator: " → "))."
                let door = Door(kind: .echoToday, album: f.album, because: because)
                // Everything this close has been heard: look further out for something new first.
                guard isHeard(f.album.id) else { return door }
                if heardDoor == nil { heardDoor = door }
            }
            frontier = next
        }
        if let heardDoor { return heardDoor }
        // No line: a record today by someone on the same instrument.
        let instrument = library.artist(album.artist).map { Passport.family($0.instrument) }
        let today = library.albums.filter { a in
            guard let lead = library.artist(a.artist), todayEras.contains(lead.primaryEra) else { return false }
            return instrument == nil || Passport.family(lead.instrument) == instrument
        }
        if let pick = best(today, isHeard: isHeard, excluding: excluding, rank: { -Double($0.year) }) {
            return Door(kind: .echoToday, album: pick, because: "The same instrument today, in the hands of \(pick.artistName).")
        }
        // Not even that: where the music has got to now, newest first.
        let now = library.albums.filter { a in library.artist(a.artist).map { todayEras.contains($0.primaryEra) } ?? false }
        guard let pick = best(now, isHeard: isHeard, excluding: excluding, rank: { -Double($0.year) }),
              let era = library.era(album.era) else { return nil }
        return Door(kind: .echoToday, album: pick, because: "Where the line from \(era.name) has got to today: \(pick.artistName).")
    }
}
