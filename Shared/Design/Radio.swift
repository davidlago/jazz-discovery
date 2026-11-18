import SwiftUI

/// A station as a record's centre label: a circle in its colour, its name on the curve, a spindle hole. It turns
/// while the station plays.
struct StationLabel: View {
    let station: Station
    var size: CGFloat = 140
    @Environment(PlayerController.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let playing = player.station?.id == station.id && player.isPlaying
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !playing || reduceMotion)) { context in
            let angle = playing && !reduceMotion
                ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6) / 6 * 360 : 0
            ZStack {
                // The record around the label.
                Circle().fill(Color.black)
                Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: size * 0.004).padding(size * 0.04)
                Circle().strokeBorder(Color.white.opacity(0.05), lineWidth: size * 0.004).padding(size * 0.08)
                ZStack {
                    Circle().fill(station.tint)
                    Circle().strokeBorder(Theme.ink.opacity(0.35), lineWidth: size * 0.006).padding(size * 0.02)
                    ArcText(text: station.title.uppercased(), radius: size * 0.235, fontSize: size * 0.06, tint: Theme.ink)
                    Text("JAZZ DISCOVERY").font(Theme.label(size * 0.035)).tracking(1).foregroundStyle(Theme.ink.opacity(0.7))
                        .offset(y: size * 0.13)
                    Circle().fill(Theme.ink).frame(width: size * 0.06, height: size * 0.06)
                }
                .padding(size * 0.2)
                .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(station.title)
        .accessibilityValue(playing ? "Playing" : "")
    }
}

/// Starts stations: works out the tracks, then hands them to the player with a way to get more.
@MainActor
enum StationStarter {
    static func play(_ station: Station, library: JazzLibrary, passport: Passport, player: PlayerController) {
        let pool = Programmer.pool(for: station, library: library, isHeard: passport.isHeard)
        var seed = UInt64.random(in: 1...UInt64.max)
        let first = Programmer.sequence(pool, for: station, library: library, seed: seed)
        player.playStation(station, tracks: first) {
            seed &+= 1
            return Programmer.sequence(pool, for: station, library: library, seed: seed)
        }
    }

    /// The station for an era or decade, when it has enough tracks.
    static func station(era id: String, library: JazzLibrary) -> Station? {
        Programmer.station(id: "era-\(id)", library: library, includeNewToYou: false)
    }
    static func station(decade d: Int, library: JazzLibrary) -> Station? {
        Programmer.station(id: "decade-\(d)", library: library, includeNewToYou: false)
    }
}

/// "Play Radio" for an era or decade page.
struct PlayRadioButton: View {
    let station: Station
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player

    var body: some View {
        let playing = player.station?.id == station.id
        Button {
            if playing { player.togglePlayPause() } else { StationStarter.play(station, library: library, passport: passport, player: player) }
        } label: {
            Label(playing && player.isPlaying ? "Pause Radio" : "Play Radio",
                  systemImage: playing && player.isPlaying ? "pause.fill" : "dot.radiowaves.left.and.right")
                #if os(macOS)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 16).padding(.vertical, 9)
                #else
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 16).padding(.vertical, 10)
                #endif
                .foregroundStyle(Theme.ink)
                .background(Capsule().fill(station.tint))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("A station that keeps playing \(station.title.replacingOccurrences(of: " Radio", with: "")), with why each track is there")
    }
}

/// Why the station track playing now is there, with links to its record, artist and era.
struct WhyThisTrack: View {
    var compact = false
    var openAlbum: (String) -> Void
    var openArtist: (String) -> Void
    var openEra: (String) -> Void
    @Environment(PlayerController.self) private var player
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        if let t = player.currentStationTrack, let station = player.station {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(station.title.uppercased()) · WHY THIS TRACK").font(Theme.label(compact ? 9 : 10)).tracking(1.2)
                    .foregroundStyle(station.tint).lineLimit(1)
                Text(Programmer.reason(for: t, library: library))
                    .font(.system(size: compact ? 12 : 13, design: .serif)).italic()
                    .foregroundStyle(Theme.cream.opacity(0.88))
                    .lineLimit(compact ? 2 : 4)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if let id = t.album, library.album(id) != nil {
                        Button("Record") { openAlbum(id) }
                    }
                    if let a = library.artist(ofTrack: t) {
                        Button(a.name) { openArtist(a.id) }
                    }
                    if let e = RoundMaker.eraOf(t, library), let era = library.era(e) {
                        Button(era.name) { openEra(era.id) }
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(station.tint)
                .lineLimit(1)
            }
        }
    }
}

/// Every station, as a wall of labels: The Long Way and New to You first, then eras, decades and instruments.
struct RadioWall: View {
    var labelSize: CGFloat = 130
    var gutter: CGFloat = 40
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player
    /// Cities, rooms and labels with enough recorded there or for them (worked out once: it reads every track).
    @State private var placesAndLabels: [Station] = []

    var body: some View {
        let all = Programmer.stations(library: library, includeNewToYou: passport.heardCount > 0)
        let featured = all.filter { $0.kind == .longWay || $0.kind == .newToYou }
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .top, spacing: 24) {
                ForEach(featured) { s in tile(s, size: labelSize * 1.35, showSubtitle: true) }
            }
            group("Eras", all.filter { if case .era = $0.kind { return true } else { return false } })
            group("Decades", all.filter { if case .decade = $0.kind { return true } else { return false } })
            group("Instruments", all.filter { if case .instrument = $0.kind { return true } else { return false } })
            let places = placesAndLabels.filter { if case .place = $0.kind { return true } else { return false } }
            let labels = placesAndLabels.filter { if case .label = $0.kind { return true } else { return false } }
            if !places.isEmpty { group("Places", places) }
            if !labels.isEmpty { group("Labels", labels) }
        }
        .padding(.horizontal, gutter)
        .task { if placesAndLabels.isEmpty { placesAndLabels = Programmer.placeAndLabelStations(library: library) } }
    }

    private func group(_ title: String, _ stations: [Station]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Rectangle().fill(Theme.brass).frame(width: 22, height: 4)
                Text(title.uppercased()).font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: labelSize, maximum: labelSize + 30), spacing: 18)],
                      alignment: .leading, spacing: 22) {
                ForEach(stations) { tile($0, size: labelSize, showSubtitle: false) }
            }
        }
    }

    private func tile(_ s: Station, size: CGFloat, showSubtitle: Bool) -> some View {
        Button {
            if player.station?.id == s.id { player.togglePlayPause() }
            else { StationStarter.play(s, library: library, passport: passport, player: player) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                StationLabel(station: s, size: size)
                Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                if showSubtitle {
                    Text(s.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
                        .frame(width: size, alignment: .leading)
                }
            }
            .frame(width: size, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A row of stations for the home screen.
struct RadioRow: View {
    var labelSize: CGFloat = 120
    var limit = 6
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player

    var body: some View {
        let all = Programmer.stations(library: library, includeNewToYou: passport.heardCount > 0)
        // The featured ones, then a spread of eras.
        let eras = all.filter { if case .era = $0.kind { return true } else { return false } }
        let picks = Array((all.filter { $0.kind == .longWay || $0.kind == .newToYou } + stride(from: 0, to: eras.count, by: 3).map { eras[$0] }).prefix(limit))
        ForEach(picks) { s in
            Button {
                if player.station?.id == s.id { player.togglePlayPause() }
                else { StationStarter.play(s, library: library, passport: passport, player: player) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    StationLabel(station: s, size: labelSize)
                    Text(s.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                }
                .frame(width: labelSize, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
    }
}
