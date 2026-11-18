import SwiftUI

/// A chronological network: x = when each artist came of age, y = settled by a force simulation so collaborators
/// cluster together. Lines are ties (records together, bonds); the more records two artists share, the thicker the
/// line. Click a face to light up their circle, a second face to see what ties them, or find the chain between any two.
struct ConnectionsView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @Environment(PlayerController.self) private var player
    @State private var layout: GraphLayout?
    @State private var selected: String?
    /// A second artist, tied to the selected one: the panel shows what ties them.
    @State private var pair: String?
    @State private var hovered: String?
    @State private var zoom: CGFloat = 0.8
    @State private var path: [PathStep]?
    @State private var showFinder = false
    @State private var finder = PathRequest(from: "scott-joplin", to: "nubya-garcia")
    @State private var noPath = false
    @State private var loadingPath = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let layout {
                ScrollView([.horizontal, .vertical]) {
                    graph(layout)
                        .scaleEffect(zoom, anchor: .topLeading)
                        .frame(width: layout.size.width * zoom, height: layout.size.height * zoom, alignment: .topLeading)
                }
                .background(Theme.ink)
            } else {
                ProgressView("Drawing the family tree…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    Button { finder = PathRequest(from: selected ?? finder.from, to: pair ?? finder.to); showFinder = true } label: {
                        Label("Find a Path", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.cream)
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(Capsule().fill(.ultraThinMaterial))
                    HStack(spacing: 10) {
                        Image(systemName: "minus.magnifyingglass")
                        Slider(value: $zoom, in: 0.35...1.6).frame(width: 140)
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .foregroundStyle(Theme.muted)
                    .padding(10).background(Capsule().fill(.ultraThinMaterial))
                }

                if let path {
                    panel {
                        HStack {
                            Text("FROM \(name(path.first?.from)) TO \(name(path.last?.to))".uppercased())
                                .font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.brass).lineLimit(2)
                            Spacer()
                            closeButton { self.path = nil }
                        }
                        Text("\(path.count) link\(path.count == 1 ? "" : "s")").font(Theme.display(26)).foregroundStyle(Theme.cream)
                        ScrollView { PathStepsList(steps: path, openArtist: { router.go(.artist($0)) }, openAlbum: { router.go(.album($0)) }) }
                            .frame(maxHeight: 360)
                        Button { play(path) } label: {
                            Label(loadingPath ? "Finding the tracks…" : "Play the Path", systemImage: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .foregroundStyle(Theme.ink).background(Capsule().fill(Theme.brass))
                        }
                        .buttonStyle(.plain)
                        .disabled(loadingPath)
                        .help("One track from each link, in order")
                    }
                } else if let a = selected, let b = pair, let tie = library.tie(a, b) {
                    panel {
                        HStack { Spacer(); closeButton { pair = nil } }
                        TieDetails(tie: tie, openArtist: { router.go(.artist($0)) }, openAlbum: { router.go(.album($0)) })
                    }
                } else if let id = selected ?? hovered, let a = library.artist(id) {
                    SelectedArtistPanel(artist: a, pinned: selected != nil) { selected = nil }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(20)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONNECTIONS").font(Theme.display(44)).foregroundStyle(Theme.cream)
                Text("Who played with whom. Left to right: when each artist came of age; the thicker the line, the more records together. Click a face to trace their circle, then another to see what ties them.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: 460, alignment: .leading)
            }
            .padding(20)
            .background(LinearGradient(colors: [Theme.ink, Theme.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
        }
        .navigationTitle("Connections")
        .sheet(isPresented: $showFinder) { finderSheet }
        .onChange(of: router.connectionsFocus, initial: true) {
            // A connections/<artist> link: select that artist.
            if let focus = router.connectionsFocus {
                selected = focus; pair = nil; path = nil
                router.connectionsFocus = nil
            }
        }
        .onChange(of: router.pathRequest, initial: true) {
            // A between/<a>/<b> link: draw the chain.
            if let request = router.pathRequest {
                router.pathRequest = nil
                findPath(request)
            }
        }
        .task {
            if layout == nil {
                let artists = library.connectedArtists, ties = library.ties
                let edges = ties.map { ($0.a, $0.b) }, weights = ties.map(\.weight)
                let eras = Dictionary(library.eras.map { ($0.id, $0.start) }, uniquingKeysWith: { a, _ in a })
                layout = await Task.detached {
                    GraphLayout.compute(artists: artists, edges: edges, weights: weights, eraStarts: eras)
                }.value
            }
        }
    }

    // MARK: The map

    @ViewBuilder
    private func graph(_ g: GraphLayout) -> some View {
        let onPath = Set(path.map { $0.flatMap { [$0.from, $0.to] } } ?? [])
        let focus = path == nil ? (selected ?? hovered) : nil
        let lit: Set<String> = path != nil ? onPath : (focus.map { library.neighbors(of: $0).union([$0]) } ?? [])
        let pathTies = Set((path ?? []).map(\.tie.id))
        ZStack(alignment: .topLeading) {
            // Decade axis
            ForEach(g.decades, id: \.self) { d in
                let x = g.x(forYear: d)
                Rectangle().fill(Theme.panelHi.opacity(0.6)).frame(width: 1, height: g.size.height - 200).offset(x: x, y: 200)
                Text("\(String(d))s").font(Theme.label(11)).foregroundStyle(Theme.faint).offset(x: x + 5, y: 204)
            }
            // Era ribbon
            ForEach(library.eras) { e in
                let x0 = g.x(forYear: e.start), x1 = g.x(forYear: e.end)
                Capsule().fill(e.tint.opacity(0.5)).frame(width: max(8, x1 - x0), height: 6)
                    .offset(x: x0, y: 186)
                    .help(e.name)
            }
            // Ties
            Canvas { ctx, _ in
                let tint = focus.map { library.color(forEra: library.artist($0)?.primaryEra ?? "") } ?? Theme.cream
                for tie in library.ties {
                    guard let p = g.positions[tie.a], let q = g.positions[tie.b] else { continue }
                    let inPath = pathTies.contains(tie.id)
                    let isPair = selected != nil && pair != nil && tie.involves(selected!) && tie.involves(pair!)
                    let on = focus.map { tie.involves($0) } ?? false
                    // At rest, only the stronger ties: everyone's others appear when they're selected.
                    if !inPath && !on && !tie.prominent { continue }
                    var line = Path()
                    line.move(to: p)
                    let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 - abs(q.x - p.x) * 0.12)
                    line.addQuadCurve(to: q, control: mid)
                    let width = 0.8 + 0.7 * CGFloat(min(tie.weight, 5))
                    if inPath {
                        ctx.stroke(line, with: .color(Theme.brass), lineWidth: width + 2.5)
                    } else if isPair {
                        ctx.stroke(line, with: .color(tint), lineWidth: width + 3)
                    } else {
                        let dimmed = path != nil || (focus != nil && !on)
                        ctx.stroke(line, with: .color((on ? tint : Theme.cream).opacity(on ? 0.85 : (dimmed ? 0.04 : 0.13))),
                                   lineWidth: on ? width + 1 : width)
                    }
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .allowsHitTesting(false)
            // Faces
            ForEach(library.connectedArtists) { a in
                if let p = g.positions[a.id] {
                    let state: GraphNode.State = {
                        if path != nil { return onPath.contains(a.id) ? .lit : .dim }
                        guard let focus else { return .normal }
                        return a.id == focus || a.id == pair ? .focus : (lit.contains(a.id) ? .lit : .dim)
                    }()
                    GraphNode(artist: a, tint: library.color(forEra: a.primaryEra), state: state)
                        // Before .position: a positioned view fills the whole graph, so hover there would always hit
                        // the last node drawn.
                        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h ? a.id : (hovered == a.id ? nil : hovered) } }
                        .onTapGesture(count: 2) { router.go(.artist(a.id)) }
                        .onTapGesture { withAnimation(.spring(response: 0.3)) { tap(a.id) } }
                        .position(p)
                }
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
    }

    /// A first click selects; a click on someone tied to the selected artist shows their tie; anything else starts over.
    private func tap(_ id: String) {
        path = nil
        if let s = selected, s != id, library.tie(s, id) != nil {
            pair = (pair == id ? nil : id)
        } else {
            selected = (selected == id ? nil : id)
            pair = nil
        }
    }

    // MARK: Paths

    private var finderSheet: some View {
        let people = library.connectedArtists.sorted { $0.name < $1.name }
        return VStack(alignment: .leading, spacing: 16) {
            Text("FIND A PATH").font(Theme.display(30)).foregroundStyle(Theme.cream)
            Text("The shortest chain of records and bonds between two artists.").font(.system(size: 13)).foregroundStyle(Theme.muted)
            Picker("From", selection: Binding(get: { finder.from }, set: { finder = PathRequest(from: $0, to: finder.to) })) {
                ForEach(people) { Text($0.name).tag($0.id) }
            }
            Picker("To", selection: Binding(get: { finder.to }, set: { finder = PathRequest(from: finder.from, to: $0) })) {
                ForEach(people) { Text($0.name).tag($0.id) }
            }
            if noPath {
                Text("These two aren't connected in the guide.").font(.system(size: 12)).foregroundStyle(Theme.brass)
            }
            HStack {
                Spacer()
                Button("Cancel") { showFinder = false }.keyboardShortcut(.cancelAction)
                Button("Find Path") { findPath(finder) }.keyboardShortcut(.defaultAction).disabled(finder.from == finder.to)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Theme.panel)
    }

    private func findPath(_ request: PathRequest) {
        guard let steps = library.path(from: request.from, to: request.to) else { noPath = true; return }
        noPath = false
        showFinder = false
        withAnimation(.spring(response: 0.35)) {
            selected = nil; pair = nil
            path = steps
        }
    }

    private func play(_ steps: [PathStep]) {
        loadingPath = true
        Task {
            let tracks = await PathMusic.tracks(for: steps, library: library)
            loadingPath = false
            if !tracks.isEmpty { player.play(tracks) }
        }
    }

    // MARK: Pieces

    private func name(_ id: String?) -> String { id.flatMap { library.artist($0)?.name } ?? "" }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { content() }
            .padding(16)
            .frame(width: 340, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.brass.opacity(0.35)))
            .transition(.opacity.combined(with: .move(edge: .trailing)))
    }

    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.faint)
    }
}

struct GraphNode: View {
    enum State { case normal, focus, lit, dim }
    let artist: Artist
    let tint: Color
    let state: State

    var body: some View {
        let size: CGFloat = state == .focus ? 76 : 56
        VStack(spacing: 4) {
            ArtistPortrait(artist: artist, tint: tint, duotone: state != .focus)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(tint, lineWidth: state == .normal ? 2 : 3))
                .shadow(color: tint.opacity(state == .focus ? 0.8 : 0), radius: 16)
            Text(artist.name).font(.system(size: 11, weight: state == .focus ? .bold : .semibold))
                .foregroundStyle(state == .dim ? Theme.faint : Theme.cream)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Capsule().fill(Theme.ink.opacity(0.7)))
        }
        .opacity(state == .dim ? 0.28 : 1)
        .contentShape(Rectangle())
        .zIndex(state == .focus ? 2 : (state == .lit ? 1 : 0))
    }
}

struct SelectedArtistPanel: View {
    let artist: Artist
    let pinned: Bool
    let onClose: () -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let tint = library.color(forEra: artist.primaryEra)
        let ties = library.ties(of: artist.id)
        let records = Set(ties.flatMap(\.albums)).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ArtistPortrait(artist: artist, tint: tint, duotone: false)
                    .frame(width: 70, height: 86).clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name).font(Theme.display(26)).foregroundStyle(Theme.cream)
                    Text("\(artist.instrument) · \(artist.lifespan)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text("\(ties.count) connections · \(records) records").font(Theme.label(10)).foregroundStyle(tint)
                }
                Spacer()
                if pinned {
                    Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.faint)
                }
            }
            Text(artist.blurb).font(.system(size: 12)).foregroundStyle(Theme.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if pinned {
                Text("Click someone in their circle to see what ties them.").font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
            Button { router.go(.artist(artist.id)) } label: {
                Label("Open artist", systemImage: "arrow.right").font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .foregroundStyle(Theme.ink).background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.4)))
    }
}
