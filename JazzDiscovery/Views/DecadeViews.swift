import SwiftUI

struct DecadesView: View {
    @Environment(JazzLibrary.self) private var library
    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 400), spacing: 18)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("DECADES").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("Pick a decade to see what was in the air: the styles, the turning points, the records.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(library.decades, id: \.self) { d in DecadeCard(decade: d) }
                }
            }
            .padding(.horizontal, 40).padding(.bottom, 40)
        }
        .background(Theme.ink)
        .navigationTitle("Decades")
    }
}

struct DecadeCard: View {
    let decade: Int
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let eras = library.eras(inDecade: decade)
        let albums = library.albums(inDecade: decade)
        Button { router.go(.decade(decade)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) {
                        if albums.isEmpty {
                            DecadeFaces(decade: decade)
                        } else {
                            ForEach(albums.prefix(4)) { a in
                                AlbumCover(album: a, size: 300).clipShape(Rectangle())
                            }
                        }
                    }
                    .frame(height: 120).clipped()
                    LinearGradient(colors: [.clear, Theme.ink.opacity(0.9)], startPoint: .top, endPoint: .bottom)
                    Text("\(String(decade))s").font(Theme.display(52)).foregroundStyle(Theme.cream)
                        .padding(.horizontal, 14).padding(.bottom, -4)
                }
                .frame(height: 120)
                HStack(spacing: 0) { ForEach(eras) { e in Rectangle().fill(e.tint) } }.frame(height: 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(eras.map(\.name).joined(separator: " · ")).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.cream.opacity(0.85)).lineLimit(2)
                        .frame(height: 32, alignment: .topLeading)
                    Text("\(library.decadeCount(decade)) · \(library.milestones(inDecade: decade).count) milestones")
                        .font(Theme.label(10)).foregroundStyle(Theme.faint)
                }
                .padding(14)
            }
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .hoverLift(1.02)
        }
        .buttonStyle(.plain)
    }
}

struct DecadeDetailView: View {
    let decade: Int
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let eras = library.eras(inDecade: decade)
        let albums = library.albums(inDecade: decade)
        let milestones = library.milestones(inDecade: decade)
        let artists = library.artists.filter { a in a.active(in: decade) && a.eras.contains { id in eras.contains { $0.id == id } } }
            .sorted { ($0.born ?? 0) < ($1.born ?? 0) }
        let tint = eras.last?.tint ?? Theme.brass

        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                ZStack(alignment: .bottomLeading) {
                    HStack(spacing: 0) { ForEach(eras) { e in Rectangle().fill(e.tint.opacity(0.85)) } }
                    LinearGradient(colors: [.clear, Theme.ink], startPoint: .top, endPoint: .bottom)
                    HStack(alignment: .bottom) {
                        Text("\(String(decade))s").font(Theme.display(160)).foregroundStyle(Theme.cream)
                            .padding(.bottom, -30)
                        Spacer()
                        HStack(spacing: 10) {
                            if let station = StationStarter.station(decade: decade, library: library) {
                                PlayRadioButton(station: station)
                            }
                            if decade > library.decades.first! {
                                Button { router.go(.decade(decade - 10)) } label: { Label("\(String(decade - 10))s", systemImage: "chevron.left") }
                            }
                            if decade < library.decades.last! {
                                Button { router.go(.decade(decade + 10)) } label: { Label("\(String(decade + 10))s", systemImage: "chevron.right") }
                                    .labelStyle(TrailingIconLabelStyle())
                            }
                        }
                        .buttonStyle(.bordered).controlSize(.large)
                    }
                    .padding(.horizontal, 40).padding(.bottom, 20)
                }
                .frame(height: 300)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "In the Air", tint: tint)
                    FlowLayout(spacing: 8) { ForEach(eras) { EraChip(era: $0) } }
                }
                .padding(.horizontal, 40)

                if !milestones.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "Turning Points", tint: tint)
                        ForEach(milestones) { m in
                            HStack(alignment: .firstTextBaseline, spacing: 18) {
                                Text(String(m.year)).font(Theme.display(30)).foregroundStyle(tint).frame(width: 80, alignment: .leading)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cream)
                                    Text(m.detail).font(Theme.serif(15)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }

                if !albums.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Records of the \(String(decade))s", tint: tint).padding(.horizontal, 40)
                        HRow { ForEach(albums) { AlbumCard(album: $0, width: 200) } }
                    }
                }

                if !artists.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Who Was Playing", tint: tint).padding(.horizontal, 40)
                        HRow { ForEach(artists) { ArtistCard(artist: $0, width: 150) } }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch", tint: tint).padding(.horizontal, 40)
                    VideoStrip(query: "jazz in the \(decade)s performance", tint: tint)
                }
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("\(String(decade))s")
    }
}

struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.title; configuration.icon }
    }
}
