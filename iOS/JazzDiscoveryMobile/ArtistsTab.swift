import SwiftUI

struct ArtistsTab: View {
    @Environment(JazzLibrary.self) private var library
    @State private var era: String? = nil
    @State private var instrument: String? = nil
    @State private var sort: Sort = .chronological
    @State private var role: Role = .everyone
    enum Sort: String, CaseIterable { case chronological = "By Birth", alphabetical = "A–Z" }
    /// Leaders have records in the Crate; sidemen are known from the records they play on.
    enum Role: String, CaseIterable { case everyone = "Everyone", leaders = "Leaders", sidemen = "Sidemen" }

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let list = library.artists
            .filter { era == nil || $0.eras.contains(era!) }
            .filter { instrument == nil || $0.instrument == instrument }
            .filter { role == .everyone || (role == .sidemen) == library.isSideman($0.id) }
            .sorted { sort == .alphabetical ? $0.name < $1.name : ($0.born ?? 0, $0.name) < ($1.born ?? 0, $1.name) }

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Artists",
                           subtitle: list.count == library.artists.count
                           ? "\(library.artists.count) players, singers and composers"
                           : "\(list.count) of \(library.artists.count) players, singers and composers")

                ConnectionsBanner().padding(.horizontal, Theme.gutter)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        Menu {
                            Picker("Instrument", selection: $instrument) {
                                Text("All Instruments").tag(String?.none)
                                ForEach(library.instruments, id: \.self) { Text($0.capitalized).tag(String?.some($0)) }
                            }
                        } label: {
                            Chip(text: instrument?.capitalized ?? "Instrument", tint: Theme.cream, filled: instrument != nil,
                                 systemImage: "chevron.down")
                        }
                        Menu {
                            Picker("Role", selection: $role) {
                                ForEach(Role.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Chip(text: role.rawValue, tint: Theme.cream, filled: role != .everyone, systemImage: "chevron.down")
                        }
                        Menu {
                            Picker("Sort", selection: $sort) {
                                ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                        } label: {
                            Chip(text: sort.rawValue, tint: Theme.cream, systemImage: "arrow.up.arrow.down")
                        }
                        Rectangle().fill(Theme.panelHi).frame(width: 1, height: 22)
                        FilterChip(text: "All Eras", selected: era == nil) { era = nil }
                        ForEach(library.eras) { e in
                            FilterChip(text: e.name, tint: e.tint, selected: era == e.id) { era = (era == e.id ? nil : e.id) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)

                if list.isEmpty {
                    ContentUnavailableView {
                        Label("No Artists", systemImage: "person.2.slash")
                    } description: {
                        Text("No one in the guide matches both filters.")
                    } actions: {
                        Button("Clear Filters") { era = nil; instrument = nil; role = .everyone }
                    }
                    .padding(.top, 30)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(list) { a in ArtistCard(artist: a, width: nil) }
                    }
                    .padding(.horizontal, Theme.gutter)
                    .animation(.easeInOut(duration: 0.25), value: list.map(\.id))
                }
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Artists", after: 60)
        .rootToolbar()
    }
}

/// The way into the Connections map, drawn as a little constellation.
struct ConnectionsBanner: View {
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        NavigationLink(value: PhoneRoute.connections(focus: nil)) {
            HStack(spacing: 16) {
                Canvas { ctx, size in Self.drawConstellation(&ctx, size: size, tints: library.eras.map(\.tint)) }
                .frame(width: 92, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONNECTIONS").font(Theme.display(24)).foregroundStyle(Theme.cream)
                    Text("Who played with whom, across 130 years").font(.footnote).foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(Theme.faint)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.brass.opacity(0.2)))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connections: who played with whom")
        .accessibilityAddTraits(.isButton)
    }

    private static func drawConstellation(_ ctx: inout GraphicsContext, size: CGSize, tints: [Color]) {
        let unit: [CGPoint] = [CGPoint(x: 0.12, y: 0.62), CGPoint(x: 0.32, y: 0.25), CGPoint(x: 0.45, y: 0.72),
                               CGPoint(x: 0.66, y: 0.38), CGPoint(x: 0.86, y: 0.7), CGPoint(x: 0.82, y: 0.2)]
        let pts: [CGPoint] = unit.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let links: [(Int, Int)] = [(0, 1), (1, 2), (1, 3), (2, 3), (3, 4), (3, 5), (2, 4)]
        for (a, b) in links {
            let p0 = pts[a], p1 = pts[b]
            let control = CGPoint(x: (p0.x + p1.x) / 2, y: min(p0.y, p1.y) - 8)
            var path = Path()
            path.move(to: p0)
            path.addQuadCurve(to: p1, control: control)
            ctx.stroke(path, with: .color(Theme.cream.opacity(0.25)), lineWidth: 1)
        }
        for (i, p) in pts.enumerated() {
            let r: CGFloat = i == 3 ? 9 : 6
            let color: Color = tints.isEmpty ? Theme.brass : tints[(i * 2 + 3) % tints.count]
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }
}

// MARK: - Artist page

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var summary: WikiSummary?
    @State private var top: [CatalogTrack] = []
    @State private var loadedTop = false
    @State private var showAllTop = false

    var body: some View {
        let tint = library.color(forEra: artist.primaryEra)
        let eras = library.eras.filter { artist.eras.contains($0.id) }
        let albums = library.albums(by: artist.id)
        // Strongest ties first: the most records together, then bonds.
        let ties = library.ties(of: artist.id)
        let connections = ties.compactMap { library.artist($0.other(than: artist.id)) }

        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                // Hero: the portrait, full bleed, printed in the era's ink.
                ZStack(alignment: .bottomLeading) {
                    ArtistPortrait(artist: artist, tint: tint, large: true)
                        .frame(maxWidth: .infinity).frame(height: 500)
                        .clipped()
                    LinearGradient(stops: [.init(color: Theme.ink.opacity(0.35), location: 0),
                                           .init(color: .clear, location: 0.22),
                                           .init(color: Theme.ink.opacity(0.4), location: 0.6),
                                           .init(color: Theme.ink, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker(text: [artist.instrument, artist.lifespan].filter { !$0.isEmpty }.joined(separator: " · "), tint: tint)
                        Text(artist.name.uppercased()).font(Theme.display(58)).foregroundStyle(Theme.cream)
                            .lineLimit(2).minimumScaleFactor(0.5)
                            .shadow(color: .black.opacity(0.4), radius: 12)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .padding(.horizontal, Theme.gutter)
                }
                .frame(height: 500)

                VStack(alignment: .leading, spacing: 14) {
                    Text(artist.blurb).font(.system(.title3, design: .serif)).foregroundStyle(Theme.cream.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    FlowLayout(spacing: 8) { ForEach(eras) { EraChip(era: $0) } }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, -14)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Popular on Apple Music", tint: tint) {
                        if !top.isEmpty {
                            Button { player.play(top, startAt: 0, key: "top-\(artist.id)") } label: {
                                Label("Play", systemImage: "play.fill").font(.subheadline.weight(.bold))
                            }
                            .buttonStyle(.glassProminent)
                            .tint(tint)
                            .foregroundStyle(Theme.ink)
                        }
                    }
                    Group {
                        if top.isEmpty {
                            if loadedTop {
                                Text("Couldn't reach the catalog right now.").font(.subheadline).foregroundStyle(Theme.muted)
                            } else {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            }
                        } else {
                            TrackList(tracks: top, visible: showAllTop ? top.count : 5, tint: tint,
                                      showArtwork: true, highlight: artist.signatureTracks)
                            if top.count > 5 {
                                Button(showAllTop ? "Show Fewer" : "Show All \(top.count)") {
                                    withAnimation(.easeInOut(duration: 0.25)) { showAllTop.toggle() }
                                }
                                .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Biography", tint: tint)
                    VStack(alignment: .leading, spacing: 12) {
                        if let s = summary {
                            ExpandableText(text: s.extract, lines: 7, tint: tint)
                            Attribution(text: "Wikipedia (CC BY-SA)", url: s.pageURL)
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        if !artist.signatureTracks.isEmpty {
                            Kicker(text: "Signature Tunes", tint: tint).padding(.top, 8)
                            FlowLayout(spacing: 6) { ForEach(artist.signatureTracks, id: \.self) { Chip(text: $0, tint: tint) } }
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Essential Records", tint: tint)
                        HRow { ForEach(albums) { AlbumCard(album: $0, width: 150, showArtist: false) } }
                    }
                }

                let appearances = library.appearances(of: artist.id)
                if !appearances.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Also Plays On", subtitle: "Records in the Crate led by others.", tint: tint)
                        HRow {
                            ForEach(appearances) { a in
                                VStack(alignment: .leading, spacing: 5) {
                                    AlbumCard(album: a, width: 150)
                                    if let credit = library.credit(of: artist.id, on: a.id) {
                                        Text(credit.instrumentsText).font(.caption.weight(.medium)).foregroundStyle(tint).lineLimit(1)
                                    }
                                }
                                .frame(width: 150, alignment: .leading)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch", subtitle: "Live performances and interviews from YouTube.", tint: tint)
                    VideoStrip(query: artist.videoQuery, tint: tint)
                }

                if !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Played With", subtitle: "Bandmates, mentors and influences, the closest first.", tint: tint) {
                            NavigationLink(value: PhoneRoute.connections(focus: artist.id)) {
                                Label("Map", systemImage: "point.3.connected.trianglepath.dotted")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                            }
                            .accessibilityLabel("Show \(artist.name) on the Connections map")
                        }
                        HRow {
                            ForEach(Array(zip(connections, ties)), id: \.0.id) { other, tie in
                                VStack(alignment: .leading, spacing: 3) {
                                    ArtistCard(artist: other, width: 116)
                                    Text(tie.shortText).font(.caption.weight(.medium)).foregroundStyle(tint)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.ink)
        .revealedTitle(artist.name, after: 420)
        .task(id: artist.id) {
            async let s = Wikipedia.shared.summary(artist.wikipedia)
            async let t = ITunes.shared.topSongs(artist: artist.name)
            summary = await s
            top = await t
            loadedTop = true
        }
    }
}
