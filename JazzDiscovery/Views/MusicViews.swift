import SwiftUI

/// A list of catalog tracks with play buttons (full track via Apple Music, or preview).
struct TrackList: View {
    let tracks: [CatalogTrack]
    var tint: Color = Theme.brass
    var showArtist = false
    var highlight: [String] = []
    /// Told which track the pointer is over (nil when it leaves the list), for the album page's personnel.
    var onHover: ((CatalogTrack?) -> Void)? = nil
    @Environment(PlayerController.self) private var player
    @State private var hovered: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tracks.enumerated()), id: \.element.id) { i, t in
                TrackRow(track: t, number: t.trackNumber ?? (i + 1), tint: tint, showArtist: showArtist,
                         highlighted: highlight.contains { t.name.localizedCaseInsensitiveContains($0) },
                         hoverChanged: { inside in
                             // Entering the next row can arrive before leaving this one.
                             if inside { hovered = t.trackId; onHover?(t) }
                             else if hovered == t.trackId { hovered = nil; onHover?(nil) }
                         }) {
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
    var hoverChanged: ((Bool) -> Void)? = nil
    var action: () -> Void
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
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
                    if let tune = library.tune(forTrackTitle: track.name) {
                        Button { router.go(.tune(tune.id)) } label: { Image(systemName: "music.quarternote.3") }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.muted)
                            .help("\(tune.title) in the Songbook")
                    }
                    if let guide = library.guide(forSongID: track.trackId) {
                        Button { router.go(.guide(guide.id)) } label: { Image(systemName: "list.bullet.rectangle.portrait") }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.brass)
                            .help("A listening guide follows this recording")
                    }
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
        .onHover { hovering = $0; hoverChanged?($0) }
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

/// The player: a glass capsule over the foot of every page, after Music Library's. What the app has to say about the
/// track (why a station chose it, the next stop on a path, its listening guide, the doors out of a finished record) is
/// in a bubble above it (`PlayerNotes`), not in the bar.
struct NowPlayingBar: View {
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @Environment(Passport.self) private var passport
    @State private var hoveringCover = false

    var body: some View {
        if let np = player.current {
            VStack(alignment: .leading, spacing: 8) {
                PlayerNotes()
                bar(np)
            }
            .frame(maxWidth: 980)
            .padding(.horizontal, 20).padding(.bottom, 14)
            .frame(maxWidth: .infinity)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func bar(_ np: NowPlaying) -> some View {
        let record = player.currentCollectionId.flatMap { passport.albumID(forCollection: $0) }.flatMap { library.album($0) }
        return HStack(spacing: 16) {
            HStack(spacing: 10) {
                Button { if let record { router.go(.album(record.id)) } } label: {
                    RemoteImage(url: np.artwork) { Theme.panelHi }
                        .frame(width: 46, height: 46)
                        .overlay {
                            if hoveringCover && record != nil {
                                ZStack {
                                    Color.black.opacity(0.45)
                                    Image(systemName: "arrow.up.right").font(.headline).foregroundStyle(.white)
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(record == nil)
                .onHover { hoveringCover = $0 }
                .help(record.map { "Open \($0.title)" } ?? "")
                VStack(alignment: .leading, spacing: 2) {
                    Text(np.title).font(.headline).foregroundStyle(Theme.cream).lineLimit(1)
                    Group {
                        if let a = library.artist(named: np.artist) {
                            Button(np.artist) { router.go(.artist(a.id)) }.buttonStyle(.plain)
                        } else {
                            Text(np.artist)
                        }
                    }
                    .font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                    caption(np)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 250, alignment: .leading)

            HStack(spacing: 14) {
                Button(action: player.previous) { Image(systemName: "backward.fill") }
                    .help("Previous")
                Button(action: player.togglePlayPause) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 20)
                }
                .help(player.isPlaying ? "Pause" : "Play")
                Button(action: player.next) { Image(systemName: "forward.fill") }
                    .help("Next")
            }
            .buttonStyle(.borderless).font(.title2).foregroundStyle(Theme.cream)

            ProgressScrubber(elapsed: player.elapsed, duration: player.duration) { player.seek(to: $0) }

            Button { player.openInMusic(np.appleMusicURL) } label: {
                Image(systemName: "arrow.up.forward.app").font(.title3)
                    .foregroundStyle(player.betterAvailable == nil ? Theme.muted : Theme.brass)
            }
            .buttonStyle(.borderless)
            .help(player.betterAvailable.map {
                "Open in Music: this song is in \($0.label) on Apple Music. The Music app plays it that way; apps on the Mac get the AAC stream."
            } ?? "Open in Music")
            .accessibilityLabel("Open in Music")
            Button(action: player.stop) { Image(systemName: "xmark").font(.body.weight(.semibold)) }
                .buttonStyle(.borderless).foregroundStyle(Theme.faint)
                .help("Stop")
        }
        .padding(.leading, 9).padding(.trailing, 20).padding(.vertical, 9)
        .modifier(GlassPanel(cornerRadius: 32, capsule: true))
    }

    /// The third line: where it's playing from (Apple Music or a preview), the Last.fm mark and the sound.
    private func caption(_ np: NowPlaying) -> some View {
        HStack(spacing: 5) {
            Text(np.isFullTrack ? "APPLE MUSIC" : "PREVIEW")
                .font(.system(size: 8, weight: .heavy)).tracking(0.8)
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Capsule().fill(np.isFullTrack ? Color(hex: "#FA2D48") : Theme.panelHi))
                .foregroundStyle(np.isFullTrack ? .white : Theme.muted)
                .help(np.isFullTrack || player.appleMusic.isReady ? "" : "A 30-second preview. Connect Apple Music in Settings for full tracks.")
            if np.isFullTrack && player.scrobbler.isActive {
                let done = player.scrobbler.currentScrobbled
                Image(systemName: done ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(done ? Color(hex: "#D51007") : Theme.faint)
                    .help(done ? "Scrobbled to Last.fm" : "Scrobbles to Last.fm once half the track has played")
            }
            if let line = soundLine {
                Text(line).font(.caption2).foregroundStyle(Theme.faint).lineLimit(1).help(soundHelp)
            }
        }
    }
}

/// What the player has to say about what's playing, in a bubble over the bar: why a station chose the track, the next
/// stop on the path it came from, the section of its listening guide, or the doors out of a record that just ended. It
/// folds down to a small tab (and stays folded until you open it again), and isn't there when there's nothing to say.
struct PlayerNotes: View {
    @AppStorage("playerNotesExpanded") private var expanded = true
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @Environment(Passport.self) private var passport

    private enum Topic {
        case doors, why, nextStop, guide
        var title: String {
            switch self {
            case .doors: return "Where next?"
            case .why: return "Why this track"
            case .nextStop: return "Next stop"
            case .guide: return "Listening guide"
            }
        }
        var symbol: String {
            switch self {
            case .doors: return "door.left.hand.open"
            case .why: return "dot.radiowaves.left.and.right"
            case .nextStop: return "forward.end.fill"
            case .guide: return "list.bullet.rectangle.portrait"
            }
        }
    }

    /// What there is to show, in the order the bubble shows it.
    private var topics: [Topic] {
        var t: [Topic] = []
        if player.finishedCollectionId.flatMap({ passport.albumID(forCollection: $0) }).flatMap({ library.album($0) }) != nil {
            t.append(.doors)
        }
        if player.currentStationTrack != nil && player.station != nil { t.append(.why) }
        if let ref = player.pathStop, PathPlayback.after(ref, library: library, passport: passport) != nil { t.append(.nextStop) }
        if player.currentGuide(library: library) != nil { t.append(.guide) }
        return t
    }

    var body: some View {
        let topics = topics
        Group {
            if let first = topics.first {
                if expanded {
                    VStack(alignment: .leading, spacing: 12) {
                        FinishedAlbumDoors { router.go(.album($0)) }
                        WhyThisTrack(compact: true, openAlbum: { router.go(.album($0)) }, openArtist: { router.go(.artist($0)) },
                                     openEra: { router.go(.era($0)) })
                            .frame(maxWidth: .infinity, alignment: .leading)
                        NextStopButton { router.go($0) }
                        NowPlayingGuide { router.go(.guide($0)) }
                    }
                    .padding(.leading, 16).padding(.trailing, 34).padding(.vertical, 14)
                    .frame(maxWidth: 520, alignment: .leading)
                    .overlay(alignment: .topTrailing) {
                        Button { withAnimation(.spring(response: 0.3)) { expanded = false } } label: {
                            Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(Theme.muted)
                                .frame(width: 22, height: 22).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).padding(8)
                        .help("Hide")
                        .accessibilityLabel("Hide \(first.title.lowercased())")
                    }
                    .modifier(GlassPanel(cornerRadius: 18))
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
                } else {
                    Button { withAnimation(.spring(response: 0.3)) { expanded = true } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: first.symbol)
                            Text(first.title)
                            if topics.count > 1 { Text("+\(topics.count - 1)").foregroundStyle(Theme.faint) }
                            Image(systemName: "chevron.up").font(.caption2.weight(.bold))
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.cream.opacity(0.85))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .modifier(GlassPanel(cornerRadius: 14, capsule: true))
                    .help("Show \(topics.map { $0.title.lowercased() }.joined(separator: ", "))")
                    .transition(.opacity)
                }
            }
        }
        .padding(.leading, 12)
        .animation(.spring(response: 0.35), value: topics.first == nil)
    }
}

/// The player in the menu bar (Settings ▸ Apple Music ▸ Menu Bar): what's playing, why a station chose it, the
/// controls, and a way back to the window, on the record's page when it's in the Crate.
struct MenuBarPlayer: View {
    static let settingKey = "showsMenuBarPlayer"
    /// The main window's ID (`JazzDiscoveryApp`).
    static let mainWindowID = "main"

    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @Environment(Passport.self) private var passport
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let np = player.current {
                HStack(spacing: 12) {
                    RemoteImage(url: np.artwork) { Theme.panelHi }
                        .frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(np.title).font(.headline).foregroundStyle(Theme.cream).lineLimit(2)
                        Text(np.artist).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(1)
                        Text(np.isFullTrack ? "Apple Music" : "Preview").font(.caption2).foregroundStyle(Theme.faint)
                    }
                }
                if let t = player.currentStationTrack, let station = player.station {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(station.title.uppercased()).font(Theme.label(9)).tracking(1.2).foregroundStyle(station.tint)
                        Text(Programmer.reason(for: t, library: library)).font(.system(size: 12, design: .serif)).italic()
                            .foregroundStyle(Theme.cream.opacity(0.85)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                ProgressScrubber(elapsed: player.elapsed, duration: player.duration) { player.seek(to: $0) }
                HStack(spacing: 22) {
                    Spacer()
                    Button(action: player.previous) { Image(systemName: "backward.fill") }.help("Previous")
                    Button(action: player.togglePlayPause) {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").frame(width: 24)
                    }
                    .help(player.isPlaying ? "Pause" : "Play")
                    Button(action: player.next) { Image(systemName: "forward.fill") }.help("Next")
                    Spacer()
                }
                .buttonStyle(.borderless).font(.title2).foregroundStyle(Theme.cream)
                Divider()
                HStack {
                    Button(record == nil ? "Show Jazz Discovery" : "Show the Record") { show() }
                    Spacer()
                    Button("Stop") { player.stop() }
                }
                .buttonStyle(.borderless).font(.callout)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(Theme.ink)
    }

    private var record: Album? {
        player.currentCollectionId.flatMap { passport.albumID(forCollection: $0) }.flatMap { library.album($0) }
    }

    /// Brings the window forward (opening it again if it was closed), on the record's page.
    private func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(Self.mainWindowID) == true }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: Self.mainWindowID)
        }
        if let record {
            router.query = ""
            if router.path.last != .album(record.id) { router.go(.album(record.id)) }
        }
    }
}

/// A floating panel in the system's glass (Liquid Glass from macOS 26; a blurred material before it).
struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat
    /// Fully rounded ends, whatever the height.
    var capsule = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if capsule {
                content.glassEffect(.regular, in: .capsule)
            } else {
                content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.panelHi))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
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
        .font(.caption).foregroundStyle(Theme.faint)
        .frame(minWidth: 180, maxWidth: .infinity)
    }

    private func fmt(_ t: Double) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
