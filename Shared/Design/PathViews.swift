import SwiftUI

/// A path as a poster: its title on its colour, how many stops, and a progress ring once started.
struct JourneyCard: View {
    let path: JourneyPath
    var width: CGFloat? = 250
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        let p = passport.progress(on: path, library: library)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("\(p.total) STOPS").font(Theme.label(10)).tracking(1.4).foregroundStyle(Theme.ink.opacity(0.75))
                Spacer()
                if p.done > 0 {
                    ZStack {
                        Circle().stroke(Theme.ink.opacity(0.2), lineWidth: 4)
                        Circle().trim(from: 0, to: CGFloat(p.done) / CGFloat(max(p.total, 1)))
                            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                        if p.done == p.total { Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(Theme.ink) }
                    }
                    .frame(width: 26, height: 26)
                    .accessibilityLabel("\(p.done) of \(p.total) stops")
                }
            }
            Spacer(minLength: 0)
            Text(path.title.uppercased()).font(Theme.display(28)).foregroundStyle(Theme.ink).lineLimit(3).minimumScaleFactor(0.6)
            Text(path.subtitle).font(.system(size: 13, design: .serif)).italic().foregroundStyle(Theme.ink.opacity(0.8)).lineLimit(2)
        }
        .padding(16)
        .frame(width: width, height: 200, alignment: .topLeading)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(RoundedRectangle(cornerRadius: 14).fill(path.color.gradient))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// A path's page: the idea, then the route, numbered stops on a line in the path's colour, with your place kept.
struct PathDetailContent: View {
    let path: JourneyPath
    var compact = false
    var open: (PathStop) -> Void
    var openPath: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player

    var body: some View {
        let p = passport.progress(on: path, library: library)
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A PATH · \(path.stops.count) STOPS").font(Theme.label(11)).tracking(1.6).foregroundStyle(path.color)
                Text(path.title.uppercased()).font(Theme.display(compact ? 44 : 64)).foregroundStyle(Theme.cream)
                    .fixedSize(horizontal: false, vertical: true)
                Text(path.subtitle).font(Theme.serif(compact ? 17 : 20)).italic().foregroundStyle(Theme.muted)
            }
            Text(path.intro).font(.system(size: compact ? 16 : 17, design: .serif)).lineSpacing(4)
                .foregroundStyle(Theme.cream.opacity(0.9)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
            HStack(spacing: 12) {
                if let next = p.next {
                    Button { start(next) } label: {
                        Label(p.done == 0 ? "Start" : "Continue: stop \(next + 1)", systemImage: "play.fill").font(.system(size: 14, weight: .bold))
                            .padding(.horizontal, 18).padding(.vertical, 10)
                            .foregroundStyle(Theme.ink).background(Capsule().fill(path.color))
                    }
                    .buttonStyle(.plain)
                } else {
                    Label("Path complete", systemImage: "checkmark.seal.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(path.color)
                }
                Text("\(p.done) of \(p.total) done").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(path.stops.enumerated()), id: \.offset) { i, stop in
                    stopRow(i, stop, isNext: p.next == i, isLast: i == path.stops.count - 1)
                }
            }
            Text(path.outro).font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
            let next = path.next.compactMap { library.journey($0) }
            if !next.isEmpty {
                HStack(spacing: 12) {
                    ForEach(next) { n in
                        Button { openPath(n.id) } label: { JourneyCard(path: n, width: compact ? 160 : 220) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func stopRow(_ i: Int, _ stop: PathStop, isNext: Bool, isLast: Bool) -> some View {
        let done = passport.isDone(stop, on: path, library: library)
        let info = library.title(of: stop)
        let note = stop.note ?? (stop.kind == .album ? library.album(stop.ref)?.why : nil)
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? path.color : Theme.panel).frame(width: 34, height: 34)
                    Circle().strokeBorder(path.color, lineWidth: 2).frame(width: 34, height: 34)
                    if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .black)).foregroundStyle(Theme.ink) }
                    else { Text(String(format: "%02d", i + 1)).font(Theme.display(15)).foregroundStyle(path.color) }
                }
                if !isLast { Rectangle().fill(path.color.opacity(0.5)).frame(width: 2).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    artwork(stop)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kindLabel(stop.kind)).font(Theme.label(9)).tracking(1.2).foregroundStyle(Theme.muted)
                        Button { tick(stop); open(stop) } label: {
                            Text(info.title).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.cream).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        Text(info.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                if let note, isNext || !compact {
                    Text(note).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.cream.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 14) {
                    if let t = library.playable(stop) {
                        Button { PathPlayback.play(i, of: path, library: library, player: player) } label: { Label("Play \(t.title)", systemImage: "play.fill") }
                            .buttonStyle(.plain).foregroundStyle(path.color)
                    }
                    Button {
                        passport.setStop(stop.key, of: path.id, done: !passport.isTicked(stop.key, of: path.id))
                    } label: {
                        Label(done ? "Done" : "Mark as done", systemImage: done ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain).foregroundStyle(done ? path.color : Theme.muted)
                    .disabled(done && !passport.isTicked(stop.key, of: path.id))
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .padding(.bottom, 22)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(isNext ? Theme.panel : .clear))
        }
        .frame(maxWidth: 720, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func artwork(_ stop: PathStop) -> some View {
        switch stop.kind {
        case .album:
            if let a = library.album(stop.ref) { AlbumCover(album: a, size: 200, cornerRadius: 4).frame(width: 52, height: 52) }
        case .track:
            RemoteImage(url: library.tracks[stop.ref]?.track.artwork(200)) { Theme.panelHi }
                .frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 4))
        case .artist:
            if let a = library.artist(stop.ref) {
                ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra)).frame(width: 52, height: 52).clipShape(Circle())
            }
        default:
            Image(systemName: symbol(stop.kind)).font(.system(size: 20)).foregroundStyle(path.color)
                .frame(width: 52, height: 52).background(RoundedRectangle(cornerRadius: 8).fill(Theme.panelHi))
        }
    }

    private func kindLabel(_ k: PathStop.Kind) -> String {
        switch k {
        case .album: return "RECORD"
        case .track: return "TRACK"
        case .tune: return "TUNE"
        case .term: return "WORD"
        case .era: return "ERA"
        case .artist: return "ARTIST"
        case .place: return "PLACE"
        }
    }

    private func symbol(_ k: PathStop.Kind) -> String {
        switch k {
        case .tune: return "music.quarternote.3"
        case .term: return "character.book.closed.fill"
        case .era: return "square.stack.3d.up.fill"
        case .place: return "mappin.and.ellipse"
        default: return "music.note"
        }
    }

    /// Reading a stop that's only read (a term, a tune, an era, a place, an artist) counts as doing it.
    private func tick(_ stop: PathStop) {
        guard ![.album, .track].contains(stop.kind), !passport.isTicked(stop.key, of: path.id) else { return }
        passport.setStop(stop.key, of: path.id, done: true)
    }

    private func start(_ index: Int) {
        let stop = path.stops[index]
        if !PathPlayback.play(index, of: path, library: library, player: player) { tick(stop); open(stop) }
    }
}

/// The path you're on, then the others: for the home screen.
struct PathsRow: View {
    var cardWidth: CGFloat? = 230
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        let current = passport.currentPath(library: library)
        let others = library.paths.filter { $0.id != current?.id }
        ForEach([current].compactMap { $0 } + others) { p in
            Button { open(p.id) } label: { JourneyCard(path: p, width: cardWidth) }.buttonStyle(.plain)
        }
    }
}

/// Finished paths, for the Passport page.
struct PathStamps: View {
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        let finished = library.paths.filter { passport.isFinished($0, library: library) }
        if !finished.isEmpty {
            FlowLayout(spacing: 10) {
                ForEach(finished) { p in
                    Button { open(p.id) } label: {
                        Label(p.title, systemImage: "checkmark.seal.fill").font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .foregroundStyle(Theme.ink).background(Capsule().fill(p.color))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// In the player, when what's playing came from a path: the stop after it. Plays it, or opens it when it's a stop to
/// read (and ticks it, as opening it from the path page does).
struct NextStopButton: View {
    var open: (Route) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let ref = player.pathStop, let (path, i) = PathPlayback.after(ref, library: library, passport: passport) {
            let stop = path.stops[i]
            Button {
                if !PathPlayback.play(i, of: path, library: library, player: player) {
                    if ![.album, .track].contains(stop.kind) { passport.setStop(stop.key, of: path.id, done: true) }
                    if let r = Route(stop: stop, library: library) { open(r) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: library.playable(stop) == nil ? "arrow.right.circle.fill" : "forward.end.fill")
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(path.title.uppercased()) · NEXT STOP \(i + 1) OF \(path.stops.count)").font(Theme.label(9))
                            .tracking(1.1).foregroundStyle(path.color).lineLimit(1)
                        Text(library.title(of: stop).title).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.cream).lineLimit(1)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Capsule().fill(path.color.opacity(0.18)))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
