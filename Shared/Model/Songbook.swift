import Foundation

/// A tune in the Songbook: its story, and the versions that made it matter.
struct Tune: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    /// Names, or artist IDs for composers with a page in the guide.
    let composers: [String]
    var lyricists: [String]? = nil
    let year: Int
    /// Popular song, Show tune, Film song, Blues, Jazz original or Latin standard.
    let origin: String
    let form: String
    let summary: String
    /// Another tune whose chords this one is built on.
    var builtOn: String? = nil
    /// Other titles it appears under in tracklists.
    var aliases: [String]? = nil
    /// Crate albums whose same-titled track is a different song.
    var notOn: [String]? = nil
    let versions: [TuneVersion]

    /// The span of its versions, by year.
    var span: ClosedRange<Int> { (versions.map(\.year).min() ?? year)...(versions.map(\.year).max() ?? year) }
    var sortedVersions: [TuneVersion] { versions.sorted { $0.year < $1.year } }
}

struct TuneVersion: Codable, Hashable {
    /// The artist's ID when they have a page.
    let artist: String?
    let artistName: String
    /// The title on the record, when it isn't the tune's ("Ko Ko" for Cherokee).
    var title: String? = nil
    let year: Int
    /// The Crate album it's on, if any.
    var album: String? = nil
    /// What to listen for.
    let note: String
    var landmark: Bool? = nil

    var isLandmark: Bool { landmark == true }
    /// The album it's on, as a hint for finding the right recording ("Selflessness").
    var record: String? = nil

    /// The key under which tracks.json resolves it: "artistName|title|year".
    func ref(in tune: Tune) -> String { "\(artistName)|\(title ?? tune.title)|\(year)" }
}

struct SongbookData: Codable {
    let tunes: [Tune]
}

extension Tune {
    /// Lowercased letters and digits, without accents, apostrophes, edition notes or a leading "The".
    static func key(_ title: String) -> String {
        var t = title
        if let i = t.firstIndex(where: { $0 == "(" || $0 == "[" }) { t = String(t[..<i]) }
        t = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).replacingOccurrences(of: "&", with: "and")
        if t.hasPrefix("the ") { t.removeFirst(4) }
        return t.filter { $0.isLetter || $0.isNumber }
    }

    /// Every title it goes by, as keys.
    var keys: Set<String> { Set(([title] + (aliases ?? [])).map(Tune.key)) }

    /// "Johnny Green, 1930 · Popular song · AABA, 32 bars", with composer names for IDs.
    func credit(names: (String) -> String) -> String {
        "\(Session.joinedList(composers.map(names))), \(String(year)) · \(origin) · \(form)"
    }
}

extension JazzLibrary {
    func tune(_ id: String) -> Tune? { tunes.first { $0.id == id } }

    /// The tune a track title is, when it's exactly one in the book (by title or alias), and not on an album it's
    /// marked as not being on.
    func tune(forTrackTitle title: String, onAlbum albumID: String? = nil) -> Tune? {
        guard let t = tunesByKey(Tune.key(title)) else { return nil }
        if let albumID, t.notOn?.contains(albumID) == true { return nil }
        return t
    }

    /// Tunes the artist wrote.
    func tunes(writtenBy artistID: String) -> [Tune] { tunes.filter { $0.composers.contains(artistID) } }

    /// Versions the artist plays, by tune.
    func versions(by artistID: String) -> [(tune: Tune, version: TuneVersion)] {
        tunes.flatMap { t in t.versions.filter { $0.artist == artistID }.map { (t, $0) } }
            .sorted { $0.version.year < $1.version.year }
    }

    /// Tunes built on this one's chords, the one it's built on, and others built on the same.
    func family(of tune: Tune) -> [Tune] {
        tunes.filter { other in
            other.id != tune.id && (other.builtOn == tune.id || tune.builtOn == other.id
                || (tune.builtOn != nil && other.builtOn == tune.builtOn))
        }
    }

    /// Versions on Crate records that aren't among the hand-picked ones.
    func alsoInCrate(_ tune: Tune) -> [(album: Album, track: CatalogTrack)] {
        let picked = Set(tune.versions.compactMap(\.album))
        let keys = tune.keys
        return albums.compactMap { album in
            guard !picked.contains(album.id), tune.notOn?.contains(album.id) != true,
                  let track = tracklists[album.id]?.first(where: { keys.contains(Tune.key($0.name)) }) else { return nil }
            return (album, track)
        }
    }

    /// A version's resolved track, if tracks.json has it.
    func track(for version: TuneVersion, of tune: Tune) -> StationTrack? { tracks[version.ref(in: tune)] }

    /// A composer's name: the artist's, for an ID.
    func composerName(_ s: String) -> String { artist(s)?.name ?? s }
}

extension Tune {
    /// The family of forms the tune belongs to, for "Same form" on its page: the blues in any length, or the 32-bar
    /// AABA song. Nil for the rest, which are too varied to group.
    var formFamily: String? {
        let f = form.lowercased()
        if f.contains("blues") { return "blues" }
        if f.hasPrefix("aaba, 32 bars") { return "aaba-32" }
        return nil
    }
}

extension JazzLibrary {
    /// Other tunes in the same form family, A–Z.
    func sameForm(as tune: Tune) -> [Tune] {
        guard let family = tune.formFamily else { return [] }
        return tunes.filter { $0.id != tune.id && $0.formFamily == family }
    }
}

extension Passport {
    /// How many of a tune's versions (the ones that resolve to a song) have been heard in full.
    func versionsHeard(of tune: Tune, library: JazzLibrary) -> (heard: Int, total: Int) {
        let ids = tune.versions.compactMap { library.track(for: $0, of: tune)?.id }
        let heard = ids.filter { data.songsHeard?[String($0)] != nil }.count
        return (heard, ids.count)
    }
}
