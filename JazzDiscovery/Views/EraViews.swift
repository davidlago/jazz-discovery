import SwiftUI

struct EraIndexView: View {
    @Environment(JazzLibrary.self) private var library
    private let columns = [GridItem(.adaptive(minimum: 330, maximum: 520), spacing: 22)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ERAS & STYLES").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("Every movement in jazz was an argument with the one before it. Here's the whole conversation.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(library.eras) { era in EraPosterCard(era: era) }
                }
            }
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
        .background(Theme.ink)
        .navigationTitle("Eras & Styles")
    }
}

/// A record-sleeve style poster for an era.
struct EraPosterCard: View {
    let era: Era
    var width: CGFloat? = nil
    var height: CGFloat = 260
    @Environment(Router.self) private var router
    @Environment(JazzLibrary.self) private var library
    @State private var image: URL?

    var body: some View {
        Button { router.go(.era(era.id)) } label: {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: image) { era.tint.opacity(0.3) }
                    .frame(maxWidth: .infinity).frame(height: height)
                    .clipped()
                    .duotone(era.tint)
                LinearGradient(colors: [.clear, Theme.ink.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 4) {
                    Text(era.years).font(Theme.label(11)).tracking(2).foregroundStyle(era.tint)
                    Text(era.name.uppercased()).font(Theme.display(34)).foregroundStyle(Theme.cream)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Text(era.tagline).font(Theme.serif(14)).italic().foregroundStyle(Theme.cream.opacity(0.8)).lineLimit(1)
                }
                .padding(20)
                Rectangle().fill(era.tint).frame(width: 6).frame(maxHeight: .infinity, alignment: .leading)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .hoverLift(1.02)
        }
        .buttonStyle(.plain)
        .task(id: era.id) { image = await Wikipedia.shared.leadImage(era.wikipedia) }
    }
}

struct EraDetailView: View {
    let era: Era
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var summary: WikiSummary?
    @State private var gallery: [WikiImage] = []
    @State private var heroImage: URL?

    var body: some View {
        let artists = library.artists(era.keyArtists)
        let more = library.artists(inEra: era.id).filter { !era.keyArtists.contains($0.id) }
        let keyAlbums = library.albums(era.keyAlbums)
        let moreAlbums = library.albums(inEra: era.id).filter { !era.keyAlbums.contains($0.id) }

        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HeroBanner(imageURL: heroImage, tint: era.tint,
                           kicker: era.years, title: era.name, subtitle: era.tagline, height: 420) {
                    VStack(alignment: .trailing, spacing: 14) {
                        EraProgressBadge(era: era)
                        if let station = StationStarter.station(era: era.id, library: library) { PlayRadioButton(station: station) }
                    }
                }

                HStack(alignment: .top, spacing: 40) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(era.summary.components(separatedBy: "\n\n"), id: \.self) { p in
                            TermText(text: p, font: Theme.serif(17), color: Theme.cream.opacity(0.92)) { router.go(.term($0)) }
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: 680, alignment: .leading)

                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("THE SOUND").font(Theme.label(11)).tracking(2).foregroundStyle(era.tint)
                            FlowLayout(spacing: 8) {
                                ForEach(era.characteristics, id: \.self) { Chip(text: $0, tint: era.tint) }
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WHERE IT HAPPENED").font(Theme.label(11)).tracking(2).foregroundStyle(era.tint)
                            let linked = library.places(inEra: era.id)
                            if linked.isEmpty {
                                ForEach(era.places, id: \.self) { place in
                                    Label(place, systemImage: "mappin.and.ellipse").font(.system(size: 13)).foregroundStyle(Theme.cream)
                                }
                            } else {
                                ForEach(linked) { p in
                                    Button { router.go(.place(p.id)) } label: {
                                        Label(p.name, systemImage: p.symbol).font(.system(size: 13)).foregroundStyle(Theme.cream)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if let i = library.eras.firstIndex(of: era) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FAMILY").font(Theme.label(11)).tracking(2).foregroundStyle(era.tint)
                                FlowLayout(spacing: 8) {
                                    ForEach(neighbors(i)) { EraChip(era: $0) }
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 320, alignment: .leading)
                }
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Key Artists", tint: era.tint).padding(.horizontal, 40)
                    HRow { ForEach(artists + more) { ArtistCard(artist: $0) } }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Essential Records", tint: era.tint).padding(.horizontal, 40)
                    HRow { ForEach(keyAlbums + moreAlbums) { AlbumCard(album: $0, width: 200) } }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Essential Tracks", subtitle: "Click to play.", tint: era.tint)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 10) {
                        ForEach(Array(era.essentialTracks.enumerated()), id: \.element.id) { i, t in
                            EssentialTrackRow(ref: t, tint: era.tint, index: i)
                        }
                    }
                }
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch", subtitle: "Documentaries and performances from YouTube.", tint: era.tint)
                        .padding(.horizontal, 40)
                    VideoStrip(query: era.documentaryQuery, tint: era.tint)
                }

                if !gallery.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Picture Archive", subtitle: "From Wikimedia Commons.", tint: era.tint)
                            .padding(.horizontal, 40)
                        HRow(spacing: 12) {
                            ForEach(gallery) { img in
                                VStack(alignment: .leading, spacing: 6) {
                                    RemoteImage(url: img.url, contentMode: .fill) { Theme.panel }
                                        .frame(width: 260, height: 190).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    if let c = img.caption {
                                        Text(c).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                                            .frame(width: 260, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }

                if let s = summary, !s.extract.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "From Wikipedia", tint: era.tint)
                        Text(s.extract).font(.system(size: 14)).lineSpacing(4).foregroundStyle(Theme.muted)
                            .frame(maxWidth: 760, alignment: .leading)
                        Attribution(text: "Wikipedia — \(s.title) (CC BY-SA)", url: s.pageURL)
                    }
                    .padding(.horizontal, 40)
                }

                EraPager(era: era).padding(.horizontal, 40)
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(era.name)
        .task(id: era.id) {
            summary = await Wikipedia.shared.summary(era.wikipedia)
            heroImage = await Wikipedia.shared.leadImage(era.wikipedia)
            gallery = await Wikipedia.shared.images(era.wikipedia)
        }
    }

    private func neighbors(_ i: Int) -> [Era] {
        library.eras.filter { $0.id != era.id && $0.start <= era.end && $0.end >= era.start }
    }
}

struct EraPager: View {
    let era: Era
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let eras = library.eras
        let i = eras.firstIndex(of: era) ?? 0
        HStack {
            if i > 0 { pagerButton(eras[i - 1], label: "Before", leading: true) }
            Spacer()
            if i + 1 < eras.count { pagerButton(eras[i + 1], label: "Next", leading: false) }
        }
    }

    private func pagerButton(_ e: Era, label: String, leading: Bool) -> some View {
        Button { router.go(.era(e.id)) } label: {
            HStack(spacing: 12) {
                if leading { Image(systemName: "arrow.left") }
                VStack(alignment: leading ? .leading : .trailing, spacing: 2) {
                    Text(label.uppercased()).font(Theme.label(10)).tracking(2).foregroundStyle(Theme.muted)
                    Text(e.name.uppercased()).font(Theme.display(24)).foregroundStyle(e.tint)
                }
                if !leading { Image(systemName: "arrow.right") }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
            .hoverLift(1.02)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.cream)
    }
}
