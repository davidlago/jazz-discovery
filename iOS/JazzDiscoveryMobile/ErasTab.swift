import SwiftUI
import MapKit

/// Explore: the eras first, as a carousel of posters, then Decades, the Songbook and Connections, each a row with
/// *See all*.
struct ErasTab: View {
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader(title: "Explore",
                           subtitle: "Every movement in jazz was an argument with the one before it. Start with the eras.")

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Eras & Styles")
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 12) {
                            ForEach(library.eras) { EraPosterCard(era: $0, height: 180).frame(width: 290) }
                        }
                        .scrollTargetLayout()
                        .padding(.vertical, 6)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Decades") { SeeAllLink(route: .decades) }
                    HRow(spacing: 12) { ForEach(library.decades, id: \.self) { DecadeTile(decade: $0) } }
                }

                if !library.tunes.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "The Songbook", subtitle: "\(library.tunes.count) tunes, and the versions that made them.") {
                            SeeAllLink(route: .songbook)
                        }
                        HRow(spacing: 12) {
                            ForEach(library.tunes.prefix(10)) { t in
                                NavigationLink(value: PhoneRoute.tune(t.id)) { TuneCard(tune: t, width: 200) }.buttonStyle(.pressable)
                            }
                        }
                    }
                }

                if !library.places.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Places", subtitle: "Where it happened, on a map with a time slider.") { SeeAllLink(route: .places) }
                        NavigationLink(value: PhoneRoute.places) {
                            Map(initialPosition: JazzMap.start, interactionModes: []) {
                                ForEach(library.places.filter(\.isCity)) { p in
                                    Annotation(p.name, coordinate: p.coordinate) { PlacePin(place: p, tint: library.tint(for: p)) }
                                }
                            }
                            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                            .preferredColorScheme(.dark)
                            .frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .allowsHitTesting(false)
                        }
                        .buttonStyle(.pressable)
                        .padding(.horizontal, Theme.gutter)
                    }
                }

                if !library.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionHeader(title: "Labels", subtitle: "Who put the music out.") { SeeAllLink(route: .labels) }
                        HRow(spacing: 12) {
                            ForEach(library.labels) { l in
                                NavigationLink(value: PhoneRoute.label(l.id)) { LabelCard(label: l, width: 130) }.buttonStyle(.pressable)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Connections", subtitle: "Who played with whom, across the century.")
                    NavigationLink(value: PhoneRoute.connections(focus: nil)) {
                        HStack {
                            Label("Open the map", systemImage: "point.3.connected.trianglepath.dotted")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.faint)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
                    }
                    .buttonStyle(.pressable)
                    .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Explore", after: 60)
        .rootToolbar()
    }
}

/// A record-sleeve poster for an era.
struct EraPosterCard: View {
    let era: Era
    var height: CGFloat = 196
    @State private var image: URL?

    var body: some View {
        NavigationLink(value: PhoneRoute.era(era.id)) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: image) { era.tint.opacity(0.3) }
                    .frame(maxWidth: .infinity).frame(height: height)
                    .clipped()
                    .duotone(era.tint)
                // Deep enough that the years, in the era's own color, still read over a photo printed in that color.
                LinearGradient(stops: [.init(color: .clear, location: 0.15),
                                       .init(color: Theme.ink.opacity(0.7), location: 0.55),
                                       .init(color: Theme.ink.opacity(0.95), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 3) {
                    Kicker(text: era.years, tint: era.tint)
                    Text(era.name.uppercased()).font(Theme.display(32)).foregroundStyle(Theme.cream)
                        .lineLimit(2).minimumScaleFactor(0.6)
                    Text(era.tagline).font(.system(.subheadline, design: .serif)).italic()
                        .foregroundStyle(Theme.cream.opacity(0.8)).lineLimit(1)
                }
                .shadow(color: .black.opacity(0.55), radius: 6)
                .padding(.leading, 22).padding(.trailing, 16).padding(.bottom, 16)
                Rectangle().fill(era.tint).frame(width: 6).frame(maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .task(id: era.id) { image = await Wikipedia.shared.leadImage(era.wikipedia) }
    }
}

// MARK: - Era page

struct EraDetailView: View {
    let era: Era
    @Environment(JazzLibrary.self) private var library
    @State private var summary: WikiSummary?
    @State private var gallery: [WikiImage] = []
    @State private var heroImage: URL?
    @State private var viewing: WikiImage?

    var body: some View {
        let artists = library.artists(era.keyArtists)
        let more = library.artists(inEra: era.id).filter { !era.keyArtists.contains($0.id) }
        let keyAlbums = library.albums(era.keyAlbums)
        let moreAlbums = library.albums(inEra: era.id).filter { !era.keyAlbums.contains($0.id) }
        let family = library.eras.filter { $0.id != era.id && $0.start <= era.end && $0.end >= era.start }

        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HeroBanner(imageURL: heroImage, tint: era.tint, kicker: era.years, title: era.name, subtitle: era.tagline)

                EraProgressRow(era: era)

                if let station = StationStarter.station(era: era.id, library: library) {
                    PlayRadioButton(station: station).padding(.horizontal, Theme.gutter).padding(.top, -16)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(era.summary.components(separatedBy: "\n\n"), id: \.self) { p in
                        Text(p).font(.system(.body, design: .serif)).lineSpacing(5)
                            .foregroundStyle(Theme.cream.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, Theme.gutter)

                Panel(tint: era.tint) {
                    VStack(alignment: .leading, spacing: 10) {
                        Kicker(text: "The Sound", tint: era.tint)
                        FlowLayout(spacing: 8) {
                            ForEach(era.characteristics, id: \.self) { Chip(text: $0, tint: era.tint) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Kicker(text: "Where It Happened", tint: era.tint)
                        let linked = library.places(inEra: era.id)
                        if linked.isEmpty {
                            ForEach(era.places, id: \.self) { place in
                                Label(place, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Theme.cream)
                            }
                        } else {
                            ForEach(linked) { p in
                                NavigationLink(value: PhoneRoute.place(p.id)) {
                                    Label(p.name, systemImage: p.symbol).font(.subheadline).foregroundStyle(Theme.cream)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !family.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Kicker(text: "Family", tint: era.tint)
                            FlowLayout(spacing: 8) { ForEach(family) { EraChip(era: $0) } }
                        }
                    }
                }

                if !(artists + more).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Key Artists", tint: era.tint)
                        HRow { ForEach(artists + more) { ArtistCard(artist: $0, width: 128) } }
                    }
                }

                if !(keyAlbums + moreAlbums).isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Essential Records", tint: era.tint)
                        HRow { ForEach(keyAlbums + moreAlbums) { AlbumCard(album: $0, width: 150) } }
                    }
                }

                if !era.essentialTracks.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "Essential Tracks", subtitle: "Tap to play. Touch and hold for more.", tint: era.tint)
                        VStack(spacing: 8) {
                            ForEach(Array(era.essentialTracks.enumerated()), id: \.element.id) { i, t in
                                EssentialTrackRow(ref: t, tint: era.tint, index: i)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch", subtitle: "Documentaries and performances from YouTube.", tint: era.tint)
                    VideoStrip(query: era.documentaryQuery, tint: era.tint)
                }

                if !gallery.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Picture Archive", subtitle: "From Wikimedia Commons. Tap to look closer.", tint: era.tint)
                        HRow(spacing: 10) {
                            ForEach(gallery) { img in
                                Button { viewing = img } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        RemoteImage(url: img.url, contentMode: .fill) { Theme.panel }
                                            .frame(width: 220, height: 160).clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        if let c = img.caption {
                                            Text(c).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                                .frame(width: 220, alignment: .leading)
                                        }
                                    }
                                }
                                .buttonStyle(.pressable)
                                .accessibilityLabel(img.caption ?? "Archive photo")
                            }
                        }
                    }
                }

                if let s = summary, !s.extract.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "From Wikipedia", tint: era.tint)
                        VStack(alignment: .leading, spacing: 10) {
                            ExpandableText(text: s.extract, lines: 5, font: .callout, color: Theme.muted, tint: era.tint)
                            Attribution(text: "Wikipedia: \(s.title) (CC BY-SA)", url: s.pageURL)
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }

                EraPager(era: era).padding(.horizontal, Theme.gutter)
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.ink)
        .revealedTitle(era.name, after: 360)
        .fullScreenCover(item: $viewing) { ImageViewer(image: $0) }
        .task(id: era.id) {
            summary = await Wikipedia.shared.summary(era.wikipedia)
            heroImage = await Wikipedia.shared.leadImage(era.wikipedia)
            gallery = await Wikipedia.shared.images(era.wikipedia)
        }
    }
}

struct EraPager: View {
    let era: Era
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let eras = library.eras
        let i = eras.firstIndex(of: era) ?? 0
        HStack(spacing: 10) {
            if i > 0 { card(eras[i - 1], label: "Before", leading: true) } else { Spacer() }
            if i + 1 < eras.count { card(eras[i + 1], label: "Next", leading: false) } else { Spacer() }
        }
    }

    private func card(_ e: Era, label: String, leading: Bool) -> some View {
        NavigationLink(value: PhoneRoute.era(e.id)) {
            VStack(alignment: leading ? .leading : .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    if leading { Image(systemName: "arrow.left") }
                    Text(label.uppercased()).font(Theme.label(10)).tracking(1.5)
                    if !leading { Image(systemName: "arrow.right") }
                }
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.muted)
                Text(e.name.uppercased()).font(Theme.display(22)).foregroundStyle(e.tint)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(leading ? .leading : .trailing)
            }
            .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.panel))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(label): \(e.name)")
    }
}

// MARK: - Decades

struct DecadeList: View {
    @Environment(JazzLibrary.self) private var library
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(library.decades, id: \.self) { DecadeCard(decade: $0) }
        }
        .padding(.horizontal, Theme.gutter)
    }
}

/// Decades as their own page (from the Timeline's "Travel by Decade").
struct DecadesPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Decades", subtitle: "Pick a decade to see what was in the air: the styles, the turning points, the records.")
                DecadeList()
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Decades", after: 60)
    }
}

struct DecadeCard: View {
    let decade: Int
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let eras = library.eras(inDecade: decade)
        let albums = library.albums(inDecade: decade)
        NavigationLink(value: PhoneRoute.decade(decade)) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) {
                        if albums.isEmpty {
                            ForEach(eras) { e in Rectangle().fill(e.tint) }
                        } else {
                            ForEach(albums.prefix(4)) { a in
                                AlbumCover(album: a, size: 300, cornerRadius: 0)
                            }
                            if albums.count < 4 {
                                ForEach(eras.prefix(4 - albums.count)) { e in Rectangle().fill(e.tint.opacity(0.8)) }
                            }
                        }
                    }
                    .frame(height: 96).clipped()
                    LinearGradient(colors: [.clear, Theme.ink.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                    Text("\(String(decade))s").font(Theme.display(46)).foregroundStyle(Theme.cream)
                        .padding(.horizontal, 14).padding(.bottom, -6)
                }
                .frame(height: 96)
                HStack(spacing: 0) { ForEach(eras) { e in Rectangle().fill(e.tint) } }.frame(height: 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eras.map(\.name).joined(separator: " · ")).font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.cream.opacity(0.85)).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(albums.count) records · \(library.milestones(inDecade: decade).count) milestones")
                        .font(Theme.label(10)).foregroundStyle(Theme.faint)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The \(String(decade))s: \(eras.map(\.name).joined(separator: ", ")). \(albums.count) records.")
        .accessibilityAddTraits(.isButton)
    }
}

struct DecadeDetailView: View {
    let decade: Int
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        let eras = library.eras(inDecade: decade)
        let albums = library.albums(inDecade: decade)
        let milestones = library.milestones(inDecade: decade)
        let artists = library.artists.filter { a in a.active(in: decade) && a.eras.contains { id in eras.contains { $0.id == id } } }
            .sorted { ($0.born ?? 0) < ($1.born ?? 0) }
        let tint = eras.last?.tint ?? Theme.brass

        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) { ForEach(eras) { e in Rectangle().fill(e.tint.opacity(0.85)) } }
                    LinearGradient(colors: [Theme.ink.opacity(0.2), Theme.ink], startPoint: .top, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(String(decade))s").font(Theme.display(118)).foregroundStyle(Theme.cream)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .padding(.bottom, -22)
                            .accessibilityAddTraits(.isHeader)
                        if let station = StationStarter.station(decade: decade, library: library) {
                            PlayRadioButton(station: station)
                        }
                        HStack(spacing: 10) {
                            if decade > library.decades.first! {
                                NavigationLink(value: PhoneRoute.decade(decade - 10)) {
                                    Label("\(String(decade - 10))s", systemImage: "chevron.left")
                                }
                            }
                            Spacer()
                            if decade < library.decades.last! {
                                NavigationLink(value: PhoneRoute.decade(decade + 10)) {
                                    HStack(spacing: 6) { Text("\(String(decade + 10))s"); Image(systemName: "chevron.right") }
                                }
                            }
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(Theme.cream)
                    }
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 4)
                }
                .frame(height: 330)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "In the Air", tint: tint)
                    FlowLayout(spacing: 8) { ForEach(eras) { EraChip(era: $0) } }
                        .padding(.horizontal, Theme.gutter)
                }

                if !milestones.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Turning Points", tint: tint)
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(milestones) { m in
                                HStack(alignment: .firstTextBaseline, spacing: 14) {
                                    Text(String(m.year)).font(Theme.display(26)).foregroundStyle(tint)
                                        .frame(width: 58, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(m.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.cream)
                                        Text(m.detail).font(.system(.subheadline, design: .serif)).foregroundStyle(Theme.muted)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Records of the \(String(decade))s", tint: tint)
                        HRow { ForEach(albums) { AlbumCard(album: $0, width: 150) } }
                    }
                }

                if !artists.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Who Was Playing", tint: tint)
                        HRow { ForEach(artists) { ArtistCard(artist: $0, width: 120) } }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch", tint: tint)
                    VideoStrip(query: "jazz in the \(decade)s performance", tint: tint)
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.ink)
        .revealedTitle("\(String(decade))s", after: 250)
    }
}
