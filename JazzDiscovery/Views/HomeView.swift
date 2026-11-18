import SwiftUI

struct HomeView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                HomeHero()

                ContinueSection()

                HowToListenHome()

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader(title: "Paths", subtitle: "Journeys with a point of view, a few stops each.")
                        Spacer()
                        Button("All Paths →") { router.show(.paths) }.buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brass)
                    }
                    .padding(.horizontal, 40)
                    HRow(spacing: 16) { PathsRow { router.go(.journey($0)) } }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        SectionHeader(title: "Radio", subtitle: "Stations that keep playing, and say why each track is there.")
                        Spacer()
                        Button("All Stations →") { router.show(.radio) }.buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.brass)
                    }
                    .padding(.horizontal, 40)
                    HRow(spacing: 22) { RadioRow() }
                }

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "The River of Jazz",
                                  subtitle: "130 years of styles flowing, overlapping and splitting. Click a style to dive in; hover a dot for a turning point.")
                        .padding(.horizontal, 40)
                    TimelineRiver()
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Start Here", subtitle: "A listening path through the essentials — one record at a time, in order.")
                        .padding(.horizontal, 40)
                    HRow(spacing: 22) {
                        ForEach(Array(library.starterPath.enumerated()), id: \.element.id) { i, album in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(String(format: "%02d", i + 1)).font(Theme.display(26))
                                        .foregroundStyle(library.color(forEra: album.era))
                                    Rectangle().fill(library.color(forEra: album.era).opacity(0.4)).frame(height: 1)
                                }
                                AlbumCard(album: album, width: 190)
                            }
                            .frame(width: 190)
                        }
                    }
                }

                SpotlightCard()

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Travel by Decade").padding(.horizontal, 40)
                    HRow(spacing: 14) {
                        ForEach(library.decades, id: \.self) { d in DecadeTile(decade: d) }
                    }
                }
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Discover")
    }
}

struct HomeHero: View {
    @Environment(JazzLibrary.self) private var library

    private var faces: [(Artist, Color)] {
        // Each era's first key artist who isn't already shown: Miles Davis leads three eras.
        var shown = Set<String>()
        return library.eras.compactMap { era in
            guard let artist = era.keyArtists.lazy.compactMap({ library.artist($0) }).first(where: { !shown.contains($0.id) })
            else { return nil }
            shown.insert(artist.id)
            return (artist, era.tint)
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            GeometryReader { geo in
                let cols = max(1, faces.count / 2)
                let w = geo.size.width / CGFloat(cols)
                let h = geo.size.height / 2
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<cols, id: \.self) { col in
                                let i = row * cols + col
                                if i < faces.count {
                                    ArtistPortrait(artist: faces[i].0, tint: faces[i].1)
                                        .frame(width: w, height: h).clipped()
                                }
                            }
                        }
                    }
                }
            }
            LinearGradient(colors: [Theme.ink.opacity(0.1), Theme.ink.opacity(0.55), Theme.ink],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [Theme.ink.opacity(0.85), .clear], startPoint: .leading, endPoint: .center)
            VStack(alignment: .leading, spacing: 4) {
                Text("A VISUAL HISTORY · 1895 — TODAY").font(Theme.label(12)).tracking(4).foregroundStyle(Theme.brass)
                Text("JAZZ").font(Theme.display(150)).foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.5), radius: 20)
                    .padding(.vertical, -20)
                Text("\(library.eras.count) eras · \(library.artists.count) artists · \(library.albums.count) essential records")
                    .font(Theme.serif(20)).italic().foregroundStyle(Theme.cream.opacity(0.85))
            }
            .padding(40)
        }
        .frame(height: 440)
        .clipped()
    }
}

struct SpotlightCard: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var summary: WikiSummary?

    private var artist: Artist? {
        guard !library.artists.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return library.artists[day % library.artists.count]
    }

    var body: some View {
        if let artist {
            let tint = library.color(forEra: artist.primaryEra)
            HStack(alignment: .top, spacing: 30) {
                ArtistPortrait(artist: artist, tint: tint)
                    .frame(width: 260, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 12) {
                    Text("TODAY'S SPOTLIGHT").font(Theme.label(12)).tracking(3).foregroundStyle(tint)
                    Text(artist.name.uppercased()).font(Theme.display(54)).foregroundStyle(Theme.cream)
                    Text("\(artist.instrument) · \(artist.lifespan)").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    Text(artist.blurb).font(Theme.serif(18)).foregroundStyle(Theme.cream.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                    if let s = summary?.extract, !s.isEmpty {
                        Text(s).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(4)
                    }
                    HStack(spacing: 8) {
                        ForEach(library.eras.filter { artist.eras.contains($0.id) }) { EraChip(era: $0) }
                    }
                    Button { router.go(.artist(artist.id)) } label: {
                        Label("Meet \(artist.name.components(separatedBy: " ").first ?? artist.name)", systemImage: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .foregroundStyle(Theme.ink).background(Capsule().fill(tint))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(28)
            .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(tint.opacity(0.25)))
            .padding(.horizontal, 40)
            .task(id: artist.id) { summary = await Wikipedia.shared.summary(artist.wikipedia) }
        }
    }
}

struct DecadeTile: View {
    let decade: Int
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let eras = library.eras(inDecade: decade)
        Button { router.go(.decade(decade)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(eras) { e in Rectangle().fill(e.tint) }
                }
                .frame(height: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(decade))s").font(Theme.display(34)).foregroundStyle(Theme.cream)
                    Text(eras.map(\.name).prefix(2).joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(2)
                        .frame(height: 30, alignment: .topLeading)
                    Text("\(library.albums(inDecade: decade).count) records").font(Theme.label(10)).foregroundStyle(Theme.faint)
                }
                .padding(12)
            }
            .frame(width: 170)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .hoverLift()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Timeline river

struct TimelineRiver: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var focus: Focus?

    enum Focus: Equatable { case era(Era), milestone(Milestone) }

    let firstYear = 1890
    let lastYear = 2027
    let pxPerYear: CGFloat = 17
    let laneHeight: CGFloat = 58
    let topPad: CGFloat = 34

    private func x(_ year: Int) -> CGFloat { CGFloat(year - firstYear) * pxPerYear }

    /// Greedy lane packing so overlapping eras stack like river channels.
    private var lanes: [(Era, Int)] {
        var laneEnds: [CGFloat] = []
        var out: [(Era, Int)] = []
        for e in library.eras {
            let start = x(e.start)
            let end = max(x(e.end), start + CGFloat(e.name.count) * 9 + 40)
            if let i = laneEnds.firstIndex(where: { $0 + 8 < start }) {
                laneEnds[i] = end; out.append((e, i))
            } else {
                laneEnds.append(end); out.append((e, laneEnds.count - 1))
            }
        }
        return out
    }

    var body: some View {
        let packed = lanes
        let laneCount = (packed.map(\.1).max() ?? 0) + 1
        let lanesHeight = CGFloat(laneCount) * laneHeight
        let milestoneTop = topPad + lanesHeight + 26
        let totalHeight = milestoneTop + 92
        let width = x(lastYear)

        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Decade grid
                    ForEach(Array(stride(from: firstYear, through: 2020, by: 10)), id: \.self) { d in
                        Rectangle().fill(Theme.panelHi.opacity(0.7)).frame(width: 1, height: totalHeight - 10)
                            .offset(x: x(d))
                        Text("\(String(d))s").font(Theme.label(11)).foregroundStyle(Theme.faint)
                            .offset(x: x(d) + 6, y: 6)
                    }
                    // Era channels
                    ForEach(packed, id: \.0.id) { era, lane in
                        EraBar(era: era, width: max(x(era.end) - x(era.start), CGFloat(era.name.count) * 9 + 40),
                               focused: focus == .era(era), dimmed: focus != nil && focus != .era(era))
                            .offset(x: x(era.start), y: topPad + CGFloat(lane) * laneHeight)
                            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { focus = h ? .era(era) : (focus == .era(era) ? nil : focus) } }
                            .onTapGesture { router.go(.era(era.id)) }
                    }
                    // Milestone axis
                    Rectangle().fill(Theme.muted.opacity(0.4)).frame(width: width, height: 1)
                        .offset(y: milestoneTop)
                    ForEach(Array(library.milestones.enumerated()), id: \.element.id) { i, m in
                        let isFocused = focus == .milestone(m)
                        let row = CGFloat(i % 3)
                        ZStack(alignment: .topLeading) {
                            Rectangle().fill(Theme.brass.opacity(0.35)).frame(width: 1, height: 14 + row * 20)
                                .offset(x: 4.5, y: 9)
                            Circle().fill(isFocused ? Theme.cream : Theme.brass).frame(width: 10, height: 10)
                                .scaleEffect(isFocused ? 1.5 : 1)
                            Text(String(m.year)).font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(isFocused ? Theme.cream : Theme.muted)
                                .fixedSize()
                                .offset(x: -6, y: 24 + row * 20)
                        }
                        .frame(width: 30, height: 90, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .offset(x: x(m.year) - 5, y: milestoneTop - 5)
                        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { focus = h ? .milestone(m) : (focus == .milestone(m) ? nil : focus) } }
                    }
                }
                .frame(width: width + 40, height: totalHeight, alignment: .topLeading)
                .padding(.horizontal, 40)
            }
            .scrollIndicators(.visible)

            // Caption panel
            HStack(alignment: .top, spacing: 14) {
                switch focus {
                case .era(let e)?:
                    RoundedRectangle(cornerRadius: 2).fill(e.tint).frame(width: 6, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(e.name) · \(e.years)").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cream)
                        Text(e.tagline).font(Theme.serif(15)).italic().foregroundStyle(Theme.muted)
                    }
                case .milestone(let m)?:
                    Text(String(m.year)).font(Theme.display(34)).foregroundStyle(Theme.brass)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.title).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cream)
                        Text(m.detail).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                case nil:
                    Image(systemName: "hand.point.up.left").foregroundStyle(Theme.faint)
                    Text("Hover the river to read it. Scroll sideways to travel in time.")
                        .font(.system(size: 13)).foregroundStyle(Theme.faint)
                }
                Spacer()
            }
            .frame(height: 48, alignment: .top)
            .padding(.horizontal, 40)
        }
    }
}

struct EraBar: View {
    let era: Era
    let width: CGFloat
    let focused: Bool
    let dimmed: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(era.name.uppercased()).font(Theme.display(16, weight: .heavy)).lineLimit(1).fixedSize()
                Text(era.years).font(.system(size: 10, weight: .semibold).monospacedDigit()).opacity(0.75)
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: 46)
        .background(
            LinearGradient(colors: [era.tint, era.tint.opacity(0.75)], startPoint: .leading, endPoint: .trailing)
        )
        .overlay(alignment: .trailing) {
            // tapering tail: eras fade out rather than stop dead
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.6)], startPoint: .leading, endPoint: .trailing).frame(width: 30)
        }
        .clipShape(Capsule())
        .shadow(color: era.tint.opacity(focused ? 0.6 : 0), radius: 14)
        .scaleEffect(focused ? 1.03 : 1, anchor: .leading)
        .opacity(dimmed ? 0.45 : 1)
        .contentShape(Capsule())
        .help("\(era.name) — \(era.tagline)")
    }
}

/// Once anything is heard: the next stop on Start Here, and the doors out of the last record you heard.
struct ContinueSection: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(Router.self) private var router

    var body: some View {
        if passport.heardCount > 0 {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Continue", subtitle: "\(passport.heardCount) of \(library.albums.count) records heard.")
                HStack(alignment: .top, spacing: 28) {
                    if let stop = passport.nextStop(library: library) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("START HERE · \(String(format: "%02d", stop.number))").font(Theme.label(10)).tracking(1.4)
                                .foregroundStyle(library.color(forEra: stop.album.era))
                            AlbumCard(album: stop.album, width: 170)
                        }
                    }
                    if let last = passport.lastHeard(library: library) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AFTER \(last.title.uppercased())").font(Theme.label(10)).tracking(1.4).foregroundStyle(Theme.muted)
                                .lineLimit(1)
                            DoorsList(album: last, stacked: true, compact: true) { router.go(.album($0)) }
                                .frame(maxWidth: 560)
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
        }
    }
}

/// For someone who hasn't heard anything yet: how to listen to a jazz performance, in five steps.
struct HowToListenHome: View {
    @Environment(Passport.self) private var passport
    @Environment(Router.self) private var router

    var body: some View {
        if passport.heardCount == 0 {
            HowToListenCard { router.go(.term($0)) }.padding(.horizontal, 40)
        }
    }
}
