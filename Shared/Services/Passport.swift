import Foundation
import Observation

// The listening passport: which records you've heard, sampled and saved, and the artists you've saved. Kept in one
// JSON file in Application Support (it must outlive a cache cleanup), and later synced through iCloud. Every yes/no
// remembers when it was set, so two copies merge field by field with the later change winning, an un-mark included.

/// A yes or no, and when it was set.
struct Flag: Codable, Equatable {
    enum How: String, Codable { case hand, listening, lastFM }
    var on: Bool
    var at: Date
    /// For Heard: marked by hand, by listening in the app, or from Last.fm.
    var how: How?

    /// The later of two; on a tie, the yes (so the merge doesn't depend on order).
    static func latest(_ a: Flag?, _ b: Flag?) -> Flag? {
        guard let a else { return b }
        guard let b else { return a }
        if a.at != b.at { return a.at > b.at ? a : b }
        return a.on ? a : b
    }
}

/// What the passport knows about one record (or one artist, for whom only Saved is used).
struct PassportMark: Codable, Equatable {
    var heard: Flag?
    var saved: Flag?
    /// The first time a preview of one of its tracks played.
    var sampled: Date?
    /// Songs (Apple Music IDs) heard in full that count toward Heard, and when each first did.
    var songs: [String: Date]?

    var isHeard: Bool { heard?.on == true }
    var isSaved: Bool { saved?.on == true }
    var isEmpty: Bool { heard == nil && saved == nil && sampled == nil && (songs ?? [:]).isEmpty }

    static func merged(_ a: PassportMark, _ b: PassportMark) -> PassportMark {
        var m = PassportMark()
        m.heard = Flag.latest(a.heard, b.heard)
        m.saved = Flag.latest(a.saved, b.saved)
        m.sampled = [a.sampled, b.sampled].compactMap { $0 }.min()
        let songs = (a.songs ?? [:]).merging(b.songs ?? [:]) { min($0, $1) }
        m.songs = songs.isEmpty ? nil : songs
        return m
    }
}

/// Blindfold Test answers for one era.
struct EarScore: Codable, Equatable {
    var right: Int
    var total: Int
    var at: Date
}

struct PassportData: Codable, Equatable {
    var albums: [String: PassportMark] = [:]
    var artists: [String: PassportMark] = [:]
    /// Blindfold Test results by era (added in 1.3).
    var ears: [String: EarScore]? = nil

    /// Both orders give the same result.
    static func merged(_ a: PassportData, _ b: PassportData) -> PassportData {
        func merge(_ x: [String: PassportMark], _ y: [String: PassportMark]) -> [String: PassportMark] {
            x.merging(y) { PassportMark.merged($0, $1) }
        }
        // Scores: the more recently updated copy of each era's tally.
        let ears = (a.ears ?? [:]).merging(b.ears ?? [:]) { x, y in
            x.at != y.at ? (x.at > y.at ? x : y) : (x.total >= y.total ? x : y)
        }
        return PassportData(albums: merge(a.albums, b.albums), artists: merge(a.artists, b.artists),
                            ears: ears.isEmpty ? nil : ears)
    }
}

/// A track the player played: a preview starting, or a full track passing the listening threshold (half the song or
/// four minutes, as for scrobbling).
struct ListenEvent: Equatable {
    /// Apple Music song ID.
    let songID: String
    /// The Apple Music album it was played from, when known.
    let collectionId: Int?
    let full: Bool
    var at: Date = .now
}

/// Counts real listening time for the track that's playing and says once when it passes the threshold.
struct ListenMeter {
    private(set) var key: String?
    private var seconds = 0.0
    private var threshold = Double.infinity
    private var fired = false

    /// Half the song or four minutes, whichever comes first; four minutes if the length isn't known.
    static func threshold(duration: Double?) -> Double {
        guard let d = duration, d > 0 else { return 240 }
        return d > 30 ? min(d / 2, 240) : .infinity
    }

    /// Starts measuring a new track (the same key keeps counting, and may update the length).
    mutating func track(_ key: String?, duration: Double?) {
        if key != self.key {
            self.key = key; seconds = 0; fired = false
        }
        threshold = Self.threshold(duration: duration)
    }

    /// Adds listening time; true the one time the track crosses the threshold.
    mutating func add(_ s: Double) -> Bool {
        guard key != nil, !fired, s > 0 else { return false }
        seconds += s
        if seconds >= threshold { fired = true; return true }
        return false
    }
}

@MainActor
@Observable
final class Passport {
    /// A record counts as heard once this share of its tracks has been heard in full.
    static let heardShare = 0.6

    private(set) var data = PassportData()
    /// Told after every change, to send it to iCloud.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Whether the passport syncs through iCloud (the build has the entitlement and an account is signed in).
    var syncsWithICloud = false
    @ObservationIgnored let fileURL: URL?
    /// Apple Music album ID → Crate album ID, and how many tracks each has (catalog.json).
    @ObservationIgnored private let albumByCollection: [Int: String]
    @ObservationIgnored private let trackCounts: [String: Int]

    /// `fileURL` nil keeps the passport in memory only (tests, snapshots).
    init(fileURL: URL? = Passport.defaultFile, catalog: [String: CatalogAlbum] = Passport.bundledCatalog()) {
        self.fileURL = fileURL
        albumByCollection = Dictionary(catalog.map { ($0.value.collectionId, $0.key) }, uniquingKeysWith: { a, _ in a })
        trackCounts = catalog.compactMapValues(\.trackCount)
        if let fileURL, let d = try? Data(contentsOf: fileURL), let saved = try? Self.decoder.decode(PassportData.self, from: d) {
            data = saved
        }
    }

    nonisolated static var defaultFile: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("JazzDiscovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("passport.json")
    }

    nonisolated static func bundledCatalog(in bundle: Bundle = .main) -> [String: CatalogAlbum] {
        guard let url = bundle.url(forResource: "catalog", withExtension: "json"), let d = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: CatalogAlbum].self, from: d) else { return [:] }
        return map
    }

    // MARK: Reading

    /// The Crate record an Apple Music album ID belongs to.
    func albumID(forCollection id: Int) -> String? { albumByCollection[id] }

    func mark(_ albumID: String) -> PassportMark? { data.albums[albumID] }
    func isHeard(_ albumID: String) -> Bool { data.albums[albumID]?.isHeard == true }
    /// A preview played, but not heard.
    func isSampled(_ albumID: String) -> Bool { !isHeard(albumID) && data.albums[albumID]?.sampled != nil }
    func isSaved(_ albumID: String) -> Bool { data.albums[albumID]?.isSaved == true }
    func isSaved(artist id: String) -> Bool { data.artists[id]?.isSaved == true }

    var heardCount: Int { data.albums.values.filter(\.isHeard).count }
    var isEmpty: Bool { !data.albums.values.contains { $0.isHeard || $0.isSaved || $0.sampled != nil } && savedArtists.isEmpty }

    /// Heard, sampled (and not heard) and all records in an era.
    func progress(inEra id: String, library: JazzLibrary) -> (heard: Int, sampled: Int, total: Int) {
        let albums = library.albums(inEra: id)
        return (albums.filter { isHeard($0.id) }.count, albums.filter { isSampled($0.id) }.count, albums.count)
    }

    /// Records heard, the latest first.
    func recentlyHeard(limit: Int = 20) -> [(albumID: String, at: Date)] {
        let heard: [(albumID: String, at: Date)] = data.albums.compactMap { id, m in
            guard m.isHeard, let at = m.heard?.at else { return nil }
            return (albumID: id, at: at)
        }
        return Array(heard.sorted { $0.at > $1.at }.prefix(limit))
    }

    var savedAlbums: [String] { data.albums.filter(\.value.isSaved).sorted { $0.value.saved!.at > $1.value.saved!.at }.map(\.key) }
    var savedArtists: [String] { data.artists.filter(\.value.isSaved).sorted { $0.value.saved!.at > $1.value.saved!.at }.map(\.key) }

    // MARK: Marking

    func setHeard(_ albumID: String, _ on: Bool, how: Flag.How = .hand, at: Date = .now) {
        update(albumID) { m in
            m.heard = Flag(on: on, at: Self.stamp(at), how: on ? how : nil)
            // Un-marking starts the count of heard tracks over, so it isn't marked again by the next song.
            if !on { m.songs = nil }
        }
    }

    func toggleHeard(_ albumID: String) { setHeard(albumID, !isHeard(albumID)) }

    func setSaved(_ albumID: String, _ on: Bool, at: Date = .now) {
        update(albumID) { $0.saved = Flag(on: on, at: Self.stamp(at)) }
    }

    func toggleSaved(_ albumID: String) { setSaved(albumID, !isSaved(albumID)) }

    func toggleSaved(artist id: String, at: Date = .now) {
        var m = data.artists[id] ?? PassportMark()
        m.saved = Flag(on: !m.isSaved, at: Self.stamp(at))
        data.artists[id] = m
        save()
    }

    /// From the player: a preview marks its record sampled; a full track counts toward Heard.
    func listened(_ e: ListenEvent) {
        let at = Self.stamp(e.at)
        guard let c = e.collectionId, let albumID = albumByCollection[c] else { return }
        if !e.full {
            guard data.albums[albumID]?.sampled == nil else { return }
            update(albumID) { $0.sampled = at }
            return
        }
        guard data.albums[albumID]?.songs?[e.songID] == nil else { return }
        update(albumID) { m in
            var songs = m.songs ?? [:]
            songs[e.songID] = at
            m.songs = songs
            if m.sampled == nil { m.sampled = at }
            // Heard once enough of the record has been heard, unless it was un-marked by hand since.
            let total = trackCounts[albumID] ?? 0
            if !m.isHeard, total > 0, Double(songs.count) >= (Double(total) * Self.heardShare).rounded(.up) {
                m.heard = Flag(on: true, at: at, how: .listening)
            }
        }
    }

    /// Replaces everything with what's merged in from elsewhere (another device). Writes only if something changed.
    func merge(_ other: PassportData) {
        let m = PassportData.merged(data, other)
        guard m != data else { return }
        data = m
        save()
    }

    fileprivate func replaceEars(_ ears: [String: EarScore]) {
        data.ears = ears
        save()
    }

    func erase() {
        data = PassportData()
        save()
    }

    // MARK: Storage

    /// Whole seconds: what the file keeps, so a date read back equals the one written and merges see no change.
    nonisolated static func stamp(_ d: Date) -> Date { Date(timeIntervalSince1970: d.timeIntervalSince1970.rounded(.down)) }

    private func update(_ albumID: String, _ change: (inout PassportMark) -> Void) {
        var m = data.albums[albumID] ?? PassportMark()
        change(&m)
        data.albums[albumID] = m
        save()
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func encoded() -> Data? { try? Self.encoder.encode(data) }
    static func decode(_ d: Data) -> PassportData? { try? decoder.decode(PassportData.self, from: d) }

    private func save() {
        onChange?()
        guard let fileURL, let d = encoded() else { return }
        try? d.write(to: fileURL, options: .atomic)
    }
}

extension Passport {
    /// Fills an in-memory passport with a believable history, for snapshots and App Store screenshots
    /// (`--demo-passport`). Never used on a real one.
    func fillWithDemo(library: JazzLibrary) {
        guard fileURL == nil, isEmpty else { return }
        for (i, a) in library.albums.enumerated() where i % 3 == 0 || a.era == "bebop" || a.era == "modal" {
            setHeard(a.id, true, how: i % 2 == 0 ? .listening : .hand, at: .now.addingTimeInterval(Double(-i * 5400)))
        }
        for (i, a) in library.albums.enumerated() where i % 7 == 1 { setSaved(a.id, true) }
        for id in ["thelonious-monk", "mary-lou-williams", "nubya-garcia"] where library.artist(id) != nil { toggleSaved(artist: id) }
    }
}

extension Passport {
    /// Counts a Blindfold Test answer toward its era.
    func recordAnswer(era: String, right: Bool, at: Date = .now) {
        var ears = data.ears ?? [:]
        var s = ears[era] ?? EarScore(right: 0, total: 0, at: Self.stamp(at))
        s.total += 1
        if right { s.right += 1 }
        s.at = Self.stamp(at)
        ears[era] = s
        replaceEars(ears)
    }

    /// "Your ear knows Hard Bop; Swing needs work." Once there are a few answers in two eras or more.
    func earSummary(library: JazzLibrary) -> String? {
        let scored = (data.ears ?? [:]).filter { $0.value.total >= 3 }.compactMap { id, s -> (Era, Double)? in
            library.era(id).map { ($0, Double(s.right) / Double(s.total)) }
        }
        guard scored.count >= 2, let best = scored.max(by: { $0.1 < $1.1 }), let worst = scored.min(by: { $0.1 < $1.1 }),
              best.0.id != worst.0.id else { return nil }
        return "Your ear knows \(best.0.name); \(worst.0.name) needs work."
    }

    /// The era your ear knows least, for a station to practise with.
    func weakestEar() -> String? {
        (data.ears ?? [:]).filter { $0.value.total >= 3 }
            .min { Double($0.value.right) / Double($0.value.total) < Double($1.value.right) / Double($1.value.total) }?.key
    }
}
