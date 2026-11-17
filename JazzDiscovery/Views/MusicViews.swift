import SwiftUI

/// A list of catalog tracks with play buttons (full track via Apple Music, or preview).
struct TrackList: View {
    let tracks: [CatalogTrack]
    var tint: Color = Theme.brass
    var showArtist = false
    var highlight: [String] = []
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, number: t.trackNumber ?? (i + 1), tint: tint, showArtist: showArtist,
                         highlighted: highlight.contains { t.name.localizedCaseInsensitiveContains($0) }) {
                    player.play(tracks, startAt: i)
                }
                if i < tracks.count - 1 { Divider().overlay(Theme.panelHi) }
            }
        }
    }
}

struct TrackRow: View {
    let track: CatalogTrack
    let number: Int
    var tint: Color
    var showArtist = false
    var highlighted = false
    var action: () -> Void
    @Environment(PlayerController.self) private var player
    @State private var hovering = false

    var body: some View {
        let isCurrent = player.isCurrent(track.trackId)
        HStack(spacing: 14) {
            ZStack {
                if player.loadingKey == "track-\(track.trackId)" {
                    ProgressView().controlSize(.small)
                } else if isCurrent && player.isPlaying {
                    Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: true).foregroundStyle(tint)
                } else if hovering {
                    Image(systemName: "play.fill").foregroundStyle(tint)
                } else {
                    Text("\(number)").font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.faint)
                }
            }
            .frame(width: 24)
            if showArtist {
                RemoteImage(url: track.artwork(100)) { Theme.panelHi }
                    .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 3))
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(track.name).font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                        .foregroundStyle(isCurrent ? tint : Theme.cream).lineLimit(1)
                    if highlighted { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(tint) }
                }
                if showArtist {
                    Text([track.artistName, track.albumName].compactMap { $0 }.joined(separator: " — "))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            Spacer()
            if hovering, let url = track.url {
                Button { player.openInMusic(url) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).help("Open in Music")
            }
            Text(track.duration).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.faint)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.panelHi : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 1, perform: action)
    }
}

/// Resolves a curated "essential track" to the Apple Music catalog lazily.
struct EssentialTrackRow: View {
    let ref: TrackRef
    let tint: Color
    let index: Int
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var track: CatalogTrack?
    @State private var resolved = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RemoteImage(url: track?.artwork(120)) { tint.opacity(0.2) }
                    .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 4))
                if hovering || (track.map { player.isCurrent($0.trackId) } ?? false) {
                    Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 4))
                    if let track, player.loadingKey == "track-\(track.trackId)" { ProgressView().controlSize(.small) }
                    else {
                        Image(systemName: (track.map { player.isCurrent($0.trackId) && player.isPlaying } ?? false) ? "waveform" : "play.fill")
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                HStack(spacing: 4) {
                    if let a = library.artist(named: ref.artist) {
                        Button(ref.artist) { router.go(.artist(a.id)) }.buttonStyle(.plain)
                            .foregroundStyle(tint)
                    } else {
                        Text(ref.artist).foregroundStyle(Theme.muted)
                    }
                    if let y = ref.year { Text("· \(String(y))").foregroundStyle(Theme.faint) }
                }
                .font(.system(size: 12))
            }
            Spacer()
            if resolved && track == nil {
                Button { openSearch() } label: { Label("Search Music", systemImage: "magnifyingglass") }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else if let track {
                Text(track.duration).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.faint)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.panelHi : Theme.panel))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if let track { player.play(track) } else { openSearch() } }
        .task(id: ref.id) {
            try? await Task.sleep(for: .milliseconds(120 * index)) // stagger catalog lookups
            track = await ITunes.shared.track(ref.title, artist: ref.artist)
            resolved = true
        }
    }

    private func openSearch() {
        let term = "\(ref.artist) \(ref.title)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "music://music.apple.com/us/search?term=\(term)") { NSWorkspace.shared.open(url) }
    }
}

/// Primary "Play album" control + "Open in Music".
struct AlbumPlayControls: View {
    let catalog: CatalogAlbum?
    let tracks: [CatalogTrack]
    let tint: Color
    @Environment(PlayerController.self) private var player

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let catalog { player.playAlbum(catalog, tracks: tracks) }
            } label: {
                HStack(spacing: 8) {
                    if let c = catalog, player.loadingKey == "album-\(c.collectionId)" { ProgressView().controlSize(.small) }
                    else { Image(systemName: "play.fill") }
                    Text(player.preferFullTracks && player.appleMusic.isReady ? "Play Album" : "Play Previews")
                }
                .font(.system(size: 14, weight: .bold))
                .padding(.horizontal, 18).padding(.vertical, 10)
                .foregroundStyle(Theme.ink)
                .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .disabled(catalog == nil)

            Button { player.openInMusic(catalog?.url) } label: {
                Label("Open in Music", systemImage: "music.note")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .foregroundStyle(Theme.cream)
                    .background(Capsule().strokeBorder(Theme.cream.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(catalog?.url == nil)
        }
    }
}

/// Persistent mini-player.
struct NowPlayingBar: View {
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        if let np = player.current {
            HStack(spacing: 16) {
                RemoteImage(url: np.artwork) { Theme.panelHi }
                    .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                    HStack(spacing: 6) {
                        if let a = library.artist(named: np.artist) {
                            Button(np.artist) { router.go(.artist(a.id)) }.buttonStyle(.plain)
                        } else { Text(np.artist) }
                        Text(np.isFullTrack ? "APPLE MUSIC" : "PREVIEW")
                            .font(.system(size: 9, weight: .heavy)).tracking(1)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(np.isFullTrack ? Color(hex: "#FA2D48") : Theme.panelHi))
                            .foregroundStyle(np.isFullTrack ? .white : Theme.muted)
                        if np.isFullTrack && player.scrobbler.isActive {
                            let done = player.scrobbler.currentScrobbled
                            Image(systemName: done ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(done ? Color(hex: "#D51007") : Theme.faint)
                                .help(done ? "Scrobbled to Last.fm" : "Scrobbles to Last.fm once half the track has played")
                        }
                    }
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    if let line = soundLine {
                        Text(line).font(.system(size: 10)).foregroundStyle(Theme.faint).lineLimit(1)
                            .help(soundHelp)
                    }
                }
                .frame(width: 260, alignment: .leading)

                HStack(spacing: 18) {
                    Button(action: player.previous) { Image(systemName: "backward.fill") }
                    Button(action: player.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 30))
                    }
                    Button(action: player.next) { Image(systemName: "forward.fill") }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.cream).font(.system(size: 15))

                ProgressScrubber(elapsed: player.elapsed, duration: player.duration) { player.seek(to: $0) }

                if !np.isFullTrack {
                    Text(player.appleMusic.isReady ? "" : "Connect Apple Music in Settings for full tracks")
                        .font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(1)
                        .frame(maxWidth: 180)
                }
                Button { player.openInMusic(np.appleMusicURL) } label: {
                    if let better = player.betterAvailable {
                        Label("\(better.label) in Music", systemImage: "arrow.up.forward.app")
                    } else {
                        Label("Open in Music", systemImage: "arrow.up.forward.app")
                    }
                }
                .buttonStyle(.plain).foregroundStyle(Theme.muted).font(.system(size: 12))
                .help(player.betterAvailable.map { "This song is in \($0.label) on Apple Music. The Music app plays it that way; apps on the Mac get the AAC stream." } ?? "")
                Button(action: player.stop) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Rectangle().fill(Theme.panelHi).frame(height: 1) }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

private extension NowPlayingBar {
    /// "AAC 256 kbps · Scarlett 2i2 4th Gen · 44.1 kHz".
    var soundLine: String? {
        let parts = [player.quality?.label, player.output?.summary].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var soundHelp: String {
        var s = player.quality == .preview
            ? "Previews are AAC at 44.1 kHz."
            : "Apple Music gives apps on the Mac its AAC stream (256 kbps, 44.1 kHz). Lossless and Hi-Res Lossless play only in the Music app."
        if player.matchOutputRate, player.output?.isAirPlay == false, player.output?.isBluetooth == false {
            s += " The output runs at 44.1 kHz while Jazz Discovery plays, so the Mac doesn't resample it (Settings ▸ Apple Music)."
        }
        return s
    }
}

struct ProgressScrubber: View {
    let elapsed: Double
    let duration: Double
    let onSeek: (Double) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(fmt(elapsed)).monospacedDigit()
            GeometryReader { geo in
                let f = duration > 0 ? min(1, elapsed / duration) : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panelHi)
                    Capsule().fill(Theme.brass).frame(width: geo.size.width * f)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { onSeek($0.location.x / max(1, geo.size.width)) })
            }
            .frame(height: 16)
            Text(fmt(duration)).monospacedDigit()
        }
        .font(.system(size: 11)).foregroundStyle(Theme.faint)
        .frame(minWidth: 200, maxWidth: 420)
    }

    private func fmt(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
