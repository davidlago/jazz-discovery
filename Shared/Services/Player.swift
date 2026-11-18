import SwiftUI
import AVFoundation
import MusicKit
import Observation
#if os(iOS)
import MediaPlayer
#else
import AppKit
#endif

struct NowPlaying: Equatable {
    var title: String
    var artist: String
    var artwork: URL?
    var appleMusicURL: URL?
    var isFullTrack: Bool
}

/// Plays music two ways:
/// - Full tracks through MusicKit's ApplicationMusicPlayer when the user has authorized
///   Apple Music and the app's bundle ID has the MusicKit service enabled.
/// - Otherwise, 30-second previews from the iTunes catalog, with one click to open the
///   full track or album in the Music app.
@MainActor
@Observable
final class PlayerController {
    enum AppleMusicState: Equatable {
        case unknown, checking, ready, denied, noSubscription, unavailable(String)
        var isReady: Bool { self == .ready }
    }

    private(set) var current: NowPlaying?
    private(set) var isPlaying = false
    private(set) var elapsed: Double = 0
    private(set) var duration: Double = 0
    private(set) var loadingKey: String?
    private(set) var currentTrackID: Int?
    private(set) var appleMusic: AppleMusicState = .unknown
    var lastError: String?
    /// What's playing now: Apple Music's variant (on the Mac always AAC, see `StreamQuality`) or a preview.
    private(set) var quality: StreamQuality?
    /// The best the current song has on Apple Music: Lossless, Hi-Res Lossless or neither.
    private(set) var songBest: StreamQuality?
    /// A better quality than what's playing that the song has on Apple Music (the Audio Quality setting on iPhone, the
    /// Music app on the Mac). Not offered over Dolby Atmos, which is picked on purpose.
    var betterAvailable: StreamQuality? {
        guard let q = quality, let best = songBest, q != .dolbyAtmos, q != .hiResLossless, q != best else { return nil }
        return best
    }
    /// Where the sound goes, and at what rate.
    private(set) var output: AudioOutputInfo?
    /// Scrobbles full tracks to Last.fm. Previews aren't scrobbled.
    let scrobbler = Scrobbler()
    /// Told when a preview starts and when a full track has been listened to (the passport marks records with it).
    @ObservationIgnored var onListen: (@MainActor (ListenEvent) -> Void)?
    @ObservationIgnored private var meter = ListenMeter()
    /// The Apple Music album a queue was started from, or the album of each song in it.
    @ObservationIgnored private var queueCollectionId: Int?
    @ObservationIgnored private var songCollections: [String: Int] = [:]
    /// The station playing, if any, and its tracks by song ID (for "why this track").
    private(set) var station: Station?
    @ObservationIgnored private var stationTracks: [Int: StationTrack] = [:]
    /// More of the station, for when a preview queue runs low.
    @ObservationIgnored private var stationRefill: (() -> [StationTrack])?
    /// A Blindfold Test clip is playing: nothing that would give it away is shown or published.
    private(set) var isBlind = false
    @ObservationIgnored private var refreshedPreviews: Set<Int> = []
    /// The Apple Music album that just played to its end (for the three doors), until something else plays.
    private(set) var finishedCollectionId: Int?
    /// The last track of an album queue is about to end.
    @ObservationIgnored private var nearEndOfAlbum = false

    var preferFullTracks: Bool = UserDefaults.standard.object(forKey: "preferFullTracks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(preferFullTracks, forKey: "preferFullTracks") }
    }
    var usingAppleMusic: Bool { mode == .appleMusic }

    #if os(macOS)
    /// Switch the output device to the stream's 44.1 kHz while playing (and back afterwards), like Audio MIDI Setup.
    var matchOutputRate: Bool = UserDefaults.standard.object(forKey: "matchOutputRate") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(matchOutputRate, forKey: "matchOutputRate")
            if matchOutputRate { if mode != .none { Task { await matchOutput() } } } else { restoreOutput() }
        }
    }
    @ObservationIgnored private let rateMatcher = OutputRateMatcher()
    /// The output device the rate was last matched on; another one (a DAC plugged in) gets matched too.
    @ObservationIgnored private var matchedOutputUID: String?
    @ObservationIgnored private var terminateObserver: Any?
    #endif

    private enum Mode { case none, preview, appleMusic }
    private var mode: Mode = .none
    private var previewQueue: [CatalogTrack] = []
    private var previewIndex = 0
    private let avPlayer = AVPlayer()
    private var endObserver: Any?
    private var ticker: Task<Void, Never>?
    private var lastTick = ContinuousClock.now
    private var scrobbleEntryID: String?
    private var queueAlbumTitle: String?
    /// MusicKit's playback position at the last tick, to count listening even when ticks were held up (the iPhone
    /// running in the background, the Mac asleep).
    private var lastPlaybackTime: Double?
    /// The queue entry whose Apple Music variants were last looked up.
    private var variantsEntryID: String?

    init() {
        avPlayer.volume = 1
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.previewEnded() }
            }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                self?.tick()
            }
        }
        let status = MusicAuthorization.currentStatus
        if status == .authorized { Task { await self.checkAppleMusic(requesting: false) } }
        else if status == .denied || status == .restricted { appleMusic = .denied }
        #if os(iOS)
        setUpSystemControls()
        #else
        let matcher = rateMatcher
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in matcher.restoreNow() }
        #endif
    }

    // MARK: Apple Music (MusicKit)

    func connectAppleMusic() async { await checkAppleMusic(requesting: true) }

    private func checkAppleMusic(requesting: Bool) async {
        appleMusic = .checking
        var status = MusicAuthorization.currentStatus
        if status == .notDetermined && requesting { status = await MusicAuthorization.request() }
        guard status == .authorized else { appleMusic = status == .notDetermined ? .unknown : .denied; return }
        do {
            let sub = try await MusicSubscription.current
            guard sub.canPlayCatalogContent else { appleMusic = .noSubscription; return }
            // A catalog request proves the developer and user tokens work. Right after the app is first signed or
            // MusicKit is enabled, Apple answers 401 for a little while (MusicKit reports it as a decoding error),
            // so retry a few times before giving up.
            let probe = MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID("268443092"))
            var attempt = 0
            while true {
                do { _ = try await probe.response(); break }
                catch where error is DecodingError && attempt < 4 {
                    attempt += 1
                    try? await Task.sleep(for: .seconds(2 * attempt))
                }
            }
            appleMusic = .ready
        } catch {
            print("Apple Music check failed: \(String(reflecting: error))")
            appleMusic = .unavailable(await Self.diagnose(error))
        }
    }

    /// MusicKit surfaces an HTTP 401 (empty body) as a JSON decoding error; ask the API directly
    /// so the message names the real problem.
    private static func diagnose(_ error: Error) async -> String {
        if !(error is DecodingError) { return describe(error) }
        let url = URL(string: "https://api.music.apple.com/v1/catalog/us/albums/268443092")!
        guard let resp = try? await MusicDataRequest(urlRequest: URLRequest(url: url)).response() else { return describe(error) }
        switch resp.urlResponse.statusCode {
        case 401, 403:
            return "Apple Music rejected this app's MusicKit token (HTTP \(resp.urlResponse.statusCode)). The MusicKit service for io.github.davidlago.JazzDiscovery may still be activating (it can take a while after you enable it), or the app needs to be signed with a provisioning profile."
        case 200..<300:
            return "Apple Music is reachable, but MusicKit couldn't finish the request. This is usually temporary right after MusicKit is enabled. Click Re-check in a minute."
        default:
            return "Apple Music returned HTTP \(resp.urlResponse.statusCode) for a catalog request."
        }
    }

    private static func describe(_ error: Error) -> String {
        if let tokenError = error as? MusicTokenRequestError {
            switch tokenError {
            case .developerTokenRequestFailed:
                return "Apple wouldn't issue this app a MusicKit token. MusicKit must be enabled for io.github.davidlago.JazzDiscovery, and the app signed with a provisioning profile for that App ID."
            case .userNotSignedIn:
                return "Sign in to Apple Music on this device (the Music app, or Settings ▸ Apps ▸ Music), then try again."
            case .privacyAcknowledgementRequired:
                return "Open the Music app once and accept Apple Music's privacy notice, then try again."
            case .permissionDenied:
                return "Apple Music access is turned off for Jazz Discovery (Settings ▸ Apps ▸ Jazz Discovery)."
            case .userTokenRevoked, .userTokenRequestFailed:
                return "Apple Music couldn't confirm your account (\(String(describing: tokenError))). Open the Music app, check you're signed in, then try again."
            default:
                return "Apple Music token error: \(String(describing: tokenError))."
            }
        }
        return "\(error.localizedDescription) (\(String(describing: error)))"
    }

    private var shouldUseAppleMusic: Bool { preferFullTracks && appleMusic.isReady }

    // MARK: Public playback API

    func play(_ tracks: [CatalogTrack], startAt index: Int = 0, key: String? = nil) {
        guard tracks.indices.contains(index) else { return }
        finishedCollectionId = nil; nearEndOfAlbum = false
        if !startingStation { station = nil; stationTracks = [:]; stationRefill = nil }
        isBlind = false
        let k = key ?? "track-\(tracks[index].trackId)"
        loadingKey = k
        currentTrackID = tracks[index].trackId
        Task {
            defer { if loadingKey == k { loadingKey = nil } }
            if shouldUseAppleMusic, await playWithMusicKit(songs: tracks, startAt: index) { return }
            playPreviews(tracks, startAt: index)
        }
    }

    func play(_ track: CatalogTrack) { play([track], startAt: 0) }

    @ObservationIgnored private var startingStation = false

    /// Plays a station: its first tracks now, and more from `refill` when a preview queue runs low (an Apple Music
    /// queue gets a hundred tracks, hours of music).
    func playStation(_ station: Station, tracks: [StationTrack], refill: @escaping () -> [StationTrack]) {
        guard !tracks.isEmpty else { return }
        self.station = station
        stationTracks = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        stationRefill = refill
        startingStation = true
        play(tracks.map(\.track), startAt: 0, key: "station-\(station.id)")
        startingStation = false
    }

    /// The station track playing now, for its reason.
    var currentStationTrack: StationTrack? { currentTrackID.flatMap { stationTracks[$0] } }

    /// Plays a Blindfold Test clip: always the 30-second preview, shown and published as a mystery.
    func playBlind(_ track: CatalogTrack) {
        guard track.preview != nil else { return }
        finishedCollectionId = nil
        station = nil; stationTracks = [:]; stationRefill = nil
        isBlind = true
        previewQueue = [track]
        switchTo(.preview)
        startPreview(at: 0)
    }

    func playAlbum(_ album: CatalogAlbum, tracks: [CatalogTrack]) {
        finishedCollectionId = nil; nearEndOfAlbum = false
        station = nil; stationTracks = [:]; stationRefill = nil; isBlind = false
        let k = "album-\(album.collectionId)"
        loadingKey = k
        Task {
            defer { if loadingKey == k { loadingKey = nil } }
            if shouldUseAppleMusic, await playAlbumWithMusicKit(album) { return }
            var t = tracks
            if t.isEmpty { t = await ITunes.shared.tracks(collectionId: album.collectionId) }
            guard !t.isEmpty else { openInMusic(album.url); return }
            currentTrackID = t.first?.trackId
            playPreviews(t, startAt: 0)
        }
    }

    func togglePlayPause() {
        switch mode {
        case .preview:
            if isPlaying { avPlayer.pause() } else { avPlayer.play() }
            isPlaying.toggle()
            #if os(iOS)
            updateNowPlayingInfo()
            #endif
        case .appleMusic:
            let p = ApplicationMusicPlayer.shared
            if p.state.playbackStatus == .playing { p.pause(); isPlaying = false }
            else { Task { try? await p.play(); isPlaying = true } }
        case .none: break
        }
    }

    func next() {
        switch mode {
        case .preview:
            guard previewIndex + 1 < previewQueue.count else { return }
            startPreview(at: previewIndex + 1)
        case .appleMusic: Task { try? await ApplicationMusicPlayer.shared.skipToNextEntry() }
        case .none: break
        }
    }

    func previous() {
        switch mode {
        case .preview:
            if elapsed > 3 || previewIndex == 0 { avPlayer.seek(to: .zero) } else { startPreview(at: previewIndex - 1) }
        case .appleMusic: Task { try? await ApplicationMusicPlayer.shared.skipToPreviousEntry() }
        case .none: break
        }
    }

    func seek(to fraction: Double) {
        let t = max(0, min(1, fraction)) * duration
        switch mode {
        case .preview: avPlayer.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        case .appleMusic: ApplicationMusicPlayer.shared.playbackTime = t; lastPlaybackTime = t
        case .none: break
        }
        elapsed = t
        #if os(iOS)
        updateNowPlayingInfo()
        #endif
    }

    func stop() {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        if mode == .appleMusic { ApplicationMusicPlayer.shared.stop() }
        endScrobbleTracking()
        station = nil; stationTracks = [:]; stationRefill = nil; isBlind = false
        mode = .none
        quality = nil; songBest = nil; variantsEntryID = nil
        #if os(macOS)
        restoreOutput()
        #endif
        current = nil
        isPlaying = false
        currentTrackID = nil
        elapsed = 0; duration = 0
        #if os(iOS)
        updateNowPlayingInfo()
        #endif
    }

    /// What's queued after the current preview (MusicKit keeps its own queue).
    var upNext: [CatalogTrack] {
        guard mode == .preview, previewIndex + 1 < previewQueue.count else { return [] }
        return Array(previewQueue[(previewIndex + 1)...])
    }

    func playUpNext(_ track: CatalogTrack) {
        guard mode == .preview, let i = previewQueue.firstIndex(of: track) else { return }
        startPreview(at: i)
    }

    func openInMusic(_ url: URL?) {
        guard let url else { return }
        // music:// opens straight in the Music app instead of the browser.
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "music"
        let items = comps?.queryItems?.filter { $0.name != "uo" }
        comps?.queryItems = (items?.isEmpty ?? true) ? nil : items
        Platform.open(comps?.url ?? url)
    }

    /// Searches the Music app, for tracks the catalog lookup couldn't match.
    func searchInMusic(_ term: String) {
        let q = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "music://music.apple.com/us/search?term=\(q)") { Platform.open(url) }
    }

    func isCurrent(_ trackID: Int) -> Bool { currentTrackID == trackID && current != nil }

    // MARK: MusicKit

    private func playWithMusicKit(songs tracks: [CatalogTrack], startAt index: Int) async -> Bool {
        do {
            let ids = tracks.map { MusicItemID(String($0.trackId)) }
            let req = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: ids)
            let resp = try await req.response()
            let byID = Dictionary(resp.items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let songs = ids.compactMap { byID[$0] }
            guard let start = byID[ids[index]] ?? songs.first else { return false }
            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: songs, startingAt: start)
            queueAlbumTitle = nil
            queueCollectionId = nil
            songCollections = Dictionary(tracks.compactMap { t in t.collectionId.map { (String(t.trackId), $0) } },
                                         uniquingKeysWith: { a, _ in a })
            #if os(macOS)
            await matchOutput()
            #endif
            try await player.play()
            switchTo(.appleMusic)
            current = NowPlaying(title: start.title, artist: start.artistName,
                                 artwork: start.artwork?.url(width: 600, height: 600) ?? tracks[index].artwork(600),
                                 appleMusicURL: start.url ?? tracks[index].url, isFullTrack: true)
            duration = start.duration ?? 0
            return true
        } catch {
            lastError = "Apple Music: \(error.localizedDescription). Playing a preview instead."
            return false
        }
    }

    private func playAlbumWithMusicKit(_ album: CatalogAlbum) async -> Bool {
        do {
            let req = MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID(String(album.collectionId)))
            guard let item = try await req.response().items.first else { return false }
            let player = ApplicationMusicPlayer.shared
            player.queue = [item]
            queueAlbumTitle = item.title
            queueCollectionId = album.collectionId
            songCollections = [:]
            #if os(macOS)
            await matchOutput()
            #endif
            try await player.play()
            switchTo(.appleMusic)
            current = NowPlaying(title: item.title, artist: item.artistName,
                                 artwork: item.artwork?.url(width: 600, height: 600) ?? album.artwork(600),
                                 appleMusicURL: item.url ?? album.url, isFullTrack: true)
            return true
        } catch {
            lastError = "Apple Music: \(error.localizedDescription). Playing previews instead."
            return false
        }
    }

    // MARK: Previews

    private func playPreviews(_ tracks: [CatalogTrack], startAt index: Int) {
        let playable = tracks.enumerated().filter { $0.element.preview != nil }
        guard !playable.isEmpty else {
            lastError = "No preview available — opening in Music."
            openInMusic(tracks[index].url)
            return
        }
        previewQueue = playable.map(\.element)
        let startID = tracks[index].trackId
        switchTo(.preview)
        startPreview(at: previewQueue.firstIndex { $0.trackId == startID } ?? 0)
    }

    private func startPreview(at i: Int) {
        previewIndex = i
        let t = previewQueue[i]
        guard let url = t.preview else { return }
        #if os(iOS)
        activateAudioSession()
        #endif
        avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        avPlayer.play()
        isPlaying = true
        quality = .preview; songBest = nil
        #if os(macOS)
        Task { await matchOutput() }
        #endif
        elapsed = 0
        duration = 30
        currentTrackID = t.trackId
        if isBlind {
            current = NowPlaying(title: "Blindfold Test", artist: "Who's playing?", artwork: nil, appleMusicURL: nil,
                                 isFullTrack: false)
        } else {
            current = NowPlaying(title: t.name, artist: t.artistName, artwork: t.artwork(600),
                                 appleMusicURL: t.url, isFullTrack: false)
            onListen?(ListenEvent(songID: String(t.trackId), collectionId: t.collectionId, full: false))
        }
        #if os(iOS)
        updateNowPlayingInfo()
        #endif
    }

    private func previewEnded() {
        guard mode == .preview else { return }
        if previewIndex + 1 >= previewQueue.count, station != nil, let more = stationRefill?(), !more.isEmpty {
            for t in more { stationTracks[t.id] = t }
            previewQueue += more.map(\.track).filter { $0.preview != nil }
        }
        if previewIndex + 1 < previewQueue.count { startPreview(at: previewIndex + 1) }
        else {
            isPlaying = false; elapsed = duration
            // A whole album's previews, played to the end.
            let albums = Set(previewQueue.map(\.collectionId))
            if previewQueue.count > 1, albums.count == 1, let c = albums.first { finishedCollectionId = c }
            #if os(iOS)
            updateNowPlayingInfo()
            #endif
        }
    }

    private func switchTo(_ m: Mode) {
        if m != .preview { avPlayer.pause() }
        if m != .appleMusic, mode == .appleMusic { ApplicationMusicPlayer.shared.stop(); endScrobbleTracking() }
        if m != mode { quality = nil; songBest = nil; variantsEntryID = nil }
        #if os(iOS)
        // MusicKit plays through the system's player, which picks the output rate (a USB DAC's included) for the
        // song's variant. Let go of the session the previews used, so it doesn't hold the hardware at its rate.
        if m == .appleMusic { try? AVAudioSession.sharedInstance().setActive(false) }
        #endif
        mode = m
        isPlaying = true
    }

    private func tick() {
        // Real listening time since the last tick, for scrobbling.
        let now = ContinuousClock.now, gap = (now - lastTick).components
        let realGap = Double(gap.seconds) + Double(gap.attoseconds) / 1e18
        lastTick = now
        switch mode {
        case .preview:
            let t = avPlayer.currentTime().seconds
            if t.isFinite { elapsed = t }
            if avPlayer.currentItem?.status == .failed { refreshPreview() }
            if let d = avPlayer.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        case .appleMusic:
            let p = ApplicationMusicPlayer.shared
            elapsed = p.playbackTime
            isPlaying = p.state.playbackStatus == .playing
            var sameEntry = false
            if let entry = p.queue.currentEntry {
                if entry.title != current?.title {
                    current?.title = entry.title
                    current?.artist = entry.subtitle ?? current?.artist ?? ""
                    if let art = entry.artwork?.url(width: 600, height: 600) { current?.artwork = art }
                }
                if case .song(let s)? = entry.item, let d = s.duration { duration = d }
                if case .song(let s)? = entry.item, let id = Int(s.id.rawValue), currentTrackID != id { currentTrackID = id }
                sameEntry = entry.id == scrobbleEntryID
                trackForScrobbling(entry)
                lookUpVariants(entry)
            }
            #if os(iOS)
            // Nil until the stream starts.
            quality = p.state.audioVariant.map(StreamQuality.init)
            #else
            // MusicKit on the Mac reports no variant; Apple gives it the AAC stream.
            quality = p.state.audioVariant.map(StreamQuality.init) ?? .aac
            #endif
            // Count how far the song moved on, but never more than the time that passed: a seek isn't listening, and
            // a long gap between ticks (the app was held up) still counts what played meanwhile.
            let moved = sameEntry ? elapsed - (lastPlaybackTime ?? elapsed) : 0
            lastPlaybackTime = elapsed
            let listened = max(0, min(moved, realGap + 0.5))
            if isPlaying || moved > 0 { scrobbler.played(listened) }
            measureListening(p.queue.currentEntry, listened: listened)
            noticeAlbumEnd(p)
        case .none: break
        }
        if mode != .none { refreshOutput() }
    }

    /// A stored preview link that no longer works: look the song up again once, and play the fresh link.
    private func refreshPreview() {
        guard previewQueue.indices.contains(previewIndex) else { return }
        let t = previewQueue[previewIndex]
        guard refreshedPreviews.insert(t.trackId).inserted else { return }
        let index = previewIndex
        Task {
            guard let fresh = await ITunes.shared.refresh(trackId: t.trackId), fresh.preview != nil, fresh.preview != t.preview,
                  mode == .preview, previewIndex == index, previewQueue.indices.contains(index) else { return }
            previewQueue[index] = fresh
            startPreview(at: index)
        }
    }

    // MARK: Listening (for the passport)

    /// Counts the current song's real listening time, and reports it once it passes the threshold.
    private func measureListening(_ entry: ApplicationMusicPlayer.Queue.Entry?, listened: Double) {
        guard let entry, case .song(let song)? = entry.item else { meter.track(nil, duration: nil); return }
        meter.track(entry.id, duration: song.duration)
        guard meter.add(listened) else { return }
        let id = song.id.rawValue
        onListen?(ListenEvent(songID: id, collectionId: queueCollectionId ?? songCollections[id], full: true))
    }

    /// An album queue that reached the end of its last track: MusicKit stops (or pauses) there.
    private func noticeAlbumEnd(_ p: ApplicationMusicPlayer) {
        guard let album = queueCollectionId else { nearEndOfAlbum = false; return }
        if let entry = p.queue.currentEntry, entry.id == p.queue.entries.last?.id, duration > 0 {
            if isPlaying { nearEndOfAlbum = duration - elapsed < 3 }
        }
        if nearEndOfAlbum && !isPlaying {
            nearEndOfAlbum = false
            finishedCollectionId = album
        }
    }

    // MARK: Audio quality and output

    /// Looks up which variants the entry's song has on Apple Music, once per entry.
    private func lookUpVariants(_ entry: ApplicationMusicPlayer.Queue.Entry) {
        guard entry.id != variantsEntryID else { return }
        variantsEntryID = entry.id
        songBest = nil
        guard case .song(let song)? = entry.item else { return }
        Task {
            var variants = song.audioVariants
            if variants == nil { variants = try? await song.with([.audioVariants]).audioVariants }
            guard variantsEntryID == entry.id else { return }
            songBest = StreamQuality.best(of: variants ?? [])
        }
    }

    private func refreshOutput() {
        #if os(iOS)
        let now = AudioOutputInfo.current()
        #else
        let now = OutputRateMatcher.current()
        if isPlaying, OutputRateMatcher.defaultOutputUID() != matchedOutputUID { Task { await matchOutput() } }
        #endif
        if now != output { output = now }
    }

    #if os(macOS)
    /// Switches the default output to the stream's rate, before playing and when the default output changes. Apple
    /// Music (as the Mac's MusicKit gets it) and previews are both AAC at 44.1 kHz.
    private func matchOutput() async {
        guard matchOutputRate, quality?.isLossless != true,
              let uid = OutputRateMatcher.defaultOutputUID(), uid != matchedOutputUID else { return }
        matchedOutputUID = uid
        await rateMatcher.match(rate: 44_100)
        refreshOutput()
    }

    private func restoreOutput() {
        matchedOutputUID = nil
        rateMatcher.restore()
    }
    #endif

    // MARK: Last.fm

    private func trackForScrobbling(_ entry: ApplicationMusicPlayer.Queue.Entry) {
        var song: Song?
        if case .song(let s)? = entry.item { song = s }
        if entry.id == scrobbleEntryID {
            scrobbler.refineCurrent(album: song?.albumTitle ?? queueAlbumTitle, duration: song?.duration)
            return
        }
        scrobbleEntryID = entry.id
        let artist = song?.artistName ?? entry.subtitle ?? current?.artist ?? ""
        let title = song?.title ?? entry.title
        guard !artist.isEmpty, !title.isEmpty else { scrobbler.trackStopped(); return }
        scrobbler.trackStarted(ScrobbleTrack(artist: artist, title: title, album: song?.albumTitle ?? queueAlbumTitle,
                                             duration: song?.duration, startedAt: .now))
    }

    private func endScrobbleTracking() {
        scrobbleEntryID = nil
        lastPlaybackTime = nil
        scrobbler.trackStopped()
    }

    // MARK: Lock screen and Control Center (iPhone)

    #if os(iOS)
    /// Previews play through the app's own AVPlayer, so the app publishes them to the lock screen itself. MusicKit's
    /// player does that for full tracks.
    private func setUpSystemControls() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            guard let self, !self.isPlaying, self.current != nil else { return .commandFailed }
            self.togglePlayPause(); return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.togglePlayPause(); return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.current != nil else { return .commandFailed }
            self.togglePlayPause(); return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in self?.previous(); return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let e = event as? MPChangePlaybackPositionCommandEvent, self.duration > 0 else { return .commandFailed }
            self.seek(to: e.positionTime / self.duration); return .success
        }
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    private func updateNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        guard mode == .preview, let np = current else {
            if mode != .appleMusic { center.nowPlayingInfo = nil }
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: np.title,
            MPMediaItemPropertyArtist: np.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if !isBlind, let album = previewQueue.indices.contains(previewIndex) ? previewQueue[previewIndex].albumName : nil {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        center.nowPlayingInfo = info
        guard let art = np.artwork else { return }
        Task {
            guard let img = await ImageStore.shared.load(art), current?.artwork == art else { return }
            var withArt = center.nowPlayingInfo ?? info
            withArt[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            center.nowPlayingInfo = withArt
        }
    }
    #endif
}
