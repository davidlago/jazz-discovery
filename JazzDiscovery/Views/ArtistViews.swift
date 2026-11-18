import SwiftUI

struct ArtistsView: View {
    @Environment(JazzLibrary.self) private var library
    @State private var era: String? = nil
    @State private var instrument: String? = nil
    @State private var sort: Sort = .chronological
    @State private var role: Role = .everyone
    enum Sort: String, CaseIterable { case chronological = "By birth", alphabetical = "A–Z" }
    /// Leaders have records in the Crate; sidemen are known from the records they play on.
    enum Role: String, CaseIterable { case everyone = "Everyone", leaders = "Leaders", sidemen = "Sidemen" }

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 20)]

    var body: some View {
        let list = library.artists
            .filter { era == nil || $0.eras.contains(era!) }
            .filter { instrument == nil || $0.instrument == instrument }
            .filter { role == .everyone || (role == .sidemen) == library.isSideman($0.id) }
            .sorted { sort == .alphabetical ? $0.name < $1.name : ($0.born ?? 0, $0.name) < ($1.born ?? 0, $1.name) }

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ARTISTS").font(Theme.display(64)).foregroundStyle(Theme.cream)
                        Text("\(list.count) of \(library.artists.count) players, singers and composers")
                            .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Picker("", selection: $role) {
                        ForEach(Role.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 240)
                    Picker("Instrument", selection: $instrument) {
                        Text("All instruments").tag(String?.none)
                        Divider()
                        ForEach(library.instruments, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                    .frame(width: 190)
                    Picker("", selection: $sort) {
                        ForEach(Sort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).frame(width: 170)
                }
                .padding(.top, 30)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button { era = nil } label: { Chip(text: "All eras", tint: Theme.cream, filled: era == nil) }
                            .buttonStyle(.plain)
                        ForEach(library.eras) { e in
                            Button { era = (era == e.id ? nil : e.id) } label: {
                                Chip(text: e.name, tint: e.tint, filled: era == e.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
                    ForEach(list) { a in ArtistCard(artist: a, width: 170) }
                }
                .animation(.easeInOut(duration: 0.25), value: list.map(\.id))
            }
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
        .background(Theme.ink)
        .navigationTitle("Artists")
    }
}

struct ArtistDetailView: View {
    let artist: Artist
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var summary: WikiSummary?
    @State private var top: [CatalogTrack] = []
    @State private var loadedTop = false

    var body: some View {
        let tint = library.color(forEra: artist.primaryEra)
        let eras = library.eras.filter { artist.eras.contains($0.id) }
        let albums = library.albums(by: artist.id)
        let connections = library.artists(Array(library.neighbors(of: artist.id))).sorted { ($0.born ?? 0) < ($1.born ?? 0) }

        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Hero
                ZStack(alignment: .bottomLeading) {
                    RemoteImage(url: summary?.largeImage) { tint.opacity(0.2) }
                        .frame(maxWidth: .infinity).frame(height: 460).clipped()
                        .duotone(tint, strength: 0.95)
                        .blur(radius: 18).opacity(0.55)
                    LinearGradient(colors: [.clear, Theme.ink], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom, spacing: 34) {
                        ArtistPortrait(artist: artist, tint: tint, duotone: false)
                            .frame(width: 260, height: 330)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(color: .black.opacity(0.6), radius: 24, y: 10)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(artist.instrument.uppercased()) · \(artist.lifespan)").font(Theme.label(12)).tracking(3).foregroundStyle(tint)
                            Text(artist.name.uppercased()).font(Theme.display(72)).foregroundStyle(Theme.cream)
                                .lineLimit(2).minimumScaleFactor(0.5)
                            Text(artist.blurb).font(Theme.serif(19)).foregroundStyle(Theme.cream.opacity(0.9))
                                .frame(maxWidth: 640, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                            FlowLayout(spacing: 8) { ForEach(eras) { EraChip(era: $0) } }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 40).padding(.bottom, 10)
                }
                .frame(height: 460)

                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Popular on Apple Music", tint: tint)
                        if top.isEmpty {
                            if loadedTop { Text("Couldn't reach the catalog right now.").foregroundStyle(Theme.muted) }
                            else { ProgressView().controlSize(.small).padding() }
                        } else {
                            TrackList(tracks: top, tint: tint, showArtist: true, highlight: artist.signatureTracks)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Biography", tint: tint)
                        if let s = summary {
                            Text(s.extract).font(Theme.serif(16)).lineSpacing(4).foregroundStyle(Theme.cream.opacity(0.88))
                                .fixedSize(horizontal: false, vertical: true)
                            Attribution(text: "Wikipedia (CC BY-SA)", url: s.pageURL)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        if !artist.signatureTracks.isEmpty {
                            Text("SIGNATURE TUNES").font(Theme.label(11)).tracking(2).foregroundStyle(tint).padding(.top, 8)
                            FlowLayout(spacing: 6) { ForEach(artist.signatureTracks, id: \.self) { Chip(text: $0, tint: tint) } }
                        }
                    }
                    .frame(width: 400, alignment: .topLeading)
                }
                .padding(.horizontal, 40)

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Essential Records", tint: tint).padding(.horizontal, 40)
                        HRow { ForEach(albums) { AlbumCard(album: $0, width: 200, showArtist: false) } }
                    }
                }

                let appearances = library.appearances(of: artist.id)
                if !appearances.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Also Plays On", subtitle: "Records in the Crate led by others.", tint: tint)
                            .padding(.horizontal, 40)
                        HRow {
                            ForEach(appearances) { a in
                                VStack(alignment: .leading, spacing: 6) {
                                    AlbumCard(album: a, width: 200)
                                    if let credit = library.credit(of: artist.id, on: a.id) {
                                        Text(credit.instrumentsText).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(width: 200, alignment: .leading)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch \(artist.name)", subtitle: "Live performances and interviews from YouTube.", tint: tint)
                        .padding(.horizontal, 40)
                    VideoStrip(query: artist.videoQuery, tint: tint)
                }

                if !connections.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            SectionHeader(title: "Played With", subtitle: "Bandmates, mentors and collaborators.", tint: tint)
                            Spacer()
                            Button { router.show(.connections) } label: {
                                Label("Open the Connections map", systemImage: "point.3.connected.trianglepath.dotted")
                            }
                            .buttonStyle(.link)
                        }
                        .padding(.horizontal, 40)
                        HRow { ForEach(connections) { ArtistCard(artist: $0, width: 140) } }
                    }
                }
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(artist.name)
        .task(id: artist.id) {
            async let s = Wikipedia.shared.summary(artist.wikipedia)
            async let t = ITunes.shared.topSongs(artist: artist.name)
            summary = await s
            top = await t
            loadedTop = true
        }
    }
}
