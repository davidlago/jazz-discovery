import SwiftUI

struct CrateTab: View {
    @Environment(JazzLibrary.self) private var library
    @State private var era: String? = nil
    @State private var startersOnly = false
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let list = library.albums
            .filter { era == nil || $0.era == era }
            .filter { !startersOnly || $0.starter }
        let decades = Array(Set(list.map(\.decade))).sorted()

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                PageHeader(title: "The Crate", subtitle: "\(list.count) records that changed the music. Flip through by decade.")

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        FilterChip(text: "Start Here", tint: Theme.brass, selected: startersOnly, systemImage: "star.fill") {
                            startersOnly.toggle()
                        }
                        Rectangle().fill(Theme.panelHi).frame(width: 1, height: 22)
                        FilterChip(text: "All Styles", selected: era == nil) { era = nil }
                        ForEach(library.eras) { e in
                            FilterChip(text: e.name, tint: e.tint, selected: era == e.id) { era = (era == e.id ? nil : e.id) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)

                if list.isEmpty {
                    ContentUnavailableView("No Records", systemImage: "opticaldisc",
                                           description: Text("None of the Start Here picks are from this style."))
                        .padding(.top, 30)
                }

                ForEach(decades, id: \.self) { d in
                    Section {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            ForEach(list.filter { $0.decade == d }) { AlbumCard(album: $0, width: nil) }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 10)
                    } header: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(String(d))s").font(Theme.display(34)).foregroundStyle(Theme.cream)
                            Rectangle().fill(Theme.panelHi).frame(height: 1)
                            Text("\(list.filter { $0.decade == d }.count)").font(Theme.label(11)).foregroundStyle(Theme.faint)
                        }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 6)
                        .background(Theme.ink.opacity(0.94))
                        .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .padding(.top, 8).padding(.bottom, 32)
            .animation(.easeInOut(duration: 0.25), value: list.map(\.id))
        }
        .background(Theme.ink)
        .revealedTitle("The Crate", after: 60)
        .rootToolbar()
    }
}

// MARK: - Album page

struct AlbumDetailView: View {
    let album: Album
    @Environment(JazzLibrary.self) private var library
    @State private var catalog: CatalogAlbum?
    @State private var tracks: [CatalogTrack] = []
    @State private var loaded = false

    var body: some View {
        let tint = library.color(forEra: album.era)
        let era = library.era(album.era)
        let artist = library.artist(album.artist)
        let more = library.albums(by: album.artist).filter { $0.id != album.id }
        let sameEra = library.albums(inEra: album.era).filter { $0.id != album.id && $0.artist != album.artist }

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(spacing: 14) {
                    AlbumCover(album: album, size: 1000, cornerRadius: 10)
                        .frame(width: 270, height: 270)
                        .shadow(color: .black.opacity(0.65), radius: 30, y: 16)
                        .padding(.bottom, 8)
                    HStack(spacing: 8) {
                        if let era { EraChip(era: era) }
                        Text("\(String(album.year)) · \(album.label)").font(Theme.label(11)).foregroundStyle(Theme.muted)
                    }
                    Text(album.title.uppercased()).font(Theme.display(40)).foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                    if let artist {
                        NavigationLink(value: PhoneRoute.artist(artist.id)) {
                            Text(album.artistName).font(.system(.title2, design: .serif)).italic().foregroundStyle(tint)
                        }
                        .buttonStyle(.pressable)
                    } else {
                        Text(album.artistName).font(.system(.title2, design: .serif)).italic().foregroundStyle(tint)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 110)
                .frame(maxWidth: .infinity)
                .background {
                    // The cover's own colors, blurred into a backdrop that fades into the page.
                    RemoteImage(url: catalog?.artwork(300)) { tint.opacity(0.25) }
                        .blur(radius: 50, opaque: true)
                        .opacity(0.75)
                        .overlay(LinearGradient(stops: [.init(color: Theme.ink.opacity(0.15), location: 0),
                                                        .init(color: Theme.ink.opacity(0.35), location: 0.55),
                                                        .init(color: Theme.ink, location: 1)],
                                                startPoint: .top, endPoint: .bottom))
                        .padding(.bottom, -40)
                        .clipped()
                }

                AlbumPlayControls(catalog: catalog, tracks: tracks, tint: tint)
                    .padding(.horizontal, Theme.gutter)
                    .padding(.top, -12)

                Text(album.why).font(.system(.body, design: .serif)).lineSpacing(4)
                    .foregroundStyle(Theme.cream.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Tracklist", subtitle: album.highlights.isEmpty ? nil : "★ marks the tracks to start with.", tint: tint)
                    Group {
                        if tracks.isEmpty {
                            if loaded {
                                Text("This record isn't in the Apple Music catalog lookup. Try opening it in Music.")
                                    .font(.subheadline).foregroundStyle(Theme.muted)
                            } else {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            }
                        } else {
                            TrackList(tracks: tracks, tint: tint, highlight: album.highlights)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch & Listen on YouTube", tint: tint)
                    VideoStrip(query: "\(album.artistName) \(album.title) \(album.highlights.first ?? "")", tint: tint)
                }

                if !more.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "More from \(album.artistName)", tint: tint)
                        HRow { ForEach(more) { AlbumCard(album: $0, width: 150, showArtist: false) } }
                    }
                }
                if !sameEra.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Also from \(era?.name ?? "this era")", tint: tint)
                        HRow { ForEach(sameEra) { AlbumCard(album: $0, width: 150) } }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.ink)
        .revealedTitle(album.title, after: 480)
        .task(id: album.id) {
            catalog = await ITunes.shared.album(for: album)
            if let c = catalog { tracks = await ITunes.shared.tracks(collectionId: c.collectionId) }
            loaded = true
        }
    }
}
