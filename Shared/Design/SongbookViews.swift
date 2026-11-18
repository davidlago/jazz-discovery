import SwiftUI

extension JazzLibrary {
    /// The era a version belongs to: its artist's, or the newest style under way that year.
    func era(of version: TuneVersion) -> Era? {
        if let id = version.artist, let a = artist(id), let e = era(a.primaryEra) { return e }
        return eras.filter { $0.start <= version.year && $0.end >= version.year }.max { $0.start < $1.start }
    }
}

/// Five faint staff lines, like the top of a lead sheet.
struct StaffLines: View {
    var spacing: CGFloat = 6
    var color: Color = Theme.cream.opacity(0.12)

    var body: some View {
        VStack(spacing: spacing - 1) {
            ForEach(0..<5) { _ in Rectangle().fill(color).frame(height: 1) }
        }
    }
}

/// A tune as a lead-sheet card: staff lines, the title in serif italic, who wrote it and when, and a dot per version
/// placed by year and coloured by era, so the card shows how far the tune travelled.
struct TuneCard: View {
    let tune: Tune
    var width: CGFloat? = 220
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            StaffLines().padding(.top, 4)
            Text(tune.title).font(.system(size: 21, weight: .regular, design: .serif)).italic()
                .foregroundStyle(Theme.cream).lineLimit(2).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Session.joinedList(tune.composers.map(library.composerName))) · \(String(tune.year))".uppercased())
                .font(Theme.label(9)).tracking(1).foregroundStyle(Theme.muted).lineLimit(2)
            Spacer(minLength: 0)
            VersionDots(tune: tune).frame(height: 14)
            let heard = passport.versionsHeard(of: tune, library: library)
            Text(heard.heard > 0 ? "\(heard.heard) of \(heard.total) heard · \(String(tune.span.lowerBound))–\(String(tune.span.upperBound))"
                 : "\(tune.versions.count) versions · \(String(tune.span.lowerBound))–\(String(tune.span.upperBound))")
                .font(.system(size: 11)).foregroundStyle(heard.heard > 0 ? Theme.brass : Theme.faint)
        }
        .padding(14)
        .frame(width: width, height: 190, alignment: .topLeading)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.panelHi))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(tune.title), \(tune.versions.count) versions from \(tune.span.lowerBound) to \(tune.span.upperBound)")
    }
}

/// One dot per version along 1900–2030, coloured by era.
struct VersionDots: View {
    let tune: Tune
    var highlight: Int? = nil
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        GeometryReader { geo in
            let x = { (y: Int) in CGFloat(y - 1900) / 130 * (geo.size.width - 10) + 5 }
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.panelHi).frame(height: 1)
                ForEach(Array(tune.sortedVersions.enumerated()), id: \.offset) { i, v in
                    Circle().fill(library.era(of: v)?.tint ?? Theme.brass)
                        .frame(width: highlight == i ? 12 : 8, height: highlight == i ? 12 : 8)
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 1))
                        .position(x: x(v.year), y: geo.size.height / 2)
                }
            }
        }
    }
}

/// The Songbook index: tune cards, sortable, filterable by where the tune came from.
struct SongbookGrid: View {
    var minimum: CGFloat = 200
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @State private var byYear = false
    @State private var origin: String?

    var body: some View {
        let origins = Array(Set(library.tunes.map(\.origin))).sorted()
        let list = library.tunes.filter { origin == nil || $0.origin == origin }
            .sorted { byYear ? $0.year < $1.year : Tune.key($0.title) < Tune.key($1.title) }
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Picker("Sort", selection: $byYear) {
                        Text("A–Z").tag(false)
                        Text("By Year").tag(true)
                    }
                    .pickerStyle(.segmented).fixedSize()
                    Button { origin = nil } label: { chip("All", on: origin == nil) }.buttonStyle(.plain)
                    ForEach(origins, id: \.self) { o in
                        Button { origin = origin == o ? nil : o } label: { chip(o, on: origin == o) }.buttonStyle(.plain)
                    }
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 14)], spacing: 14) {
                ForEach(list) { t in
                    Button { open(t.id) } label: { TuneCard(tune: t, width: nil) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(_ text: String, on: Bool) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .foregroundStyle(on ? Theme.ink : Theme.cream)
            .background(Capsule().fill(on ? Theme.brass : Theme.panelHi))
    }
}

/// A tune's page: the story, the versions on a time axis and as rows, play them in order, and its relatives.
struct TuneDetailContent: View {
    let tune: Tune
    var compact = false
    var openArtist: (String) -> Void
    var openAlbum: (String) -> Void
    var openTune: (String) -> Void
    var openTerm: (String) -> Void = { _ in }
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(Passport.self) private var passport

    var body: some View {
        let versions = tune.sortedVersions
        let resolved = versions.compactMap { library.track(for: $0, of: tune) }
        let also = library.alsoInCrate(tune)
        let family = library.family(of: tune)
        VStack(alignment: .leading, spacing: 28) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                StaffLines(spacing: 9).frame(maxWidth: 520)
                Text(tune.title).font(.system(size: compact ? 40 : 60, weight: .regular, design: .serif)).italic()
                    .foregroundStyle(Theme.cream).fixedSize(horizontal: false, vertical: true)
                composers
                Text("\(tune.origin) · \(tune.form)").font(Theme.label(11)).tracking(1).foregroundStyle(Theme.muted)
                if let l = tune.lyricists, !l.isEmpty {
                    Text("Words by \(Session.joinedList(l))").font(.system(size: 12)).foregroundStyle(Theme.faint)
                }
            }
            HStack(spacing: 10) {
                Button { playInOrder(resolved) } label: {
                    Label("Play in Order", systemImage: "play.fill").font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
                }
                .buttonStyle(.plain).disabled(resolved.isEmpty)
                let heard = passport.versionsHeard(of: tune, library: library)
                Text("\(versions.count) versions, \(String(tune.span.lowerBound)) to \(String(tune.span.upperBound))"
                     + (heard.heard > 0 ? " · \(heard.heard) of \(heard.total) heard" : ""))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            ForEach(tune.summary.components(separatedBy: "\n\n"), id: \.self) { p in
                TermText(text: p, font: .system(size: compact ? 16 : 17, design: .serif), openTerm: openTerm).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 680, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 12) {
                header("The Versions", subtitle: "★ marks the one to play if you play only one.")
                VersionDots(tune: tune).frame(height: 18).frame(maxWidth: 680)
                ForEach(Array(versions.enumerated()), id: \.offset) { _, v in versionRow(v) }
            }

            if !also.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    header("Also in the Crate", subtitle: "Other versions on the Crate's records.")
                    ForEach(also, id: \.album.id) { a in
                        Button { openAlbum(a.album.id) } label: {
                            HStack(spacing: 10) {
                                AlbumCover(album: a.album, size: 200, cornerRadius: 3).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(a.album.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
                                    Text("\(a.album.artistName) · \(String(a.album.year))").font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let sameForm = library.sameForm(as: tune)
            if !sameForm.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    header("Same Form", subtitle: tune.formFamily == "blues"
                           ? "Other blues in the Songbook: the same short cycle of chords, played every way there is."
                           : "Other 32-bar AABA songs: two statements, a bridge, and the statement again.")
                    FlowLayout(spacing: 12) {
                        ForEach(sameForm) { t in
                            Button(t.title) { openTune(t.id) }.buttonStyle(.plain)
                                .font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.brass)
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)
                }
            }

            if !family.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    header("Family", subtitle: "Tunes that share its chords.")
                    ForEach(family) { t in
                        Button(t.title) { openTune(t.id) }.buttonStyle(.plain)
                            .font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.brass)
                    }
                }
            }
        }
    }

    private var composers: some View {
        HStack(spacing: 4) {
            ForEach(Array(tune.composers.enumerated()), id: \.offset) { i, c in
                if let a = library.artist(c) {
                    Button(a.name) { openArtist(a.id) }.buttonStyle(.plain).foregroundStyle(Theme.brass)
                } else {
                    Text(c).foregroundStyle(Theme.cream)
                }
                if i < tune.composers.count - 1 { Text(i == tune.composers.count - 2 ? "and" : ",").foregroundStyle(Theme.muted) }
            }
            Text("· \(String(tune.year))").foregroundStyle(Theme.muted)
        }
        .font(.system(size: compact ? 15 : 17, weight: .semibold))
    }

    private func header(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.brass).frame(width: 22, height: 4)
                Text(title.uppercased()).font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
            }
            if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted) }
        }
    }

    private func versionRow(_ v: TuneVersion) -> some View {
        let t = library.track(for: v, of: tune)
        let era = library.era(of: v)
        let current = t.map { player.isCurrent($0.id) } ?? false
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if let t { player.play(t.track) } else { player.searchInMusic("\(v.artistName) \(v.title ?? tune.title)") }
            } label: {
                ZStack {
                    RemoteImage(url: t?.track.artwork(300)) { Theme.panelHi }
                        .frame(width: compact ? 52 : 60, height: compact ? 52 : 60).clipShape(RoundedRectangle(cornerRadius: 4))
                    Image(systemName: t == nil ? "magnifyingglass" : (current && player.isPlaying ? "speaker.wave.2.fill" : "play.fill"))
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white).shadow(radius: 3)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(t == nil ? "Search Apple Music for this version" : "Play this version")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(String(v.year)).font(Theme.label(12)).foregroundStyle(era?.tint ?? Theme.brass)
                    if let id = v.artist, library.artist(id) != nil {
                        Button(v.artistName) { openArtist(id) }.buttonStyle(.plain).foregroundStyle(Theme.cream)
                    } else {
                        Text(v.artistName).foregroundStyle(Theme.cream)
                    }
                    if v.isLandmark { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(Theme.brass) }
                }
                .font(.system(size: 14, weight: .semibold))
                if let title = v.title { Text("as “\(title)”").font(.system(size: 12)).italic().foregroundStyle(Theme.muted) }
                Text(v.note).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if let id = v.album ?? t?.album, let album = library.album(id) {
                    Button("On \(album.title)") { openAlbum(id) }.buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(era?.tint ?? Theme.brass)
                } else if let rec = t?.track.albumName {
                    Text("On \(rec)").font(.system(size: 12)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private func playInOrder(_ tracks: [StationTrack]) {
        guard !tracks.isEmpty else { return }
        let station = Station(kind: .tune(tune.id), title: tune.title, subtitle: "Every version, oldest first", color: "#E9B949")
        player.playStation(station, tracks: tracks) { [] }
    }
}
