import SwiftUI

struct TimelineTab: View {
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                HomeHero()

                ContinueSection()

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "The River of Jazz",
                                  subtitle: "130 years of styles flowing, overlapping and splitting. Tap a style to dive in, or a dot for a turning point.")
                    TimelineRiver()
                }

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Start Here", subtitle: "A listening path through the essentials, one record at a time.")
                    HRow(spacing: 16) {
                        ForEach(Array(library.starterPath.enumerated()), id: \.element.id) { i, album in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 6) {
                                    Text(String(format: "%02d", i + 1)).font(Theme.display(24))
                                        .foregroundStyle(library.color(forEra: album.era))
                                    Rectangle().fill(library.color(forEra: album.era).opacity(0.4)).frame(height: 1)
                                }
                                .accessibilityHidden(true)
                                AlbumCard(album: album, width: 150)
                            }
                            .frame(width: 150)
                        }
                    }
                }

                SpotlightCard()

                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Travel by Decade") { SeeAllLink(route: .decades) }
                    HRow(spacing: 12) {
                        ForEach(library.decades, id: \.self) { DecadeTile(decade: $0) }
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.ink)
        .revealedTitle("Jazz Discovery", after: 400)
        .rootToolbar()
    }
}

// MARK: - Hero: rows of faces drifting past

struct HomeHero: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let faceSize = CGSize(width: 118, height: 148)

    /// Two faces per era (its first key artists), dealt into three rows.
    private var rows: [[(Artist, Color)]] {
        var faces: [(Artist, Color)] = []
        for rank in 0..<2 {
            for era in library.eras where era.keyArtists.count > rank {
                if let a = library.artist(era.keyArtists[rank]), !faces.contains(where: { $0.0.id == a.id }) {
                    faces.append((a, era.tint))
                }
            }
        }
        return (0..<3).map { r in faces.enumerated().filter { $0.offset % 3 == r }.map(\.element) }
    }

    var body: some View {
        let rows = rows
        ZStack(alignment: .bottomLeading) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                VStack(spacing: 4) {
                    ForEach(rows.indices, id: \.self) { r in
                        FaceRow(faces: rows[r], size: faceSize, time: reduceMotion ? 0 : t,
                                speed: [9, 6, 11][r % 3], leftward: r % 2 == 0)
                    }
                }
                .padding(.top, 50)
            }
            .frame(height: 520, alignment: .top)
            .clipped()
            .accessibilityHidden(true)

            LinearGradient(stops: [.init(color: Theme.ink.opacity(0.55), location: 0),
                                   .init(color: Theme.ink.opacity(0.15), location: 0.2),
                                   .init(color: Theme.ink.opacity(0.65), location: 0.55),
                                   .init(color: Theme.ink, location: 0.92)],
                           startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 2) {
                Text("A VISUAL HISTORY · 1895 — TODAY").font(Theme.label(11)).tracking(3).foregroundStyle(Theme.brass)
                Text("JAZZ").font(Theme.display(132)).foregroundStyle(Theme.cream)
                    .shadow(color: .black.opacity(0.5), radius: 20)
                    .padding(.vertical, -18)
                    .accessibilityAddTraits(.isHeader)
                Text("\(library.eras.count) eras · \(library.artists.count) artists · \(library.albums.count) essential records")
                    .font(.system(.body, design: .serif)).italic().foregroundStyle(Theme.cream.opacity(0.85))
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 4)
        }
        .frame(height: 520)
    }
}

private struct FaceRow: View {
    let faces: [(Artist, Color)]
    let size: CGSize
    let time: TimeInterval
    let speed: Double
    let leftward: Bool

    var body: some View {
        let spacing: CGFloat = 4
        let setWidth = CGFloat(faces.count) * (size.width + spacing)
        let travel = CGFloat((time * speed).truncatingRemainder(dividingBy: Double(max(setWidth, 1))))
        let x = leftward ? -travel : travel - setWidth
        HStack(spacing: spacing) {
            ForEach(0..<(faces.count * 2), id: \.self) { i in
                let face = faces[i % faces.count]
                ArtistPortrait(artist: face.0, tint: face.1)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .offset(x: x)
        .frame(width: 10, alignment: .leading)  // the row is far wider than the screen; don't let it set the layout
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Spotlight

struct SpotlightCard: View {
    @Environment(JazzLibrary.self) private var library
    @State private var summary: WikiSummary?

    private var artist: Artist? {
        guard !library.artists.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return library.artists[day % library.artists.count]
    }

    var body: some View {
        if let artist {
            let tint = library.color(forEra: artist.primaryEra)
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    ArtistPortrait(artist: artist, tint: tint, large: true)
                        .frame(height: 300)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    LinearGradient(colors: [.clear, Theme.panel], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Kicker(text: "Today's Spotlight", tint: tint)
                        Text(artist.name.uppercased()).font(Theme.display(40)).foregroundStyle(Theme.cream)
                            .lineLimit(2).minimumScaleFactor(0.6)
                    }
                    .padding(.horizontal, 18)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text([artist.instrument, artist.lifespan].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Text(artist.blurb).font(.system(.body, design: .serif)).foregroundStyle(Theme.cream.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                    if let s = summary?.extract, !s.isEmpty {
                        Text(s).font(.footnote).foregroundStyle(Theme.muted).lineLimit(4)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(library.eras.filter { artist.eras.contains($0.id) }) { EraChip(era: $0) }
                        }
                    }
                    .scrollIndicators(.hidden)
                    NavigationLink(value: PhoneRoute.artist(artist.id)) {
                        Label("Meet \(artist.name.components(separatedBy: " ").first ?? artist.name)", systemImage: "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(Theme.ink)
                            .background(Capsule().fill(tint))
                    }
                    .buttonStyle(.pressable)
                    .padding(.top, 4)
                }
                .padding(18)
            }
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(tint.opacity(0.25)))
            .padding(.horizontal, Theme.gutter)
            .task(id: artist.id) { summary = await Wikipedia.shared.summary(artist.wikipedia) }
        }
    }
}

struct DecadeTile: View {
    let decade: Int
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let eras = library.eras(inDecade: decade)
        NavigationLink(value: PhoneRoute.decade(decade)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) { ForEach(eras) { e in Rectangle().fill(e.tint) } }
                    .frame(height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(String(decade))s").font(Theme.display(30)).foregroundStyle(Theme.cream)
                    Text(eras.map(\.name).prefix(2).joined(separator: " · "))
                        .font(.caption2).foregroundStyle(Theme.muted).lineLimit(2)
                        .frame(height: 28, alignment: .topLeading)
                    Text("\(library.albums(inDecade: decade).count) records").font(Theme.label(9)).foregroundStyle(Theme.faint)
                }
                .padding(12)
            }
            .frame(width: 132)
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("The \(String(decade))s, \(eras.map(\.name).joined(separator: ", "))")
    }
}

// MARK: - Timeline river

struct TimelineRiver: View {
    @Environment(JazzLibrary.self) private var library
    @State private var focus: Milestone?

    let firstYear = 1890
    let lastYear = 2027
    let pxPerYear: CGFloat = 15
    let laneHeight: CGFloat = 50
    let topPad: CGFloat = 30

    private func x(_ year: Int) -> CGFloat { CGFloat(year - firstYear) * pxPerYear }
    private func barWidth(_ e: Era) -> CGFloat { max(x(e.end) - x(e.start), CGFloat(e.name.count) * 8.5 + 36) }

    /// Greedy lane packing so overlapping eras stack like river channels.
    private var lanes: [(Era, Int)] {
        var laneEnds: [CGFloat] = []
        var out: [(Era, Int)] = []
        for e in library.eras {
            let start = x(e.start)
            let end = start + barWidth(e)
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
        let milestoneTop = topPad + CGFloat(laneCount) * laneHeight + 22
        let totalHeight = milestoneTop + 86
        let width = x(lastYear)

        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    // Decade grid
                    ForEach(Array(stride(from: firstYear, through: 2020, by: 10)), id: \.self) { d in
                        Rectangle().fill(Theme.panelHi.opacity(0.7)).frame(width: 1, height: totalHeight - 10)
                            .offset(x: x(d))
                        Text("\(String(d))s").font(Theme.label(10)).foregroundStyle(Theme.faint)
                            .offset(x: x(d) + 5, y: 4)
                    }
                    // Era channels
                    ForEach(packed, id: \.0.id) { era, lane in
                        NavigationLink(value: PhoneRoute.era(era.id)) {
                            RiverBar(era: era, width: barWidth(era))
                        }
                        .buttonStyle(PressableStyle(scale: 0.97))
                        .offset(x: x(era.start), y: topPad + CGFloat(lane) * laneHeight)
                        .accessibilityLabel("\(era.name), \(era.years). \(era.tagline)")
                    }
                    // Milestone axis
                    Rectangle().fill(Theme.muted.opacity(0.4)).frame(width: width, height: 1)
                        .offset(y: milestoneTop)
                    ForEach(Array(library.milestones.enumerated()), id: \.element.id) { i, m in
                        MilestoneDot(milestone: m, row: i % 3, focused: focus == m) {
                            withAnimation(.spring(response: 0.3)) { focus = (focus == m ? nil : m) }
                        }
                        .offset(x: x(m.year) - 14, y: milestoneTop - 14)
                    }
                }
                .frame(width: width + 30, height: totalHeight, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
            .sensoryFeedback(.selection, trigger: focus)

            // Caption
            HStack(alignment: .top, spacing: 12) {
                if let m = focus {
                    Text(String(m.year)).font(Theme.display(30)).foregroundStyle(Theme.brass)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.title).font(.subheadline.weight(.bold)).foregroundStyle(Theme.cream)
                        Text(m.detail).font(.footnote).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.opacity)
                } else {
                    Image(systemName: "hand.draw").foregroundStyle(Theme.faint)
                    Text("Swipe sideways to travel in time.")
                        .font(.footnote).foregroundStyle(Theme.faint)
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44, alignment: .top)
            .padding(.horizontal, Theme.gutter)
            .animation(.easeInOut(duration: 0.2), value: focus)
        }
    }
}

private struct MilestoneDot: View {
    let milestone: Milestone
    let row: Int
    let focused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Theme.brass.opacity(0.35)).frame(width: 1, height: 12 + CGFloat(row) * 18)
                    .offset(x: 13.5, y: 22)
                Circle().fill(focused ? Theme.cream : Theme.brass).frame(width: 10, height: 10)
                    .scaleEffect(focused ? 1.6 : 1)
                    .offset(x: 9, y: 9)
                Text(String(milestone.year)).font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(focused ? Theme.cream : Theme.muted)
                    .fixedSize()
                    .offset(x: 2, y: 36 + CGFloat(row) * 18)
            }
            .frame(width: 30, height: 86, alignment: .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(String(milestone.year)): \(milestone.title)")
        .accessibilityHint(milestone.detail)
    }
}

private struct RiverBar: View {
    let era: Era
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(era.name.uppercased()).font(Theme.display(15, weight: .heavy)).lineLimit(1).fixedSize()
                Text(era.years).font(.system(size: 9, weight: .semibold).monospacedDigit()).opacity(0.75)
            }
            .foregroundStyle(Theme.ink)
            .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .frame(width: width, height: 40)
        .background(LinearGradient(colors: [era.tint, era.tint.opacity(0.75)], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .trailing) {
            // eras fade out rather than stop dead
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.6)], startPoint: .leading, endPoint: .trailing).frame(width: 30)
        }
        .clipShape(Capsule())
        .contentShape(Capsule())
    }
}

/// Once anything is heard: the next stop on Start Here, and the doors out of the last record you heard.
struct ContinueSection: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        if passport.heardCount > 0 {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Continue", subtitle: "\(passport.heardCount) of \(library.albums.count) records heard.") {
                    SeeAllLink(route: .passport)
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let stop = passport.nextStop(library: library) {
                        NavigationLink(value: PhoneRoute.album(stop.album.id)) {
                            HStack(spacing: 12) {
                                AlbumCover(album: stop.album, size: 200, cornerRadius: 4).frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("START HERE · \(String(format: "%02d", stop.number))").font(Theme.label(10)).tracking(1.2)
                                        .foregroundStyle(library.color(forEra: stop.album.era))
                                    Text(stop.album.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
                                    Text(stop.album.artistName).font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.faint)
                            }
                        }
                        .buttonStyle(.pressable)
                    }
                    if let last = passport.lastHeard(library: library) {
                        Text("AFTER \(last.title.uppercased())").font(Theme.label(10)).tracking(1.2).foregroundStyle(Theme.muted)
                            .lineLimit(1).padding(.top, 6)
                        DoorsList(album: last, stacked: true, compact: true) { router.go(.album($0)) }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
    }
}
