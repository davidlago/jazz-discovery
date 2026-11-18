import SwiftUI

// MARK: - Lineages

/// A lineage as a card: overlapping faces from its tree, the instrument's name and how many players.
struct LineageCard: View {
    let lineage: Lineage
    var width: CGFloat? = 240
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let faces = lineage.players.prefix(5).compactMap { library.artist($0.artist) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: -14) {
                ForEach(faces) { a in
                    ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra))
                        .frame(width: 46, height: 46).clipShape(Circle())
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                }
            }
            Text(lineage.title.uppercased()).font(Theme.display(26)).foregroundStyle(Theme.cream).lineLimit(1).minimumScaleFactor(0.6)
            Text("\(lineage.players.count) players · \(lineage.links.count) lines").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// The tree: faces placed by when each player came of age, lines for who came from whom. Selecting a face lights its
/// roots and heirs.
struct LineageTree: View {
    let lineage: Lineage
    @Binding var selected: String?
    var playing: String? = nil
    @Environment(JazzLibrary.self) private var library
    private let pxPerYear: CGFloat = 10
    private let laneHeight: CGFloat = 96
    private let face: CGFloat = 54

    var body: some View {
        let layout = LineageLayout(lineage: lineage, library: library)
        let width = CGFloat(layout.maxYear - layout.minYear) * pxPerYear + 160
        let height = CGFloat(layout.lanes) * laneHeight + 40
        let pos = { (id: String) -> CGPoint? in
            layout.node(id).map { CGPoint(x: CGFloat(Int($0.x) - layout.minYear) * pxPerYear + 70, y: CGFloat($0.lane) * laneHeight + 50) }
        }
        let lit: Set<String> = selected.map { s in
            Set(lineage.links.filter { $0.from == s || $0.to == s }.flatMap { [$0.from, $0.to] }).union([s])
        } ?? []
        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                // Decades along the top.
                ForEach(Array(stride(from: (layout.minYear / 10) * 10, through: layout.maxYear, by: 10)), id: \.self) { d in
                    Text("\(String(d))s").font(Theme.label(9)).foregroundStyle(Theme.faint)
                        .position(x: CGFloat(d - layout.minYear) * pxPerYear + 70, y: 8)
                }
                Canvas { ctx, _ in
                    for link in lineage.links {
                        guard let a = pos(link.from), let b = pos(link.to) else { continue }
                        var path = Path()
                        path.move(to: a)
                        path.addCurve(to: b, control1: CGPoint(x: (a.x + b.x) / 2, y: a.y), control2: CGPoint(x: (a.x + b.x) / 2, y: b.y))
                        let on = selected == nil || (lit.contains(link.from) && lit.contains(link.to) && (link.from == selected || link.to == selected))
                        let color = (library.artist(link.to).map { library.color(forEra: $0.primaryEra) } ?? Theme.brass).opacity(on ? 0.9 : 0.15)
                        let style: StrokeStyle = switch link.kind {
                        case .reaction: StrokeStyle(lineWidth: 2, dash: [6, 5])
                        case .teacher: StrokeStyle(lineWidth: 4)
                        default: StrokeStyle(lineWidth: 2)
                        }
                        ctx.stroke(path, with: .color(color), style: style)
                    }
                }
                .frame(width: width, height: height)
                ForEach(lineage.players, id: \.artist) { p in
                    if let a = library.artist(p.artist), let at = pos(p.artist) {
                        Button { selected = selected == p.artist ? nil : p.artist } label: {
                            VStack(spacing: 4) {
                                ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra))
                                    .frame(width: face, height: face).clipShape(Circle())
                                    .overlay(Circle().strokeBorder(playing == p.artist ? Theme.cream : library.color(forEra: a.primaryEra),
                                                                   lineWidth: playing == p.artist || selected == p.artist ? 3 : 1.5))
                                Text(a.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.cream)
                                    .lineLimit(1).fixedSize()
                            }
                            .opacity(selected == nil || lit.contains(p.artist) ? 1 : 0.35)
                        }
                        .buttonStyle(.plain)
                        .position(x: at.x, y: at.y + 10)
                        .accessibilityLabel("\(a.name): \(p.idea)")
                    }
                }
            }
            .frame(width: width, height: height)
        }
    }
}

/// A lineage's page: the story, the tree, the selected player's idea and lines, and the line as a list.
struct LineageDetailContent: View {
    let lineage: Lineage
    var compact = false
    var openArtist: (String) -> Void
    @State private var selected: String?
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        let ordered = lineage.players.sorted { library.comingOfAge($0.artist) < library.comingOfAge($1.artist) }
        let playing = player.station?.id == "lineage-\(lineage.id)" ? player.currentStationTrack.flatMap { t in
            ordered.first { $0.track == t.ref }?.artist } : nil
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(lineage.family.uppercased()).font(Theme.label(11)).tracking(1.6).foregroundStyle(Theme.brass)
                Text(lineage.title.uppercased()).font(Theme.display(compact ? 44 : 64)).foregroundStyle(Theme.cream)
            }
            ForEach(lineage.intro.components(separatedBy: "\n\n"), id: \.self) { p in
                Text(p).font(.system(size: compact ? 16 : 17, design: .serif)).lineSpacing(4).foregroundStyle(Theme.cream.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 700, alignment: .leading)
            }
            Button { playLineage(ordered) } label: {
                Label("Play the Lineage", systemImage: "play.fill").font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
            }
            .buttonStyle(.plain)
            LineageTree(lineage: lineage, selected: $selected, playing: playing)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel.opacity(0.6)))
            if let id = selected, let a = library.artist(id), let p = lineage.player(id) {
                selectedPanel(a, p)
            } else {
                Text("Select a face to see what they brought, and where it came from.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Rectangle().fill(Theme.brass).frame(width: 22, height: 4)
                    Text("THE LINE").font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
                }
                ForEach(ordered, id: \.artist) { p in
                    if let a = library.artist(p.artist) { lineRow(a, p) }
                }
            }
        }
    }

    private func selectedPanel(_ a: Artist, _ p: LineagePlayer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(a.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.cream)
                Spacer()
                Button("Open artist") { openArtist(a.id) }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brass)
            }
            Text(p.idea).font(.system(size: 15, design: .serif)).italic().foregroundStyle(Theme.cream.opacity(0.9))
            ForEach(lineage.links.filter { $0.from == a.id || $0.to == a.id }) { l in
                let other = library.artist(l.from == a.id ? l.to : l.from)?.name ?? ""
                Text("\(l.from == a.id ? "Led to" : "Came from") \(other) · \(l.kindText): \(l.note)")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let ref = p.track, let t = library.tracks[ref] {
                Button { player.play(t.track) } label: {
                    Label("\(t.title) (\(Programmer.year(t, library: library).map { String($0) } ?? ""))", systemImage: "play.circle.fill")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brass)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: 700, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
    }

    private func lineRow(_ a: Artist, _ p: LineagePlayer) -> some View {
        let t = p.track.flatMap { library.tracks[$0] }
        return HStack(alignment: .top, spacing: 12) {
            Button { openArtist(a.id) } label: {
                ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra)).frame(width: 44, height: 44).clipShape(Circle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                Text(a.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.cream)
                Text(p.idea).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(lineage.links.filter { $0.to == a.id }) { l in
                    Text("From \(library.artist(l.from)?.name ?? l.from): \(l.note)").font(.system(size: 12)).italic()
                        .foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                if let t {
                    Button { player.play(t.track) } label: { Label(t.title, systemImage: "play.fill") }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(library.color(forEra: a.primaryEra))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private func playLineage(_ ordered: [LineagePlayer]) {
        let tracks = ordered.compactMap { $0.track.flatMap { library.tracks[$0] } }
        guard !tracks.isEmpty else { return }
        let station = Station(kind: .lineage(lineage.id), title: lineage.title, subtitle: "One track per player, in order", color: "#E9B949")
        player.playStation(station, tracks: tracks) { [] }
    }
}

/// On an artist's page: who they came from and who came from them, with why.
struct ArtistLineageStrip: View {
    let artist: Artist
    var openArtist: (String) -> Void
    var openLineage: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let roots = library.roots(of: artist.id)
        let heirs = library.heirs(of: artist.id)
        if !roots.isEmpty || !heirs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(roots) { l in row("Came from", l.from, l) }
                ForEach(heirs) { l in row("Led to", l.to, l) }
                ForEach(library.lineages(including: artist.id)) { lin in
                    Button("The whole tree: \(lin.title) →") { openLineage(lin.id) }.buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brass)
                }
            }
        }
    }

    private func row(_ label: String, _ id: String, _ link: LineageLink) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let a = library.artist(id) {
                Button { openArtist(id) } label: {
                    ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra)).frame(width: 36, height: 36).clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label.uppercased()) · \(library.artist(id)?.name.uppercased() ?? "")").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.brass)
                Text(link.note).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.cream.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

// MARK: - Glossary

/// Prose with its glossary terms underlined; tapping one opens the term.
struct TermText: View {
    let text: String
    var font: Font = .system(size: 17, design: .serif)
    var color: Color = Theme.cream.opacity(0.9)
    var openTerm: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        Text(library.termLinker.attributed(text))
            .font(font).foregroundStyle(color).tint(Theme.brass)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "jazzdiscovery", url.host() == "term" else { return .systemAction }
                openTerm(url.lastPathComponent)
                return .handled
            })
    }
}

/// The glossary: terms by category, dictionary style, with a filter.
struct GlossaryList: View {
    var openTerm: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var query = ""
    static let categories = ["Form", "Rhythm", "Harmony", "Sound", "Roles", "Slang"]

    var body: some View {
        let q = query.lowercased()
        let terms = library.terms.filter { q.isEmpty || $0.term.lowercased().contains(q) || $0.short.lowercased().contains(q) }
        VStack(alignment: .leading, spacing: 22) {
            TextField("Find a term", text: $query)
                .textFieldStyle(.plain)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
                .frame(maxWidth: 360)
            ForEach(Self.categories, id: \.self) { c in
                let inCat = terms.filter { $0.category == c }
                if !inCat.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(c.uppercased()).font(Theme.label(12)).tracking(1.6).foregroundStyle(Theme.brass)
                        ForEach(inCat) { t in entry(t) }
                    }
                }
            }
        }
    }

    private func entry(_ t: GlossaryTerm) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { openTerm(t.id) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.term).font(.system(size: 18, weight: .bold, design: .serif)).foregroundStyle(Theme.cream)
                    Text(t.short).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.cream.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let ex = t.examples.first, let track = library.tracks[ex.track] {
                Button { player.play(track.track) } label: { Image(systemName: "play.circle.fill").font(.system(size: 22)) }
                    .buttonStyle(.plain).foregroundStyle(Theme.brass)
                    .accessibilityLabel("Hear \(t.term)")
            }
        }
    }
}

/// A term's page: headword, definition, recordings to hear it in, related terms, and where it shows up.
struct TermDetailContent: View {
    let term: GlossaryTerm
    var compact = false
    var openTerm: (String) -> Void
    var openEra: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        let linker = library.termLinker
        let eras = library.eras.filter { e in linker.links(in: e.summary).contains { $0.id == term.id } }
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(term.category.uppercased()).font(Theme.label(11)).tracking(1.6).foregroundStyle(Theme.brass)
                Text(term.term).font(.system(size: compact ? 42 : 60, weight: .bold, design: .serif)).foregroundStyle(Theme.cream)
                Text(term.short).font(.system(size: compact ? 18 : 20, design: .serif)).italic().foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            TermText(text: term.long, font: .system(size: compact ? 16 : 17, design: .serif), openTerm: openTerm)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 680, alignment: .leading)
            VStack(alignment: .leading, spacing: 12) {
                Text("HEAR IT").font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
                ForEach(term.examples, id: \.track) { ex in
                    if let t = library.tracks[ex.track] {
                        Button { player.play(t.track) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                RemoteImage(url: t.track.artwork(200)) { Theme.panelHi }.frame(width: 48, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(Image(systemName: "play.fill").foregroundStyle(.white).shadow(radius: 2))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(t.title) · \(t.artistName)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
                                    Text(ex.note).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.cream.opacity(0.8))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: 680, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !term.related.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(term.related.compactMap { library.term($0) }) { r in
                        Button { openTerm(r.id) } label: {
                            Text(r.term).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 11).padding(.vertical, 6)
                                .foregroundStyle(Theme.brass).background(Capsule().fill(Theme.brass.opacity(0.14)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !eras.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("WHERE IT SHOWS UP").font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.muted)
                    FlowLayout(spacing: 8) {
                        ForEach(eras) { e in
                            Button { openEra(e.id) } label: {
                                Text(e.name).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                                    .foregroundStyle(e.tint).background(Capsule().fill(e.tint.opacity(0.14)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

/// How to Listen: five steps through one recording.
struct HowToListenCard: View {
    var openTerm: (String) -> Void
    /// Opens the recording's listening guide, when it has one.
    var openGuide: ((String) -> Void)? = nil
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        let steps = library.glossary.howToListen
        if !steps.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("HOW TO LISTEN").font(Theme.display(28)).foregroundStyle(Theme.cream)
                    Spacer()
                    if let ref = library.glossary.howToListenTrack, let t = library.tracks[ref] {
                        Button { player.play(t.track) } label: {
                            Label("Play \(t.title)", systemImage: "play.fill").font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let openGuide, let ref = library.glossary.howToListenTrack, let g = library.guide(forTrack: ref) {
                    Button { openGuide(g.id) } label: {
                        Label("Then follow the whole recording, section by section, with its listening guide", systemImage: "list.bullet.rectangle.portrait")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brass)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    HStack(alignment: .top, spacing: 12) {
                        Text(String(format: "%02d", i + 1)).font(Theme.display(26)).foregroundStyle(Theme.brass)
                        VStack(alignment: .leading, spacing: 3) {
                            Button(s.title) { openTerm(s.term) }.buttonStyle(.plain)
                                .font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cream)
                            Text(s.text).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.cream.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.panel))
        }
    }
}
