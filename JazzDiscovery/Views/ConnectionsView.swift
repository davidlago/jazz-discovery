import SwiftUI

/// A chronological network: x = when each artist came of age, y = settled by a force
/// simulation so collaborators cluster together.
struct ConnectionsView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var layout: GraphLayout?
    @State private var selected: String?
    @State private var hovered: String?
    @State private var zoom: CGFloat = 0.8

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
                HStack(spacing: 10) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: $zoom, in: 0.45...1.6).frame(width: 140)
                    Image(systemName: "plus.magnifyingglass")
                }
                .foregroundStyle(Theme.muted)
                .padding(10).background(Capsule().fill(.ultraThinMaterial))

                if let id = selected ?? hovered, let a = library.artist(id) {
                    SelectedArtistPanel(artist: a, pinned: selected != nil) { selected = nil }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .padding(20)
        }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CONNECTIONS").font(Theme.display(44)).foregroundStyle(Theme.cream)
                Text("Who played with whom. Left to right: when each artist came of age. Click a face to trace their circle.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted).frame(maxWidth: 420, alignment: .leading)
            }
            .padding(20)
            .background(LinearGradient(colors: [Theme.ink, Theme.ink.opacity(0)], startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
        }
        .navigationTitle("Connections")
        .task {
            if layout == nil {
                let artists = library.artists, edges = library.edges
                let eras = Dictionary(library.eras.map { ($0.id, $0.start) }, uniquingKeysWith: { a, _ in a })
                layout = await Task.detached { GraphLayout.compute(artists: artists, edges: edges, eraStarts: eras) }.value
            }
        }
    }

    @ViewBuilder
    private func graph(_ g: GraphLayout) -> some View {
        let focus = selected ?? hovered
        let lit: Set<String> = focus.map { library.neighbors(of: $0).union([$0]) } ?? []
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
            // Edges
            Canvas { ctx, _ in
                for (a, b) in g.edges {
                    guard let p = g.positions[a], let q = g.positions[b] else { continue }
                    let on = focus != nil && (a == focus || b == focus)
                    var path = Path()
                    path.move(to: p)
                    let mid = CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 - abs(q.x - p.x) * 0.12)
                    path.addQuadCurve(to: q, control: mid)
                    let color: Color = on ? library.color(forEra: library.artist(focus!)?.primaryEra ?? "") : Theme.cream
                    ctx.stroke(path, with: .color(color.opacity(on ? 0.9 : (focus == nil ? 0.14 : 0.05))), lineWidth: on ? 2.5 : 1)
                }
            }
            .frame(width: g.size.width, height: g.size.height)
            .allowsHitTesting(false)
            // Nodes
            ForEach(library.artists) { a in
                if let p = g.positions[a.id] {
                    GraphNode(artist: a, tint: library.color(forEra: a.primaryEra),
                              state: focus == nil ? .normal : (a.id == focus ? .focus : (lit.contains(a.id) ? .lit : .dim)))
                        .position(p)
                        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h ? a.id : (hovered == a.id ? nil : hovered) } }
                        .onTapGesture(count: 2) { router.go(.artist(a.id)) }
                        .onTapGesture { withAnimation(.spring(response: 0.3)) { selected = (selected == a.id ? nil : a.id) } }
                }
            }
        }
        .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
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
        let n = library.neighbors(of: artist.id).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                ArtistPortrait(artist: artist, tint: tint, duotone: false)
                    .frame(width: 70, height: 86).clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name).font(Theme.display(26)).foregroundStyle(Theme.cream)
                    Text("\(artist.instrument) · \(artist.lifespan)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Text("\(n) connections").font(Theme.label(10)).foregroundStyle(tint)
                }
                Spacer()
                if pinned {
                    Button(action: onClose) { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(Theme.faint)
                }
            }
            Text(artist.blurb).font(.system(size: 12)).foregroundStyle(Theme.cream.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
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

struct GraphLayout: Sendable {
    var positions: [String: CGPoint]
    var edges: [(String, String)]
    var size: CGSize
    var firstYear: Int
    var pxPerYear: CGFloat
    var leftPad: CGFloat

    var decades: [Int] { Array(stride(from: firstYear / 10 * 10 + 10, through: 2020, by: 10)) }
    func x(forYear y: Int) -> CGFloat { leftPad + CGFloat(y - firstYear) * pxPerYear }

    static func compute(artists: [Artist], edges: [(String, String)], eraStarts: [String: Int]) -> GraphLayout {
        func comingOfAge(_ a: Artist) -> Double {
            if let b = a.born { return Double(b + 22) }
            return Double(eraStarts[a.primaryEra] ?? 1950)
        }
        let years = artists.map(comingOfAge)
        let first = Int((years.min() ?? 1890) - 4)
        let last = Int((years.max() ?? 2020) + 4)
        let pxPerYear: CGFloat = 26
        let leftPad: CGFloat = 80
        let top: CGFloat = 260, height: CGFloat = 820
        let width = leftPad * 2 + CGFloat(last - first) * pxPerYear

        let ids = artists.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let n = ids.count
        let targetX = artists.map { leftPad + CGFloat(comingOfAge($0) - Double(first)) * pxPerYear }
        var px = targetX
        // Deterministic pseudo-random starting heights.
        var py: [CGFloat] = ids.map { id in
            var h: UInt64 = 1469598103934665603
            for c in id.utf8 { h = (h ^ UInt64(c)) &* 1099511628211 }
            return top + CGFloat(h % 1000) / 1000 * height
        }
        let links = edges.compactMap { e -> (Int, Int)? in
            guard let a = index[e.0], let b = index[e.1] else { return nil }
            return (a, b)
        }
        let centerY = top + height / 2
        for iter in 0..<500 {
            let cool = 1 - CGFloat(iter) / 500
            var fx = [CGFloat](repeating: 0, count: n), fy = [CGFloat](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = px[i] - px[j], dy = py[i] - py[j]
                    let d2 = max(dx * dx + dy * dy, 25)
                    let d = d2.squareRoot()
                    guard d < 260 else { continue }
                    let f = 9000 / d2
                    fx[i] += f * dx / d; fy[i] += f * dy / d
                    fx[j] -= f * dx / d; fy[j] -= f * dy / d
                }
            }
            for (a, b) in links {
                let dx = px[b] - px[a], dy = py[b] - py[a]
                let d = max((dx * dx + dy * dy).squareRoot(), 1)
                let f = (d - 110) * 0.03
                fx[a] += f * dx / d; fy[a] += f * dy / d
                fx[b] -= f * dx / d; fy[b] -= f * dy / d
            }
            for i in 0..<n {
                fx[i] += (targetX[i] - px[i]) * 0.25      // stay true to chronology
                fy[i] += (centerY - py[i]) * 0.008        // gentle gravity
                px[i] += max(-12, min(12, fx[i])) * cool
                py[i] += max(-12, min(12, fy[i])) * cool
                py[i] = min(max(py[i], top), top + height)
            }
        }
        var pos: [String: CGPoint] = [:]
        for i in 0..<n { pos[ids[i]] = CGPoint(x: px[i], y: py[i]) }
        return GraphLayout(positions: pos, edges: edges, size: CGSize(width: width, height: top + height + 80),
                           firstYear: first, pxPerYear: pxPerYear, leftPad: leftPad)
    }
}
