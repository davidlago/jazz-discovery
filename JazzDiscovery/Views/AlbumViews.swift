import SwiftUI

struct CrateView: View {
    @Environment(JazzLibrary.self) private var library
    @State private var era: String? = nil
    @State private var startersOnly = false
    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 210), spacing: 20)]

    var body: some View {
        let list = library.albums
            .filter { era == nil || $0.era == era }
            .filter { !startersOnly || $0.starter }
        let decades = Array(Set(list.map(\.decade))).sorted()

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("THE CRATE").font(Theme.display(64)).foregroundStyle(Theme.cream)
                        Text("\(list.count) records that changed the music. Flip through by decade.")
                            .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Toggle("Start Here picks only", isOn: $startersOnly).toggleStyle(.switch)
                }
                .padding(.top, 30)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { era = nil } label: { Chip(text: "All styles", tint: Theme.cream, filled: era == nil) }
                            .buttonStyle(.plain)
                        ForEach(library.eras) { e in
                            Button { era = (era == e.id ? nil : e.id) } label: { Chip(text: e.name, tint: e.tint, filled: era == e.id) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(decades, id: \.self) { d in
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(String(d))s").font(Theme.display(44)).foregroundStyle(Theme.cream)
                            Rectangle().fill(Theme.panelHi).frame(height: 1)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                            ForEach(list.filter { $0.decade == d }) { AlbumCard(album: $0, width: 180) }
                        }
                    }
                }
            }
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
        .background(Theme.ink)
        .navigationTitle("The Crate")
    }
}

struct AlbumDetailView: View {
    let album: Album
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
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
            VStack(alignment: .leading, spacing: 40) {
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: catalog?.artwork(1000)) { tint.opacity(0.2) }
                        .frame(maxWidth: .infinity).frame(height: 470).clipped()
                        .blur(radius: 50).opacity(0.6)
                    LinearGradient(colors: [.clear, Theme.ink], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 36) {
                        AlbumCover(album: album, size: 1000)
                            .frame(width: 340, height: 340)
                            .shadow(color: .black.opacity(0.7), radius: 30, y: 14)
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                if let era { EraChip(era: era) }
                                Text("\(String(album.year)) · \(album.label)").font(Theme.label(12)).foregroundStyle(Theme.muted)
                            }
                            Text(album.title.uppercased()).font(Theme.display(64)).foregroundStyle(Theme.cream)
                                .lineLimit(3).minimumScaleFactor(0.4)
                            if let artist {
                                Button { router.go(.artist(artist.id)) } label: {
                                    Text(album.artistName).font(Theme.serif(24)).italic().foregroundStyle(tint)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(album.artistName).font(Theme.serif(24)).italic().foregroundStyle(tint)
                            }
                            Text(album.why).font(Theme.serif(17)).foregroundStyle(Theme.cream.opacity(0.88))
                                .frame(maxWidth: 620, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            AlbumPlayControls(catalog: catalog, tracks: tracks, tint: tint).padding(.top, 6)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 40).padding(.bottom, 10)
                }
                .frame(height: 470)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Tracklist", subtitle: album.highlights.isEmpty ? nil : "★ marks the tracks to start with.", tint: tint)
                    if tracks.isEmpty {
                        if loaded {
                            Text("This record isn't in the Apple Music catalog lookup. Try opening it in Music.")
                                .foregroundStyle(Theme.muted)
                        } else { ProgressView().controlSize(.small) }
                    } else {
                        TrackList(tracks: tracks, tint: tint, highlight: album.highlights)
                            .frame(maxWidth: 860)
                    }
                }
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch & Listen on YouTube", tint: tint).padding(.horizontal, 40)
                    VideoStrip(query: "\(album.artistName) \(album.title) \(album.highlights.first ?? "")", tint: tint)
                }

                if !more.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "More from \(album.artistName)", tint: tint).padding(.horizontal, 40)
                        HRow { ForEach(more) { AlbumCard(album: $0, showArtist: false) } }
                    }
                }
                if !sameEra.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Also from \(era?.name ?? "this era")", tint: tint).padding(.horizontal, 40)
                        HRow { ForEach(sameEra) { AlbumCard(album: $0) } }
                    }
                }
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(album.title)
        .task(id: album.id) {
            catalog = await ITunes.shared.album(for: album)
            if let c = catalog { tracks = await ITunes.shared.tracks(collectionId: c.collectionId) }
            loaded = true
        }
    }
}
