import SwiftUI

/// Who played with whom: left to right is when each artist came of age, and lines are collaborations. Pan and pinch
/// around the map; tap a face to light up their circle.
struct ConnectionsMapView: View {
    let focus: String?
    @Environment(JazzLibrary.self) private var library
    @State private var layout: GraphLayout?
    @State private var selected: String?
    @State private var camera = MapCamera()
    /// The whole screen (the map runs under the bars) and the bars' insets.
    @State private var viewport: CGSize = .zero
    @State private var insets = EdgeInsets()
    @State private var placed = false

    var body: some View {
        // The reader sits inside the bars, so its insets are the bars' (and the card's below); the map itself is drawn
        // over the whole screen, shifted back up under the navigation bar.
        GeometryReader { geo in
            let i = geo.safeAreaInsets
            let full = CGSize(width: geo.size.width + i.leading + i.trailing, height: geo.size.height + i.top + i.bottom)
            ZStack {
                Theme.ink
                if let layout {
                    GraphMap(layout: layout, selected: $selected, camera: $camera, viewport: full, topInset: i.top)
                } else {
                    ProgressView("Drawing the family tree…").tint(Theme.brass).foregroundStyle(Theme.muted)
                }
            }
            .frame(width: full.width, height: full.height)
            .offset(x: -i.leading, y: -i.top)
            .onAppear { measured(full, i) }
            .onChange(of: full) { measured(full, i) }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Group {
                if let id = selected, let a = library.artist(id) {
                    SelectedArtistCard(artist: a) { withAnimation(.spring(response: 0.3)) { selected = nil } }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if layout != nil {
                    Label("Pinch to zoom · Tap a face to trace their circle", systemImage: "hand.tap")
                        .font(.footnote.weight(.medium)).foregroundStyle(Theme.cream.opacity(0.85))
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 10)
        }
        .background(Theme.ink)
        .navigationTitle("Connections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { withAnimation(.spring(response: 0.5)) { fit() } } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Show the whole map")
                .disabled(layout == nil)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .task {
            guard layout == nil else { return }
            let artists = library.artists, edges = library.edges
            let eras = Dictionary(library.eras.map { ($0.id, $0.start) }, uniquingKeysWith: { a, _ in a })
            layout = await Task.detached { GraphLayout.compute(artists: artists, edges: edges, eraStarts: eras) }.value
            placeCamera()
        }
    }

    private func measured(_ full: CGSize, _ i: EdgeInsets) {
        viewport = full
        insets = i
        placeCamera()
    }

    /// Opens on the requested artist, or on the earliest players, at a zoom that shows the map's whole height.
    private func placeCamera() {
        guard !placed, let layout, viewport.width > 0 else { return }
        placed = true
        let b = GraphMap.bounds(layout)
        var z = min(1, max(MapCamera.minZoom, (viewport.height - insets.top - insets.bottom - 60) / b.height))
        if let focus, let p = layout.positions[focus] {
            // Close enough to read the names around them, centered above the artist's card.
            z = max(z, 0.85)
            camera.zoom = z
            camera.offset = CGPoint(x: viewport.width / 2 - p.x * z,
                                    y: insets.top + (viewport.height - insets.top - insets.bottom - 300) / 2 - p.y * z)
            selected = focus
        } else {
            // The middle of the crowd (the 1950s and 60s), close enough for names.
            z = max(z, 0.75)
            let xs = layout.positions.values.map(\.x).sorted()
            let midX = xs.isEmpty ? b.midX : xs[xs.count / 2]
            camera.zoom = z
            camera.offset = CGPoint(x: viewport.width / 2 - midX * z,
                                    y: insets.top + (viewport.height - insets.top - insets.bottom - b.height * z) / 2 - b.minY * z)
        }
        camera = GraphMap.clamped(camera, layout: layout, viewport: viewport)
    }

    private func fit() {
        guard let layout else { return }
        let b = GraphMap.bounds(layout)
        let usable = viewport.height - insets.top - insets.bottom
        let z = max(MapCamera.minZoom, min((viewport.width - 40) / b.width, (usable - 40) / b.height))
        camera.zoom = z
        camera.offset = CGPoint(x: (viewport.width - b.width * z) / 2 - b.minX * z,
                                y: insets.top + (usable - b.height * z) / 2 - b.minY * z)
    }
}

struct MapCamera: Equatable {
    static let minZoom: CGFloat = 0.14
    static let maxZoom: CGFloat = 1.5
    var zoom: CGFloat = 0.6
    /// Screen position of the map's origin.
    var offset: CGPoint = .zero

    func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * zoom + offset.x, y: p.y * zoom + offset.y) }
}

private struct GraphMap: View {
    let layout: GraphLayout
    @Binding var selected: String?
    @Binding var camera: MapCamera
    let viewport: CGSize
    let topInset: CGFloat
    @Environment(JazzLibrary.self) private var library
    @GestureState private var pan: CGSize = .zero
    @GestureState private var pinch: Pinch? = nil

    struct Pinch: Equatable { var scale: CGFloat; var anchor: CGPoint }

    /// The part of the map with artists in it (the layout leaves room at the top for the Mac's header).
    static func bounds(_ g: GraphLayout) -> CGRect {
        let xs = g.positions.values.map(\.x), ys = g.positions.values.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max() else {
            return CGRect(origin: .zero, size: g.size)
        }
        return CGRect(x: x0 - 70, y: y0 - 70, width: x1 - x0 + 140, height: y1 - y0 + 120)
    }

    /// Keeps the map on screen: it can't be pushed past its edges, and a map smaller than the screen stays centered.
    static func clamped(_ c: MapCamera, layout: GraphLayout, viewport: CGSize) -> MapCamera {
        var c = c
        c.zoom = min(MapCamera.maxZoom, max(MapCamera.minZoom, c.zoom))
        let b = bounds(layout)
        func axis(_ off: CGFloat, _ lo: CGFloat, _ len: CGFloat, _ view: CGFloat) -> CGFloat {
            let size = len * c.zoom
            // Smaller than the screen: it can move around as long as some of it stays across the middle.
            if size <= view { return min(view * 0.6 - lo * c.zoom, max(view * 0.4 - (lo + len) * c.zoom, off)) }
            return min(-lo * c.zoom + 40, max(view - (lo + len) * c.zoom - 40, off))
        }
        c.offset.x = axis(c.offset.x, b.minX, b.width, viewport.width)
        c.offset.y = axis(c.offset.y, b.minY, b.height, viewport.height)
        return c
    }

    /// The camera with the gestures in progress applied.
    private var live: MapCamera {
        var c = camera
        if let pinch {
            c.zoom = min(MapCamera.maxZoom * 1.15, max(MapCamera.minZoom * 0.85, camera.zoom * pinch.scale))
            let k = c.zoom / camera.zoom
            c.offset = CGPoint(x: pinch.anchor.x - (pinch.anchor.x - camera.offset.x) * k,
                               y: pinch.anchor.y - (pinch.anchor.y - camera.offset.y) * k)
        }
        c.offset.x += pan.width
        c.offset.y += pan.height
        return c
    }

    var body: some View {
        let cam = live
        let lit: Set<String> = selected.map { library.neighbors(of: $0).union([$0]) } ?? []
        let nodeSize = max(18, 56 * cam.zoom)
        let showNames = cam.zoom >= 0.72
        let visible = library.artists.filter { a in
            guard let p = layout.positions[a.id] else { return false }
            let s = cam.screen(p)
            return s.x > -80 && s.x < viewport.width + 80 && s.y > -80 && s.y < viewport.height + 80
        }

        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { withAnimation(.spring(response: 0.3)) { selected = nil } }

            Canvas { ctx, size in
                draw(in: &ctx, size: size, cam: cam)
            }
            .allowsHitTesting(false)

            ForEach(visible) { a in
                let state: GraphNode.State = selected == nil ? .normal : (a.id == selected ? .focus : (lit.contains(a.id) ? .lit : .dim))
                GraphNode(artist: a, tint: library.color(forEra: a.primaryEra), state: state, size: nodeSize,
                          showName: showNames || state == .focus || state == .lit)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3)) { selected = (selected == a.id ? nil : a.id) }
                    }
                    .position(cam.screen(layout.positions[a.id]!))
                    .zIndex(state == .focus ? 2 : (state == .lit ? 1 : 0))
            }

            // Faces pass under the navigation bar behind a shade, with the decades ruler on top.
            LinearGradient(stops: [.init(color: Theme.ink, location: 0), .init(color: Theme.ink.opacity(0.85), location: 0.6),
                                   .init(color: Theme.ink.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: topInset + 44)
                .allowsHitTesting(false)
                .zIndex(3)
            Canvas { ctx, size in drawRuler(in: &ctx, size: size, cam: cam) }
                .allowsHitTesting(false)
                .zIndex(4)
        }
        .frame(width: viewport.width, height: viewport.height)
        .clipped()
        .gesture(
            SimultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .updating($pan) { v, s, _ in s = v.translation }
                    .onEnded { v in
                        // Carry on a little in the direction of the swipe, then settle within the edges.
                        var c = camera
                        c.offset.x += v.translation.width
                        c.offset.y += v.translation.height
                        camera = c
                        var glide = c
                        glide.offset.x += (v.predictedEndTranslation.width - v.translation.width) * 0.8
                        glide.offset.y += (v.predictedEndTranslation.height - v.translation.height) * 0.8
                        withAnimation(.timingCurve(0.15, 0.85, 0.3, 1, duration: 0.7)) {
                            camera = Self.clamped(glide, layout: layout, viewport: viewport)
                        }
                    },
                MagnifyGesture()
                    .updating($pinch) { v, s, _ in
                        s = Pinch(scale: v.magnification,
                                  anchor: CGPoint(x: v.startAnchor.x * viewport.width, y: v.startAnchor.y * viewport.height))
                    }
                    .onEnded { v in
                        var c = camera
                        let anchor = CGPoint(x: v.startAnchor.x * viewport.width, y: v.startAnchor.y * viewport.height)
                        let z = min(MapCamera.maxZoom, max(MapCamera.minZoom, camera.zoom * v.magnification))
                        let k = z / camera.zoom
                        c.zoom = z
                        c.offset = CGPoint(x: anchor.x - (anchor.x - camera.offset.x) * k,
                                           y: anchor.y - (anchor.y - camera.offset.y) * k)
                        withAnimation(.spring(response: 0.35)) {
                            camera = Self.clamped(c, layout: layout, viewport: viewport)
                        }
                    }
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Connections map")
    }

    /// Decade labels pinned under the navigation bar, so you always know when you are, and the eras as a ribbon.
    private func drawRuler(in ctx: inout GraphicsContext, size: CGSize, cam: MapCamera) {
        for d in layout.decades {
            let x = layout.x(forYear: d) * cam.zoom + cam.offset.x
            guard x > -60, x < size.width + 60 else { continue }
            ctx.draw(Text("\(String(d))s").font(Theme.label(10)).foregroundStyle(Theme.muted),
                     at: CGPoint(x: x + 5, y: topInset + 10), anchor: .leading)
        }
        for e in library.eras {
            let x0 = layout.x(forYear: e.start) * cam.zoom + cam.offset.x
            let x1 = layout.x(forYear: e.end) * cam.zoom + cam.offset.x
            let r = CGRect(x: x0, y: topInset + 22, width: max(6, x1 - x0), height: 4)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(e.tint.opacity(0.7)))
        }
    }

    private func draw(in ctx: inout GraphicsContext, size: CGSize, cam: MapCamera) {
        // Decades: lines down the map.
        for d in layout.decades {
            let x = layout.x(forYear: d) * cam.zoom + cam.offset.x
            guard x > -60, x < size.width + 60 else { continue }
            var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(line, with: .color(Theme.panelHi.opacity(0.7)), lineWidth: 1)
        }
        // Collaborations.
        for (a, b) in layout.edges {
            guard let p0 = layout.positions[a], let q0 = layout.positions[b] else { continue }
            let p = cam.screen(p0), q = cam.screen(q0)
            if max(p.x, q.x) < -20 || min(p.x, q.x) > size.width + 20 { continue }
            let on = selected != nil && (a == selected || b == selected)
            var path = Path()
            path.move(to: p)
            path.addQuadCurve(to: q, control: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2 - abs(q.x - p.x) * 0.12))
            let color: Color = on ? library.color(forEra: library.artist(selected!)?.primaryEra ?? "") : Theme.cream
            ctx.stroke(path, with: .color(color.opacity(on ? 0.9 : (selected == nil ? 0.14 : 0.05))),
                       lineWidth: on ? 2.5 : 1)
        }
    }
}

private struct GraphNode: View {
    enum State { case normal, focus, lit, dim }
    let artist: Artist
    let tint: Color
    let state: State
    let size: CGFloat
    let showName: Bool

    var body: some View {
        let s = state == .focus ? size * 1.35 : size
        ArtistPortrait(artist: artist, tint: tint, duotone: state != .focus)
            .frame(width: s, height: s)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(tint, lineWidth: state == .normal ? 2 : 3))
            .shadow(color: tint.opacity(state == .focus ? 0.8 : 0), radius: 16)
            .overlay(alignment: .top) {
                if showName {
                    Text(artist.name).font(.system(size: 11, weight: state == .focus ? .bold : .semibold))
                        .foregroundStyle(state == .dim ? Theme.faint : Theme.cream)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.ink.opacity(0.75)))
                        .offset(y: s + 3)
                }
            }
            .frame(width: max(s, 44), height: max(s, 44))
            .contentShape(Circle())
            .opacity(state == .dim ? 0.28 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(artist.name)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(state == .focus ? .isSelected : [])
    }
}

private struct SelectedArtistCard: View {
    let artist: Artist
    let onClose: () -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let tint = library.color(forEra: artist.primaryEra)
        let n = library.neighbors(of: artist.id).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ArtistPortrait(artist: artist, tint: tint, duotone: false)
                    .frame(width: 62, height: 76).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(artist.name).font(Theme.display(26)).foregroundStyle(Theme.cream).lineLimit(1).minimumScaleFactor(0.7)
                    Text([artist.instrument, artist.lifespan].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Text("\(n) connection\(n == 1 ? "" : "s")").font(Theme.label(10)).foregroundStyle(tint)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 28, height: 28)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel("Close")
            }
            Text(artist.blurb).font(.subheadline).foregroundStyle(Theme.cream.opacity(0.85)).lineLimit(3)
            NavigationLink(value: PhoneRoute.artist(artist.id)) {
                Label("Open \(artist.name.components(separatedBy: " ").first ?? artist.name)", systemImage: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .foregroundStyle(Theme.ink).background(Capsule().fill(tint))
            }
            .buttonStyle(.pressable)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.panel.opacity(0.82)))
        .glassEffect(.regular.tint(tint.opacity(0.06)), in: .rect(cornerRadius: 24))
    }
}
