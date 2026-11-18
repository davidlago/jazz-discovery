import AppIntents
import CoreSpotlight
import Foundation

// Siri, Shortcuts and Spotlight: the app's App Intents and the things they work on. Playing from an intent is the
// person's own request (unlike a link from a web page), so intents may start music.

/// What the intents need from the running app. Set by each app as it starts; a page to open waits until a window is
/// there to show it.
@MainActor
final class AppContext {
    static let shared = AppContext()
    var library: JazzLibrary?
    var passport: Passport?
    var player: PlayerController?
    /// Opens a jazzdiscovery:// link in the app's window (set by the root view).
    var navigate: ((URL) -> Void)? { didSet { flush() } }
    private var pending: URL?

    func open(_ url: URL) {
        if let navigate { navigate(url) } else { pending = url }
    }

    private func flush() {
        if let url = pending, let navigate { pending = nil; navigate(url) }
    }

    /// The library, even when the app was started just for an intent and hasn't made one yet.
    var lib: JazzLibrary {
        if let library { return library }
        let l = JazzLibrary.load()
        library = l
        return l
    }
}

private func link(_ path: String) -> URL { URL(string: "\(DeepLink.scheme)://\(path)")! }

// MARK: - Entities

struct ArtistEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Artist"
    static let defaultQuery = ArtistQuery()
    let id: String
    let name: String
    let detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(detail)") }

    init(_ a: Artist) { id = a.id; name = a.name; detail = "\(a.instrument) · \(a.lifespan)" }
}

struct ArtistQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [ArtistEntity] {
        AppContext.shared.lib.artists(identifiers).map(ArtistEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [ArtistEntity] {
        AppContext.shared.lib.search(string).artists.map(ArtistEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [ArtistEntity] {
        AppContext.shared.lib.artists.prefix(30).map(ArtistEntity.init)
    }
}

struct AlbumEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Record"
    static let defaultQuery = AlbumQuery()
    let id: String
    let title: String
    let detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(detail)") }

    init(_ a: Album) { id = a.id; title = a.title; detail = "\(a.artistName) · \(String(a.year))" }
}

struct AlbumQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [AlbumEntity] {
        AppContext.shared.lib.albums(identifiers).map(AlbumEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [AlbumEntity] {
        AppContext.shared.lib.search(string).albums.map(AlbumEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [AlbumEntity] {
        AppContext.shared.lib.albums.filter(\.starter).map(AlbumEntity.init)
    }
}

struct TuneEntity: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Tune"
    static let defaultQuery = TuneQuery()
    let id: String
    let title: String
    let detail: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(detail)") }

    init(_ t: Tune) { id = t.id; title = t.title; detail = "The Songbook · \(t.composers.joined(separator: ", "))" }
}

struct TuneQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [TuneEntity] {
        identifiers.compactMap { AppContext.shared.lib.tune($0) }.map(TuneEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [TuneEntity] {
        let q = string.lowercased()
        return AppContext.shared.lib.tunes.filter { $0.title.lowercased().contains(q) }.map(TuneEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [TuneEntity] { AppContext.shared.lib.tunes.map(TuneEntity.init) }
}

struct StationEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Station"
    static let defaultQuery = StationQuery()
    let id: String
    let title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(_ s: Station) { id = s.id; title = s.title }
}

struct StationQuery: EntityStringQuery {
    @MainActor private var all: [Station] { Programmer.stations(library: AppContext.shared.lib, includeNewToYou: true) }
    @MainActor func entities(for identifiers: [String]) async throws -> [StationEntity] {
        all.filter { identifiers.contains($0.id) }.map(StationEntity.init)
    }
    @MainActor func entities(matching string: String) async throws -> [StationEntity] {
        let q = string.lowercased().replacingOccurrences(of: " radio", with: "")
        return all.filter { $0.title.lowercased().contains(q) }.map(StationEntity.init)
    }
    @MainActor func suggestedEntities() async throws -> [StationEntity] { all.map(StationEntity.init) }
}

// MARK: - Opening pages (Shortcuts, and Spotlight results)

struct OpenArtistIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Artist"
    @Parameter(title: "Artist") var target: ArtistEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppContext.shared.open(link("artist/\(target.id)"))
        return .result()
    }
}

struct OpenAlbumIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Record"
    @Parameter(title: "Record") var target: AlbumEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppContext.shared.open(link("album/\(target.id)"))
        return .result()
    }
}

struct OpenTuneIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Tune"
    @Parameter(title: "Tune") var target: TuneEntity
    @MainActor func perform() async throws -> some IntentResult {
        AppContext.shared.open(link("tune/\(target.id)"))
        return .result()
    }
}

// MARK: - Listening

struct PlayStationIntent: AudioPlaybackIntent {
    static let title: LocalizedStringResource = "Play a Station"
    static let description = IntentDescription("Plays one of Jazz Discovery's radio stations: an era, a decade, an instrument, The Long Way or the Songbook.")
    @Parameter(title: "Station") var station: StationEntity

    static var parameterSummary: some ParameterSummary { Summary("Play \(\.$station)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let ctx = AppContext.shared
        guard let s = Programmer.station(id: station.id, library: ctx.lib), let player = ctx.player, let passport = ctx.passport else {
            return .result(dialog: "Open Jazz Discovery once, then try again.")
        }
        StationStarter.play(s, library: ctx.lib, passport: passport, player: player)
        return .result(dialog: "Playing \(s.title).")
    }
}

struct TodayInJazzIntent: AppIntent {
    static let title: LocalizedStringResource = "Today in Jazz"
    static let description = IntentDescription("Says whose birthday it is in jazz, or what was recorded on this date.")

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let c = AppContext.shared.lib.todayWidget(on: Today.date) else {
            return .result(dialog: "Nothing in the guide happened on this day yet.")
        }
        return .result(dialog: "\(c.line)")
    }
}

struct ContinuePathIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue My Path"
    static let description = IntentDescription("Opens the path you're on at its next stop.")
    static let openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        let ctx = AppContext.shared
        if let passport = ctx.passport, let path = passport.currentPath(library: ctx.lib) {
            ctx.open(link("path/\(path.id)"))
        } else {
            ctx.open(link("paths"))
        }
        return .result()
    }
}

struct JazzShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayStationIntent(), phrases: [
            "Play \(\.$station) on \(.applicationName)",
            "Play \(\.$station) in \(.applicationName)",
            "Play jazz radio on \(.applicationName)",
        ], shortTitle: "Play a Station", systemImageName: "radio")
        AppShortcut(intent: TodayInJazzIntent(), phrases: [
            "What happened in jazz today in \(.applicationName)",
            "Today in jazz with \(.applicationName)",
        ], shortTitle: "Today in Jazz", systemImageName: "calendar")
        AppShortcut(intent: PlayNextStopIntent(), phrases: [
            "Play my next stop in \(.applicationName)",
        ], shortTitle: "Play Next Stop", systemImageName: "play.circle")
        AppShortcut(intent: ContinuePathIntent(), phrases: [
            "Continue my path in \(.applicationName)",
        ], shortTitle: "Continue My Path", systemImageName: "point.topleft.down.to.point.bottomright.curvepath")
    }
}

// MARK: - Spotlight

/// Puts every artist, record and tune in Spotlight, once per version of the data, so searching "Kind of Blue" in the
/// system finds the app's page.
enum SpotlightIndex {
    @MainActor
    static func update(library: JazzLibrary) {
        let version = "v1-\(library.artists.count)-\(library.albums.count)-\(library.tunes.count)"
        let key = "spotlightIndexed"
        guard UserDefaults.standard.string(forKey: key) != version else { return }
        let artists = library.artists.map(ArtistEntity.init)
        let albums = library.albums.map(AlbumEntity.init)
        let tunes = library.tunes.map(TuneEntity.init)
        Task.detached(priority: .utility) {
            do {
                let index = CSSearchableIndex.default()
                try await index.indexAppEntities(artists)
                try await index.indexAppEntities(albums)
                try await index.indexAppEntities(tunes)
                await MainActor.run { UserDefaults.standard.set(version, forKey: key) }
            } catch {
                // Try again next launch.
            }
        }
        JazzShortcuts.updateAppShortcutParameters()
    }
}

// MARK: - Playing a path

/// Plays path stops and knows what comes next, for the player's Next Stop and the intents.
@MainActor
enum PathPlayback {
    enum Outcome { case playing(String), notPlayable(String), noPath }

    /// Plays a stop if it has a track; false when it's a stop to read or look at.
    @discardableResult
    static func play(_ index: Int, of path: JourneyPath, library: JazzLibrary, player: PlayerController) -> Bool {
        guard path.stops.indices.contains(index), let t = library.playable(path.stops[index]) else { return false }
        player.play(t.track, pathStop: .init(pathID: path.id, index: index))
        return true
    }

    /// The path you're on, and its first stop not yet done.
    static func next(library: JazzLibrary, passport: Passport) -> (path: JourneyPath, index: Int)? {
        guard let path = passport.currentPath(library: library), let i = passport.progress(on: path, library: library).next
        else { return nil }
        return (path, i)
    }

    static func playNext(library: JazzLibrary, passport: Passport, player: PlayerController) -> Outcome {
        guard let (path, i) = next(library: library, passport: passport) else { return .noPath }
        let title = library.title(of: path.stops[i]).title
        return play(i, of: path, library: library, player: player) ? .playing(title) : .notPlayable(title)
    }

    /// The stop to go to after the one playing: the next one not yet done (or simply the next, when all are).
    static func after(_ ref: PlayerController.PathStopRef, library: JazzLibrary, passport: Passport) -> (path: JourneyPath, index: Int)? {
        guard let path = library.journey(ref.pathID), path.stops.indices.contains(ref.index + 1) else { return nil }
        let later = (ref.index + 1)..<path.stops.count
        let i = later.first { !passport.isDone(path.stops[$0], on: path, library: library) } ?? ref.index + 1
        return (path, i)
    }
}
