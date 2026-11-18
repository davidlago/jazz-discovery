import SwiftUI
import AVKit

// MARK: - Track lists

/// Catalog tracks; tapping one plays the list from there (full tracks with Apple Music, previews otherwise).
struct TrackList: View {
    let tracks: [CatalogTrack]
    var visible: Int? = nil
    var tint: Color = Theme.brass
    var showArtwork = false
    var highlight: [String] = []
    @Environment(PlayerController.self) private var player

    var body: some View {
        let shown = Array(tracks.prefix(visible ?? tracks.count).enumerated())
        VStack(spacing: 0) {
            ForEach(shown, id: \.element.id) { i, t in
                // Songs from different albums (an artist's most popular) are numbered by rank, an album's by track.
                TrackRow(track: t, number: showArtwork ? i + 1 : (t.trackNumber ?? i + 1), tint: tint, showArtwork: showArtwork,
                         highlighted: highlight.contains { t.name.localizedCaseInsensitiveContains($0) }) {
                    player.play(tracks, startAt: i)
                }
                if i < shown.count - 1 {
                    Divider().overlay(Theme.panelHi).padding(.leading, showArtwork ? 98 : 40)
                }
            }
        }
    }
}

struct TrackRow: View {
    let track: CatalogTrack
    let number: Int
    var tint: Color
    var showArtwork = false
    var highlighted = false
    var action: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        let isCurrent = player.isCurrent(track.trackId)
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    if player.loadingKey == "track-\(track.trackId)" {
                        ProgressView().controlSize(.small)
                    } else if isCurrent {
                        Image(systemName: "waveform")
                            .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                            .foregroundStyle(tint)
                    } else {
                        Text("\(number)").font(.footnote.monospacedDigit()).foregroundStyle(Theme.faint)
                    }
                }
                .frame(width: 26)
                if showArtwork {
                    RemoteImage(url: track.artwork(120)) { Theme.panelHi }
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(track.name).font(.body.weight(isCurrent ? .semibold : .regular))
                            .foregroundStyle(isCurrent ? tint : Theme.cream).lineLimit(1)
                        if highlighted {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(tint)
                                .accessibilityLabel("Start here")
                        }
                        if library.tune(forTrackTitle: track.name) != nil {
                            Image(systemName: "music.quarternote.3").font(.system(size: 10)).foregroundStyle(Theme.muted)
                                .accessibilityLabel("In the Songbook")
                        }
                        if library.guide(forSongID: track.trackId) != nil {
                            Image(systemName: "list.bullet.rectangle.portrait").font(.system(size: 10)).foregroundStyle(Theme.brass)
                                .accessibilityLabel("Has a listening guide")
                        }
                    }
                    if showArtwork, let album = track.albumName {
                        Text(album).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(track.duration).font(.footnote.monospacedDigit()).foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { action() } label: { Label("Play", systemImage: "play.fill") }
            if let url = track.url {
                Button { player.openInMusic(url) } label: { Label("Open in Apple Music", systemImage: "music.note") }
            }
            if let a = library.artist(named: track.artistName) {
                Button { router.go(.artist(a.id)) } label: { Label("Go to \(a.name)", systemImage: "person") }
            }
            if let tune = library.tune(forTrackTitle: track.name) {
                Button { router.go(.tune(tune.id)) } label: { Label("Open in Songbook", systemImage: "music.quarternote.3") }
            }
            if let guide = library.guide(forSongID: track.trackId) {
                Button { router.go(.guide(guide.id)) } label: { Label("Listening Guide", systemImage: "list.bullet.rectangle.portrait") }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: isCurrent && player.isPlaying)
    }
}

/// A curated "essential track", matched to the Apple Music catalog when it shows.
struct EssentialTrackRow: View {
    let ref: TrackRef
    let tint: Color
    let index: Int
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router
    @State private var track: CatalogTrack?
    @State private var resolved = false

    var body: some View {
        let isCurrent = track.map { player.isCurrent($0.trackId) } ?? false
        Button { if let track { player.play(track) } else { player.searchInMusic("\(ref.artist) \(ref.title)") } } label: {
            HStack(spacing: 12) {
                ZStack {
                    RemoteImage(url: track?.artwork(120)) { tint.opacity(0.2) }
                    if isCurrent || (resolved && track == nil) || player.loadingKey == track.map({ "track-\($0.trackId)" }) {
                        Color.black.opacity(0.45)
                        if let track, player.loadingKey == "track-\(track.trackId)" {
                            ProgressView().controlSize(.small).tint(.white)
                        } else if isCurrent {
                            Image(systemName: "waveform").symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "magnifyingglass").foregroundStyle(.white)
                        }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title).font(.body.weight(.semibold)).foregroundStyle(isCurrent ? tint : Theme.cream).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(ref.artist).foregroundStyle(library.artist(named: ref.artist) != nil ? tint : Theme.muted)
                        if let y = ref.year { Text("· \(String(y))").foregroundStyle(Theme.faint) }
                    }
                    .font(.footnote).lineLimit(1)
                }
                Spacer(minLength: 8)
                if resolved && track == nil {
                    Text("Search").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                } else if let track {
                    Text(track.duration).font(.footnote.monospacedDigit()).foregroundStyle(Theme.faint)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityHint(track == nil && resolved ? "Searches Apple Music" : "Plays the track")
        .contextMenu {
            if let track {
                Button { player.play(track) } label: { Label("Play", systemImage: "play.fill") }
                if let url = track.url {
                    Button { player.openInMusic(url) } label: { Label("Open in Apple Music", systemImage: "music.note") }
                }
            }
            Button { player.searchInMusic("\(ref.artist) \(ref.title)") } label: {
                Label("Search in Apple Music", systemImage: "magnifyingglass")
            }
            if let a = library.artist(named: ref.artist) {
                Button { router.go(.artist(a.id)) } label: { Label("Go to \(a.name)", systemImage: "person") }
            }
        }
        .task(id: ref.id) {
            try? await Task.sleep(for: .milliseconds(120 * index))  // stagger catalog lookups
            track = await ITunes.shared.track(ref.title, artist: ref.artist)
            resolved = true
        }
    }
}

/// "Play Album" and "Apple Music" side by side.
struct AlbumPlayControls: View {
    let catalog: CatalogAlbum?
    let tracks: [CatalogTrack]
    let tint: Color
    @Environment(PlayerController.self) private var player

    var body: some View {
        HStack(spacing: 12) {
            Button {
                if let catalog { player.playAlbum(catalog, tracks: tracks) }
            } label: {
                HStack(spacing: 8) {
                    if let c = catalog, player.loadingKey == "album-\(c.collectionId)" {
                        ProgressView().controlSize(.small).tint(Theme.ink)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(player.preferFullTracks && player.appleMusic.isReady ? "Play Album" : "Play Previews")
                }
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Theme.ink)
                .background(Capsule().fill(tint))
            }
            .buttonStyle(.pressable)
            .disabled(catalog == nil)
            .opacity(catalog == nil ? 0.5 : 1)
            .sensoryFeedback(.impact(weight: .medium), trigger: player.loadingKey)

            Button { player.openInMusic(catalog?.url) } label: {
                Label("Apple Music", systemImage: "arrow.up.forward")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(Theme.cream)
                    .background(Capsule().fill(Theme.panelHi))
            }
            .buttonStyle(.pressable)
            .disabled(catalog?.url == nil)
            .accessibilityLabel("Open in Apple Music")
        }
    }
}

// MARK: - Mini player (above the tab bar)

struct MiniPlayer: View {
    @Environment(PlayerController.self) private var player
    @Environment(PhoneRouter.self) private var router
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        if let np = player.current {
            HStack(spacing: 12) {
                RemoteImage(url: np.artwork) { Theme.panelHi }
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(np.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if placement != .inline {
                        Text(np.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                if placement != .inline {
                    Button(action: player.next) {
                        Image(systemName: "forward.fill").font(.body).frame(width: 32, height: 36).contentShape(Rectangle())
                    }
                    .accessibilityLabel("Next")
                }
            }
            .padding(.leading, 10).padding(.trailing, 8)
            .foregroundStyle(Theme.cream)
            .contentShape(Rectangle())
            .onTapGesture { router.showNowPlaying = true }
            .accessibilityAction(named: "Open Now Playing") { router.showNowPlaying = true }
        }
    }
}

// MARK: - Now Playing

struct NowPlayingView: View {
    @Environment(PlayerController.self) private var player
    @Environment(PhoneRouter.self) private var router
    @Environment(JazzLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            backdrop
            if let np = player.current {
                content(np)
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "music.note",
                                       description: Text("Play a track, an album or an era's essentials."))
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.ink)
    }

    private var backdrop: some View {
        ZStack {
            Theme.ink
            RemoteImage(url: player.current?.artwork) { Color.clear }
                .scaleEffect(1.6)
                .blur(radius: 80)
                .opacity(0.65)
            LinearGradient(colors: [Theme.ink.opacity(0.2), Theme.ink.opacity(0.85)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func content(_ np: NowPlaying) -> some View {
        let artist = library.artist(named: np.artist)
        return VStack(spacing: 0) {
            Spacer(minLength: 24)
            RemoteImage(url: np.artwork) { Theme.panelHi.overlay(Image(systemName: "music.note").font(.largeTitle).foregroundStyle(Theme.faint)) }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.55), radius: 30, y: 18)
                .scaleEffect(player.isPlaying ? 1 : 0.84)
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: player.isPlaying)
                .padding(.horizontal, 32)
                .accessibilityHidden(true)
            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(np.title).font(.title3.weight(.bold)).foregroundStyle(Theme.cream).lineLimit(1)
                        if let artist {
                            Button { router.go(.artist(artist.id)) } label: {
                                Text(np.artist).font(.title3).foregroundStyle(Theme.cream.opacity(0.65)).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the artist's page")
                        } else {
                            Text(np.artist).font(.title3).foregroundStyle(Theme.cream.opacity(0.65)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Menu {
                        Button { player.openInMusic(np.appleMusicURL) } label: { Label("Open in Apple Music", systemImage: "music.note") }
                            .disabled(np.appleMusicURL == nil)
                        if let artist {
                            Button { router.go(.artist(artist.id)) } label: { Label("Go to \(artist.name)", systemImage: "person") }
                        }
                        Divider()
                        Button(role: .destructive) { player.stop(); dismiss() } label: { Label("Stop", systemImage: "stop.fill") }
                    } label: {
                        Image(systemName: "ellipsis").font(.body.weight(.bold)).frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("More")
                }

                if player.isBlind {
                    Text("A Blindfold Test clip: the answer is on the game's page.").font(.caption).foregroundStyle(Theme.muted)
                } else {
                    SourceLine(np: np)
                }

                WhyThisTrack(compact: true,
                             openAlbum: { router.go(.album($0)) }, openArtist: { router.go(.artist($0)) },
                             openEra: { router.go(.era($0)) })
                NextStopButton { router.go(.page($0)) }
                NowPlayingGuide(compact: true) { router.go(.guide($0)) }

                Scrubber(elapsed: player.elapsed, duration: player.duration) { player.seek(to: $0) }

                HStack {
                    Spacer()
                    Button(action: player.previous) { Image(systemName: "backward.fill").font(.system(size: 30)) }
                        .accessibilityLabel("Previous")
                    Spacer()
                    Button(action: player.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 50))
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 80, height: 80)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    .sensoryFeedback(.impact(weight: .light), trigger: player.isPlaying)
                    Spacer()
                    Button(action: player.next) { Image(systemName: "forward.fill").font(.system(size: 30)) }
                        .accessibilityLabel("Next")
                    Spacer()
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .foregroundStyle(Theme.cream)

                HStack {
                    if !np.isFullTrack && !player.appleMusic.isReady {
                        Button {
                            router.showNowPlaying = false
                            Task { try? await Task.sleep(for: .milliseconds(450)); router.showSettings = true }
                        } label: {
                            Label("Full tracks with Apple Music", systemImage: "applelogo")
                                .font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button { player.openInMusic(np.appleMusicURL) } label: {
                            Label("Apple Music", systemImage: "arrow.up.forward").font(.footnote.weight(.semibold))
                        }
                        .buttonStyle(.glass)
                        .disabled(np.appleMusicURL == nil)
                    }
                    Spacer()
                    AirPlayButton().frame(width: 44, height: 44)
                }
                .foregroundStyle(Theme.cream)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 20)

            if player.finishedCollectionId != nil {
                FinishedAlbumDoors { router.go(.album($0)) }
                    .padding(.horizontal, 28).padding(.bottom, 16)
            } else if !player.upNext.isEmpty {
                UpNextStrip()
            }
        }
    }
}

/// Where the music comes from, and what Last.fm makes of it.
private struct SourceLine: View {
    let np: NowPlaying
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            badges
            if np.isFullTrack, let line = soundLine {
                Label(line, systemImage: player.quality?.isLossless == true ? "waveform" : "hifispeaker")
                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
            if np.isFullTrack, let hint {
                Text(hint).font(.caption2).foregroundStyle(Theme.faint).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Hi-Res Lossless · Scarlett 2i2 4th Gen · 96 kHz".
    private var soundLine: String? {
        let parts = [player.quality?.label, player.output?.summary].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var hint: String? {
        if let better = player.betterAvailable {
            return "This song is in \(better.label) on Apple Music. Turn it on in Settings ▸ Apps ▸ Music ▸ Audio Quality."
        }
        if player.quality?.isLossless == true, player.output?.isBluetooth == true {
            return "Bluetooth carries Apple Music as AAC. For lossless, use wired headphones or a USB DAC."
        }
        return nil
    }

    private var badges: some View {
        HStack(spacing: 10) {
            Text(np.isFullTrack ? "APPLE MUSIC" : "PREVIEW")
                .font(.system(size: 10, weight: .heavy)).tracking(1)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(np.isFullTrack ? Theme.appleMusicRed : Theme.panelHi))
                .foregroundStyle(np.isFullTrack ? .white : Theme.muted)
            if np.isFullTrack && player.scrobbler.isActive {
                let done = player.scrobbler.currentScrobbled
                Label(done ? "Scrobbled" : "Scrobbles at the halfway mark",
                      systemImage: done ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(done ? Theme.lastfmRed : Theme.muted)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut, value: done)
            } else if !np.isFullTrack {
                Text("30-second preview").font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct UpNextStrip: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("UP NEXT").font(Theme.label(10)).tracking(1.5).foregroundStyle(Theme.muted)
                .padding(.horizontal, 28)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(player.upNext.prefix(12)) { t in
                        Button { player.playUpNext(t) } label: {
                            HStack(spacing: 8) {
                                RemoteImage(url: t.artwork(100)) { Theme.panelHi }
                                    .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 5))
                                Text(t.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.cream).lineLimit(2)
                                    .frame(width: 110, alignment: .leading)
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 28, for: .scrollContent)
        }
        .padding(.bottom, 16)
    }
}

/// A scrubber that grows under the finger, like the Music app's.
struct Scrubber: View {
    let elapsed: Double
    let duration: Double
    let onSeek: (Double) -> Void
    @State private var dragFraction: Double?

    var body: some View {
        let f = dragFraction ?? (duration > 0 ? min(1, elapsed / duration) : 0)
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cream.opacity(0.2))
                    Capsule().fill(Theme.cream.opacity(dragFraction == nil ? 0.85 : 1)).frame(width: geo.size.width * f)
                }
                .frame(height: dragFraction == nil ? 6 : 12)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { dragFraction = max(0, min(1, $0.location.x / max(1, geo.size.width))) }
                    .onEnded { _ in
                        if let d = dragFraction { onSeek(d) }
                        dragFraction = nil
                    })
                .animation(.spring(response: 0.25), value: dragFraction == nil)
            }
            .frame(height: 24)
            HStack {
                Text(fmt(f * duration))
                Spacer()
                Text("-" + fmt(max(0, duration - f * duration)))
            }
            .font(.caption2.monospacedDigit().weight(.medium)).foregroundStyle(Theme.cream.opacity(0.55))
        }
        .accessibilityElement()
        .accessibilityLabel("Position")
        .accessibilityValue("\(fmt(elapsed)) of \(fmt(duration))")
        .accessibilityAdjustableAction { dir in
            guard duration > 0 else { return }
            let step = 10 / duration
            onSeek(min(1, max(0, elapsed / duration + (dir == .increment ? step : -step))))
        }
    }

    private func fmt(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The system AirPlay picker.
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = UIColor(Theme.cream)
        v.activeTintColor = UIColor(Theme.brass)
        v.prioritizesVideoDevices = false
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
