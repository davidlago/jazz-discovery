import SwiftUI
import AVFoundation
import MusicKit
import Observation
#if os(iOS)
import MediaPlayer
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
    /// Scrobbles full tracks to Last.fm. Previews aren't scrobbled.
    let scrobbler = Scrobbler()

    var preferFullTracks: Bool = UserDefaults.standard.object(forKey: "preferFullTracks") as? Bool ?? true {
        didSet { UserDefaults.standard.set(preferFullTracks, forKey: "preferFullTracks") }
    }
    var usingAppleMusic: Bool { mode == .appleMusic }

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

    func playAlbum(_ album: CatalogAlbum, tracks: [CatalogTrack]) {
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
        mode = .none
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
        elapsed = 0
        duration = 30
        currentTrackID = t.trackId
        current = NowPlaying(title: t.name, artist: t.artistName, artwork: t.artwork(600),
                             appleMusicURL: t.url, isFullTrack: false)
        #if os(iOS)
        updateNowPlayingInfo()
        #endif
    }

    private func previewEnded() {
        guard mode == .preview else { return }
        if previewIndex + 1 < previewQueue.count { startPreview(at: previewIndex + 1) }
        else {
            isPlaying = false; elapsed = duration
            #if os(iOS)
            updateNowPlayingInfo()
            #endif
        }
    }

    private func switchTo(_ m: Mode) {
        if m != .preview { avPlayer.pause() }
        if m != .appleMusic, mode == .appleMusic { ApplicationMusicPlayer.shared.stop(); endScrobbleTracking() }
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
                sameEntry = entry.id == scrobbleEntryID
                trackForScrobbling(entry)
            }
            // Count how far the song moved on, but never more than the time that passed: a seek isn't listening, and
            // a long gap between ticks (the app was held up) still counts what played meanwhile.
            let moved = sameEntry ? elapsed - (lastPlaybackTime ?? elapsed) : 0
            lastPlaybackTime = elapsed
            if isPlaying || moved > 0 { scrobbler.played(max(0, min(moved, realGap + 0.5))) }
        case .none: break
        }
    }

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
        if let album = previewQueue.indices.contains(previewIndex) ? previewQueue[previewIndex].albumName : nil {
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
