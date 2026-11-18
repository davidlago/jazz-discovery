import SwiftUI

/// Whether a guide can follow what's playing.
enum GuideSync: Equatable {
    /// The recording is playing in full, and it's the one the times were taken from.
    case following
    case notPlaying
    /// The recording is playing as a 30-second preview, which can't be placed in the track.
    case preview
    /// It's playing in full, but another edition than the times are for.
    case otherEdition
    /// The guide has no times yet.
    case untimed
}

extension PlayerController {
    /// Whether the guide's recording is what's playing, in any edition, full or preview.
    func isPlaying(_ guide: Guide, library: JazzLibrary) -> Bool {
        guard let np = current, let id = currentTrackID, !isBlind else { return false }
        if id == guide.songID || id == library.tracks[guide.track]?.id { return true }
        let parts = guide.track.split(separator: "|", maxSplits: 1).map { Guide.fold(String($0)) }
        return parts.count == 2 && Guide.fold(np.title) == parts[1] && Guide.fold(np.artist).contains(parts[0])
    }

    func sync(for guide: Guide, library: JazzLibrary) -> GuideSync {
        guard isPlaying(guide, library: library) else { return guide.isTimed ? .notPlaying : .untimed }
        guard usingAppleMusic else { return .preview }
        guard guide.isTimed else { return .untimed }
        return guide.fits(songID: currentTrackID, title: current?.title, artist: current?.artist, duration: duration)
            ? .following : .otherEdition
    }

    /// The guide for what's playing now, if there is one.
    func currentGuide(library: JazzLibrary) -> Guide? {
        guard let np = current, !isBlind else { return nil }
        return library.guide(songID: currentTrackID, title: np.title, artist: np.artist, duration: duration)
            ?? library.guides.first { isPlaying($0, library: library) }
    }
}

/// A listening guide's page: what to listen for, section by section, following the music as it plays.
struct GuideView: View {
    let guide: Guide
    var compact = false
    var openArtist: (String) -> Void
    var openTerm: (String) -> Void
    var openAlbum: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        let sync = player.sync(for: guide, library: library)
        let following = sync == .following
        let current = following ? guide.section(at: player.elapsed) : nil
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: compact ? 18 : 24) {
                    header(sync)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(guide.sections.enumerated()), id: \.offset) { i, s in
                            row(i, s, current: current, following: following).id(i)
                        }
                    }
                }
                .padding(.horizontal, compact ? 20 : 40)
                .padding(.top, compact ? 16 : 36).padding(.bottom, 50)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if guide.isTimed {
                    FormBar(guide: guide, synced: following, height: compact ? 28 : 34,
                            onJump: following ? { jump(to: $0) } : nil)
                        .padding(.horizontal, compact ? 20 : 40).padding(.vertical, 10)
                        .frame(maxWidth: 820)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                }
            }
            .onChange(of: current) { _, i in
                guard let i else { return }
                withAnimation(.easeInOut(duration: 0.5)) { proxy.scrollTo(i, anchor: UnitPoint(x: 0.5, y: 0.3)) }
            }
        }
        .background(Theme.ink)
    }

    private var track: StationTrack? { library.tracks[guide.track] }

    @ViewBuilder
    private func header(_ sync: GuideSync) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LISTENING GUIDE").font(Theme.label(11)).tracking(3).foregroundStyle(Theme.brass)
            Text(track?.title ?? guide.id).font(Theme.display(compact ? 40 : 56)).foregroundStyle(Theme.cream)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Text(byline).font(.system(size: compact ? 15 : 16, weight: .semibold)).foregroundStyle(Theme.muted)
                if let id = guide.album, let album = library.album(id) {
                    Button("\(album.title) →") { openAlbum(id) }.buttonStyle(.plain)
                        .font(.system(size: compact ? 14 : 15, weight: .semibold)).foregroundStyle(Theme.brass)
                }
            }
            TermText(text: guide.intro, font: Theme.serif(compact ? 17 : 19), openTerm: openTerm)
                .fixedSize(horizontal: false, vertical: true)
            Text(guide.form).font(.system(size: 14)).italic().foregroundStyle(Theme.muted)
            HStack(spacing: 14) {
                playButton
                Text(status(sync)).font(.system(size: 13)).foregroundStyle(sync == .following ? Theme.cream : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 4)
        }
    }

    private var byline: String {
        let year = track.flatMap { Programmer.year($0, library: library) }.map { String($0) }
        return [track?.artistName, year].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var playButton: some View {
        let playing = player.isPlaying(guide, library: library)
        Button {
            if playing { player.togglePlayPause() } else if let t = track { player.play(t.track) }
        } label: {
            Label(playing ? (player.isPlaying ? "Pause" : "Play") : "Play", systemImage: playing && player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
        }
        .buttonStyle(.plain)
        .disabled(track == nil)
    }

    private func status(_ sync: GuideSync) -> String {
        switch sync {
        case .following: return "Following the recording. Click a section to go to it."
        case .notPlaying: return "Press play: the guide follows the full track with Apple Music."
        case .preview: return "This is the 30-second preview. The guide follows the full track, which needs Apple Music; read along meanwhile."
        case .otherEdition: return "This is another edition of the recording. The times are for a different one, so the guide can't follow it."
        case .untimed: return "Not timed yet: the sections are in order, without times."
        }
    }

    private func jump(to i: Int) {
        guard let at = guide.sections[i].at else { return }
        player.seek(toSeconds: at)
    }

    private func row(_ i: Int, _ s: GuideSection, current: Int?, following: Bool) -> some View {
        let isCurrent = current == i
        let tint = sectionTint(s)
        return HStack(alignment: .top, spacing: compact ? 10 : 14) {
            Text(s.at.map(GuideTime.text) ?? "–")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? Theme.brass : Theme.faint)
                .frame(width: compact ? 34 : 42, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 8) {
                    Text(s.kind.label.uppercased()).font(Theme.label(10)).tracking(1.5).foregroundStyle(tint)
                        .padding(.top, 2)
                    ForEach(s.who, id: \.self) { w in
                        if library.artist(w) != nil {
                            Button(library.guideName(w)) { openArtist(w) }.buttonStyle(.plain)
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted)
                        } else {
                            Text(w).font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                Text(s.label).font(.system(size: isCurrent && !compact ? 19 : 16, weight: .bold)).foregroundStyle(Theme.cream)
                TermText(text: s.note, font: Theme.serif(isCurrent && !compact ? 18 : 16), openTerm: openTerm)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(s.marks.enumerated()), id: \.offset) { _, m in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(m.at.map(GuideTime.text) ?? "•").font(.system(size: 11).monospacedDigit()).foregroundStyle(Theme.faint)
                        Text(m.note).font(.system(size: 13)).italic().foregroundStyle(Theme.muted)
                    }
                }
                if !s.terms.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(s.terms, id: \.self) { id in
                            if let t = library.term(id) {
                                Button { openTerm(id) } label: {
                                    Text(t.term).font(.system(size: 11, weight: .semibold))
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .overlay(Capsule().strokeBorder(Theme.brass.opacity(0.5)))
                                        .foregroundStyle(Theme.brass)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(isCurrent ? Theme.panelHi : Theme.panel))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3).padding(.vertical, 12)
        }
        .opacity(following && !isCurrent ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if following { jump(to: i) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .animation(.easeInOut(duration: 0.3), value: isCurrent)
    }

    private func sectionTint(_ s: GuideSection) -> Color {
        switch s.kind {
        case .solo, .trading:
            if let w = s.who.first, let a = library.artist(w) { return library.color(forEra: a.primaryEra) }
            return Theme.brass
        case .head, .headOut, .ensemble: return Theme.cream
        default: return Theme.muted
        }
    }
}

/// A guide on the index: the recording, its form line, and its form bar.
struct GuideCard: View {
    let guide: Guide
    var width: CGFloat? = 300
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let t = library.tracks[guide.track]
        let tint = t?.album.flatMap { library.album($0) }.map { library.color(forEra: $0.era) } ?? Theme.brass
        VStack(alignment: .leading, spacing: 8) {
            Text((t?.title ?? guide.id).uppercased()).font(Theme.display(26)).foregroundStyle(Theme.cream)
                .lineLimit(2).minimumScaleFactor(0.7)
            Text([t?.artistName, t.flatMap { Programmer.year($0, library: library) }.map { String($0) }].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).lineLimit(1)
            Text(guide.form).font(.system(size: 12)).italic().foregroundStyle(Theme.faint).lineLimit(2)
            Spacer(minLength: 0)
            if guide.isTimed {
                FormBar(guide: guide, height: 10, showLabels: false)
            } else {
                Text("NOT TIMED YET").font(Theme.label(9)).tracking(1.5).foregroundStyle(Theme.faint)
            }
        }
        .padding(16)
        .frame(width: width, height: 170, alignment: .topLeading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .overlay(alignment: .top) { Rectangle().fill(tint).frame(height: 4).clipShape(RoundedRectangle(cornerRadius: 2)) }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Every guide, as cards.
struct GuidesRow: View {
    var cardWidth: CGFloat? = 300
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        ForEach(library.guides) { g in
            Button { open(g.id) } label: { GuideCard(guide: g, width: cardWidth) }.buttonStyle(.plain)
        }
    }
}

/// In Now Playing, when the track has a guide: its form bar and the section playing, and a way to the guide.
struct NowPlayingGuide: View {
    var compact = false
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let g = player.currentGuide(library: library) {
            let following = player.sync(for: g, library: library) == .following
            VStack(alignment: .leading, spacing: 6) {
                if following {
                    FormBar(guide: g, synced: true, height: compact ? 16 : 14, showLabels: false) { i in
                        if let at = g.sections[i].at { player.seek(toSeconds: at) }
                    }
                }
                HStack(spacing: 10) {
                    if following, let i = g.section(at: player.elapsed) {
                        let s = g.sections[i]
                        Text(s.label).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.cream).lineLimit(1)
                        Text(s.note).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(compact ? 2 : 1)
                    } else {
                        Text("This recording has a listening guide.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 8)
                    Button { open(g.id) } label: {
                        Label("Guide", systemImage: "list.bullet.rectangle").font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.brass)
                }
            }
        }
    }
}
