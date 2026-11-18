import Foundation

/// The Blindfold Test: a clip plays with its cover hidden, and you say what you're hearing.
struct BlindQuestion: Identifiable, Equatable {
    enum Kind: String, CaseIterable { case era, artist, instrument, whichFirst }
    struct Choice: Identifiable, Equatable, Hashable { let id: String; let label: String }

    let id: Int
    let kind: Kind
    let clip: StationTrack
    /// The other clip, for "which came first?".
    let second: StationTrack?
    let choices: [Choice]
    let answer: String

    var prompt: String {
        switch kind {
        case .era: return "Which era is this?"
        case .artist: return "Who's playing?"
        case .instrument: return "What's the lead instrument?"
        case .whichFirst: return "Which was recorded first?"
        }
    }
}

enum BlindLevel: String, CaseIterable, Identifiable {
    case easy = "Easy", hard = "Hard"
    var id: String { rawValue }
}

enum RoundMaker {
    static let length = 10

    /// Clips the game can use: with a preview, a year, an era and an artist in the guide, and not marked skip.
    static func clips(library: JazzLibrary, focus: String? = nil) -> [StationTrack] {
        library.tracks.values.filter { t in
            guard t.track.preview != nil, !t.skip, Programmer.year(t, library: library) != nil,
                  let era = eraOf(t, library), library.artist(ofTrack: t) != nil else { return false }
            return focus == nil || era == focus
        }
        .sorted { $0.ref < $1.ref }
    }

    static func eraOf(_ t: StationTrack, _ library: JazzLibrary) -> String? {
        t.era ?? t.album.flatMap { library.album($0)?.era }
    }

    /// Ten questions of mixed kinds, no artist twice. Easy rounds' wrong answers are far from the right one (eras far
    /// apart, other instruments); hard rounds' are close (neighbouring eras, the same instrument).
    static func round(level: BlindLevel, library: JazzLibrary, seed: UInt64, focus: String? = nil) -> [BlindQuestion] {
        var rng = SeededRandom(seed: seed)
        var pool = clips(library: library, focus: focus).shuffled(using: &rng)
        var usedArtists = Set<String>()
        var out: [BlindQuestion] = []
        var kinds: [BlindQuestion.Kind] = focus == nil ? [.era, .artist, .instrument, .whichFirst] : [.artist, .instrument, .whichFirst]
        kinds.shuffle(using: &rng)
        var attempts = 0
        while out.count < length, !pool.isEmpty, attempts < 400 {
            attempts += 1
            let kind = kinds[out.count % kinds.count]
            guard let i = pool.firstIndex(where: { !usedArtists.contains(Programmer.artistKey($0)) }) else { break }
            let clip = pool.remove(at: i)
            let q: BlindQuestion?
            switch kind {
            case .era: q = eraQuestion(clip, level: level, library: library, id: out.count, rng: &rng)
            case .artist: q = artistQuestion(clip, level: level, library: library, id: out.count, rng: &rng)
            case .instrument: q = instrumentQuestion(clip, level: level, library: library, id: out.count, rng: &rng)
            case .whichFirst:
                let other = pool.firstIndex { t in
                    !usedArtists.contains(Programmer.artistKey(t)) && Programmer.artistKey(t) != Programmer.artistKey(clip)
                        && abs((Programmer.year(t, library: library) ?? 0) - (Programmer.year(clip, library: library) ?? 0))
                            >= (level == .easy ? 15 : 4)
                }
                if let j = other {
                    let second = pool.remove(at: j)
                    usedArtists.insert(Programmer.artistKey(second))
                    q = firstQuestion(clip, second, library: library, id: out.count)
                } else { q = nil }
            }
            if let q {
                usedArtists.insert(Programmer.artistKey(clip))
                out.append(q)
            }
        }
        return out
    }

    private static func eraQuestion(_ clip: StationTrack, level: BlindLevel, library: JazzLibrary, id: Int,
                                    rng: inout SeededRandom) -> BlindQuestion? {
        guard let eraID = eraOf(clip, library), let era = library.era(eraID) else { return nil }
        let mid = (era.start + era.end) / 2
        let others = library.eras.filter { $0.id != era.id }
            .sorted { abs(($0.start + $0.end) / 2 - mid) < abs(($1.start + $1.end) / 2 - mid) }
        // Hard: the three nearest in time. Easy: three from the far half.
        let wrong = level == .hard ? Array(others.prefix(3))
                                   : Array(others.suffix(others.count / 2).shuffled(using: &rng).prefix(3))
        guard wrong.count == 3 else { return nil }
        let choices = ([era] + wrong).shuffled(using: &rng).map { BlindQuestion.Choice(id: $0.id, label: $0.name) }
        return BlindQuestion(id: id, kind: .era, clip: clip, second: nil, choices: choices, answer: era.id)
    }

    private static func artistQuestion(_ clip: StationTrack, level: BlindLevel, library: JazzLibrary, id: Int,
                                       rng: inout SeededRandom) -> BlindQuestion? {
        guard let artist = library.artist(ofTrack: clip) else { return nil }
        let family = Passport.family(artist.instrument)
        let candidates = library.artists.filter { $0.id != artist.id && library.artists.contains($0) }
        let near = candidates.filter { Passport.family($0.instrument) == family && $0.primaryEra == artist.primaryEra }
        let same = candidates.filter { Passport.family($0.instrument) == family }
        let far = candidates.filter { Passport.family($0.instrument) != family && $0.primaryEra != artist.primaryEra }
        var wrong: [Artist]
        if level == .hard {
            wrong = Array(near.shuffled(using: &rng).prefix(3))
            if wrong.count < 3 { wrong += same.filter { !wrong.contains($0) }.shuffled(using: &rng).prefix(3 - wrong.count) }
        } else {
            wrong = Array(far.shuffled(using: &rng).prefix(3))
        }
        guard wrong.count == 3 else { return nil }
        let choices = ([artist] + wrong).shuffled(using: &rng).map { BlindQuestion.Choice(id: $0.id, label: $0.name) }
        return BlindQuestion(id: id, kind: .artist, clip: clip, second: nil, choices: choices, answer: artist.id)
    }

    static let leadInstruments = ["saxophone", "trumpet", "piano", "guitar", "vocals", "trombone", "clarinet", "organ",
                                  "vibraphone", "flute", "bass", "drums"]

    private static func instrumentQuestion(_ clip: StationTrack, level: BlindLevel, library: JazzLibrary, id: Int,
                                           rng: inout SeededRandom) -> BlindQuestion? {
        // Only artists with one clear instrument ("Piano", not "Piano, composer, bandleader").
        guard let artist = library.artist(ofTrack: clip), !artist.instrument.contains(","), !artist.instrument.contains("&"),
              !artist.instrument.lowercased().contains("bandleader") else { return nil }
        let family = Passport.family(artist.instrument)
        guard leadInstruments.contains(family) else { return nil }
        let horns = ["saxophone", "trumpet", "trombone", "clarinet", "flute"]
        let others = leadInstruments.filter { $0 != family }
        let wrong: [String]
        if level == .hard, horns.contains(family) {
            wrong = Array(horns.filter { $0 != family }.shuffled(using: &rng).prefix(3))
        } else {
            wrong = Array(others.shuffled(using: &rng).prefix(3))
        }
        let choices = ([family] + wrong).shuffled(using: &rng).map { BlindQuestion.Choice(id: $0, label: $0.capitalized) }
        return BlindQuestion(id: id, kind: .instrument, clip: clip, second: nil, choices: choices, answer: family)
    }

    private static func firstQuestion(_ a: StationTrack, _ b: StationTrack, library: JazzLibrary, id: Int) -> BlindQuestion? {
        guard let ya = Programmer.year(a, library: library), let yb = Programmer.year(b, library: library), ya != yb else { return nil }
        let choices = [BlindQuestion.Choice(id: "first", label: "The first clip"),
                       BlindQuestion.Choice(id: "second", label: "The second clip")]
        return BlindQuestion(id: id, kind: .whichFirst, clip: a, second: b, choices: choices, answer: ya < yb ? "first" : "second")
    }
}
