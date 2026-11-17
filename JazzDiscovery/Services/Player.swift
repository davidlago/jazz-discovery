import SwiftUI
import AVFoundation
import MusicKit
import Observation

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
        let text = String(describing: error)
        if text.localizedCaseInsensitiveContains("developerToken") || text.localizedCaseInsensitiveContains("token") {
            return "MusicKit isn't enabled for this app's bundle ID yet. Enable the MusicKit App Service for io.github.davidlago.JazzDiscovery in your Apple Developer account, then relaunch."
        }
        return error.localizedDescription
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
        case .appleMusic: ApplicationMusicPlayer.shared.playbackTime = t
        case .none: break
        }
        elapsed = t
    }

    func stop() {
        avPlayer.pause()
        avPlayer.replaceCurrentItem(with: nil)
        if mode == .appleMusic { ApplicationMusicPlayer.shared.stop() }
        mode = .none
        current = nil
        isPlaying = false
        currentTrackID = nil
        elapsed = 0; duration = 0
    }

    func openInMusic(_ url: URL?) {
        guard let url else { return }
        // music:// opens straight in the Music app instead of the browser.
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.scheme = "music"
        let items = comps?.queryItems?.filter { $0.name != "uo" }
        comps?.queryItems = (items?.isEmpty ?? true) ? nil : items
        NSWorkspace.shared.open(comps?.url ?? url)
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
            try await player.play()
            switchTo(.appleMusic)
            current = NowPlaying(title: start.title, artist: start.artistName,
                                 artwork: start.artwork?.url(width: 300, height: 300) ?? tracks[index].artwork(300),
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
            try await player.play()
            switchTo(.appleMusic)
            current = NowPlaying(title: item.title, artist: item.artistName,
                                 artwork: item.artwork?.url(width: 300, height: 300) ?? album.artwork(300),
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
        avPlayer.replaceCurrentItem(with: AVPlayerItem(url: url))
        avPlayer.play()
        isPlaying = true
        elapsed = 0
        duration = 30
        currentTrackID = t.trackId
        current = NowPlaying(title: t.name, artist: t.artistName, artwork: t.artwork(300),
                             appleMusicURL: t.url, isFullTrack: false)
    }

    private func previewEnded() {
        guard mode == .preview else { return }
        if previewIndex + 1 < previewQueue.count { startPreview(at: previewIndex + 1) }
        else { isPlaying = false; elapsed = duration }
    }

    private func switchTo(_ m: Mode) {
        if m != .preview { avPlayer.pause() }
        if m != .appleMusic, mode == .appleMusic { ApplicationMusicPlayer.shared.stop() }
        mode = m
        isPlaying = true
    }

    private func tick() {
        switch mode {
        case .preview:
            let t = avPlayer.currentTime().seconds
            if t.isFinite { elapsed = t }
            if let d = avPlayer.currentItem?.duration.seconds, d.isFinite, d > 0 { duration = d }
        case .appleMusic:
            let p = ApplicationMusicPlayer.shared
            elapsed = p.playbackTime
            isPlaying = p.state.playbackStatus == .playing
            if let entry = p.queue.currentEntry {
                if entry.title != current?.title {
                    current?.title = entry.title
                    current?.artist = entry.subtitle ?? current?.artist ?? ""
                    if let art = entry.artwork?.url(width: 300, height: 300) { current?.artwork = art }
                }
                if case .song(let s)? = entry.item, let d = s.duration { duration = d }
            }
        case .none: break
        }
    }
}
