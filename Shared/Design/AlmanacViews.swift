import SwiftUI

/// Today in jazz: who was born, what was recorded. Falls back to the nearest day with something, then to nothing
/// (the caller shows the spotlight instead).
struct TodayCard: View {
    var compact = false
    var date: Date = .now
    var open: (Route) -> Void
    var openAlmanac: () -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(PlayerController.self) private var player

    var body: some View {
        let cal = library.calendar
        let todays = cal.rank(cal.events(on: date), on: date, isSaved: saved, isHeard: heard)
        let near = todays.isEmpty ? cal.nearest(to: date) : nil
        let day = near?.date ?? date
        let events = near.map { cal.rank(cal.events(on: $0.date), on: $0.date, isSaved: saved, isHeard: heard) } ?? todays
        if let lead = events.first {
            let tint = tint(for: lead)
            let layout = compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            layout {
                HStack(alignment: .top, spacing: 16) {
                    CalendarPage(date: day, size: compact ? 96 : 130, tint: tint)
                    picture(lead).frame(width: compact ? 96 : 150, height: compact ? 96 : 150)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(Almanac.label(offset: near?.offset)).font(Theme.label(11)).tracking(1.6).foregroundStyle(tint)
                    Text(library.line(for: lead, on: day, today: near == nil))
                        .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .serif)).foregroundStyle(Theme.cream)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(events.dropFirst().prefix(3).enumerated()), id: \.offset) { _, e in
                        Button { if let r = library.route(for: e) { open(r) } } label: {
                            Text(library.line(for: e, on: day, today: near == nil)).font(.system(size: 13, design: .serif))
                                .foregroundStyle(Theme.cream.opacity(0.75)).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 12) {
                        Button { play(lead) } label: {
                            Label("Play", systemImage: "play.fill").font(.system(size: 13, weight: .bold))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .foregroundStyle(Theme.ink).background(Capsule().fill(tint))
                        }
                        .buttonStyle(.plain)
                        if let r = library.route(for: lead) {
                            Button("Open") { open(r) }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream)
                        }
                        Button("The Almanac") { openAlmanac() }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                        Spacer(minLength: 0)
                        ShareCardButton(card: .day(lead, day))
                    }
                }
            }
            .padding(compact ? 16 : 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        }
    }

    private func saved(_ e: DayEvent) -> Bool {
        if let a = e.album { return passport.isSaved(a) }
        if let a = e.artist { return passport.isSaved(artist: a) }
        return false
    }
    private func heard(_ e: DayEvent) -> Bool { e.album.map { passport.isHeard($0) } ?? false }


    private func tint(for e: DayEvent) -> Color {
        if let a = e.album.flatMap({ library.album($0) }) { return library.color(forEra: a.era) }
        if let a = e.artist.flatMap({ library.artist($0) }) { return library.color(forEra: a.primaryEra) }
        return Theme.brass
    }

    @ViewBuilder private func picture(_ e: DayEvent) -> some View {
        if let a = e.album.flatMap({ library.album($0) }) {
            AlbumCover(album: a, size: 400, cornerRadius: 6)
        } else if let a = e.artist.flatMap({ library.artist($0) }) {
            ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra)).clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func play(_ e: DayEvent) {
        if let a = e.album.flatMap({ library.album($0) }) {
            Task { if let c = await ITunes.shared.album(for: a) { player.playAlbum(c, tracks: []) } }
        } else if let a = e.artist.flatMap({ library.artist($0) }) {
            let tracks = a.signatureTracks.compactMap { library.track($0, by: a.name)?.track }
            if !tracks.isEmpty { player.play(tracks) }
        }
    }
}

/// The next seven days, one line each.
struct ThisWeekStrip: View {
    var date: Date = .now
    var open: (Route) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let days = library.calendar.upcoming(from: date)
        ForEach(days, id: \.date) { d in
            Button { if let r = library.route(for: d.event) { open(r) } } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(d.date.formatted(.dateTime.weekday(.abbreviated).day()).uppercased()).font(Theme.label(10)).tracking(1.2)
                        .foregroundStyle(Theme.brass)
                    Text(library.line(for: d.event, on: d.date, today: false)).font(.system(size: 13, design: .serif))
                        .foregroundStyle(Theme.cream).lineLimit(4).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(width: 190, height: 120, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            }
            .buttonStyle(.plain)
        }
    }
}

/// The year at a glance: twelve months, a dot on each day that has something, coloured by its lead's era.
struct AlmanacGrid: View {
    @Binding var selected: DateComponents
    var columns: Int = 4
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let cal = Calendar(identifier: .gregorian)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns), alignment: .leading, spacing: 22) {
            ForEach(1...12, id: \.self) { m in
                let first = cal.date(from: DateComponents(year: 2024, month: m, day: 1))!
                let daysIn = cal.range(of: .day, in: .month, for: first)!.count
                let offset = (cal.component(.weekday, from: first) + 6) % 7
                VStack(alignment: .leading, spacing: 6) {
                    Text(first.formatted(.dateTime.month(.wide)).uppercased()).font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.cream)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                        ForEach(0..<(offset + daysIn), id: \.self) { i in
                            if i < offset { Color.clear.frame(height: 20) } else { dayCell(m, i - offset + 1) }
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ m: Int, _ d: Int) -> some View {
        let events = library.calendar.events(month: m, day: d)
        let isSelected = selected.month == m && selected.day == d
        let tint: Color = events.first.flatMap { e in
            e.album.flatMap { library.album($0) }.map { library.color(forEra: $0.era) }
                ?? e.artist.flatMap { library.artist($0) }.map { library.color(forEra: $0.primaryEra) }
        } ?? Theme.panelHi
        return Button { selected = DateComponents(month: m, day: d) } label: {
            Text("\(d)").font(.system(size: 10, weight: isSelected ? .bold : .regular).monospacedDigit())
                .foregroundStyle(events.isEmpty ? Theme.faint : Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 20)
                .background(RoundedRectangle(cornerRadius: 4).fill(events.isEmpty ? Theme.panel : tint.opacity(0.85)))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isSelected ? Theme.cream : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(d), \(events.count) events")
    }
}

/// The events of one day, as lines.
struct AlmanacDayList: View {
    let month: Int
    let day: Int
    var open: (Route) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: Calendar.current.component(.year, from: .now), month: month, day: day)) ?? .now
        let events = library.calendar.rank(library.calendar.events(month: month, day: day), on: date)
        VStack(alignment: .leading, spacing: 10) {
            Text(date.formatted(.dateTime.month(.wide).day()).uppercased()).font(Theme.display(28)).foregroundStyle(Theme.cream)
            if events.isEmpty {
                Text("Nothing in the guide happened on this day yet.").font(.system(size: 14)).foregroundStyle(Theme.muted)
            }
            ForEach(Array(events.enumerated()), id: \.offset) { _, e in
                Button { if let r = library.route(for: e) { open(r) } } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: e.kind == .recorded ? "opticaldisc" : e.kind == .born ? "birthday.cake" : "leaf")
                            .foregroundStyle(Theme.brass).frame(width: 20)
                        Text(library.line(for: e, on: date, today: false)).font(.system(size: 15, design: .serif))
                            .foregroundStyle(Theme.cream).multilineTextAlignment(.leading)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Share cards

/// What a share card shows.
enum ShareCardContent {
    case day(DayEvent, Date)
    case record(Album)
    case artist(Artist)
}

/// A poster, 1080 × 1350, in the app's style: what's already public in the app, and a link back.
struct ShareCardView: View {
    let content: ShareCardContent
    var cover: Image?
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let tint = tintColor
        VStack(alignment: .leading, spacing: 40) {
            Text("JAZZ DISCOVERY").font(Theme.label(30)).tracking(10).foregroundStyle(tint)
            switch content {
            case .day(let e, let date):
                CalendarPage(date: date, size: 300, tint: tint)
                Text(library.line(for: e, on: date, today: false)).font(.system(size: 64, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.cream).fixedSize(horizontal: false, vertical: true)
            case .record(let a):
                if let cover { cover.resizable().aspectRatio(1, contentMode: .fit).frame(width: 600).clipShape(RoundedRectangle(cornerRadius: 12)) }
                Text(a.title.uppercased()).font(Theme.display(110)).foregroundStyle(Theme.cream).lineLimit(2).minimumScaleFactor(0.5)
                Text("\(a.artistName) · \(String(a.year))").font(.system(size: 44, design: .serif)).italic().foregroundStyle(tint)
                Text(Programmer.firstSentence(a.why)).font(.system(size: 40, design: .serif)).foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            case .artist(let a):
                Text(a.name.uppercased()).font(Theme.display(150)).foregroundStyle(Theme.cream).lineLimit(3).minimumScaleFactor(0.4)
                Text("\(a.instrument) · \(library.fullDates(of: a.id) ?? a.lifespan)").font(.system(size: 40, design: .serif)).italic().foregroundStyle(tint)
                Text(Programmer.firstSentence(a.blurb)).font(.system(size: 44, design: .serif)).foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("Artwork from Apple Music. Jazz Discovery, a visual guide to 130 years of jazz.")
                .font(.system(size: 22)).foregroundStyle(Theme.faint)
        }
        .padding(80)
        .frame(width: 1080, height: 1350, alignment: .topLeading)
        .background(Theme.ink)
    }

    private var tintColor: Color {
        switch content {
        case .day(let e, _):
            return e.album.flatMap { library.album($0) }.map { library.color(forEra: $0.era) }
                ?? e.artist.flatMap { library.artist($0) }.map { library.color(forEra: $0.primaryEra) } ?? Theme.brass
        case .record(let a): return library.color(forEra: a.era)
        case .artist(let a): return library.color(forEra: a.primaryEra)
        }
    }
}

/// Renders a share card and offers it with a link to the page.
struct ShareCardButton: View {
    let card: ShareCardContent
    @Environment(JazzLibrary.self) private var library
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, subject: Text("Jazz Discovery"), message: Text(link.absoluteString),
                          preview: SharePreview(title, image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up").font(.system(size: 13, weight: .semibold))
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .task(id: title) { await render() }
    }

    private var title: String {
        switch card {
        case .day(_, let d): return "Today in Jazz, \(d.formatted(.dateTime.month(.wide).day()))"
        case .record(let a): return a.title
        case .artist(let a): return a.name
        }
    }

    private var link: URL {
        switch card {
        case .day(let e, _): return URL(string: e.album.map { "jazzdiscovery://album/\($0)" } ?? e.artist.map { "jazzdiscovery://artist/\($0)" } ?? "jazzdiscovery://almanac")!
        case .record(let a): return URL(string: "jazzdiscovery://album/\(a.id)")!
        case .artist(let a): return URL(string: "jazzdiscovery://artist/\(a.id)")!
        }
    }

    @MainActor
    private func render() async {
        var cover: Image?
        if case .record(let a) = card, let c = await ITunes.shared.album(for: a), let url = c.artwork(1000),
           let img = await ImageStore.shared.load(url) {
            #if os(macOS)
            cover = Image(nsImage: img)
            #else
            cover = Image(uiImage: img)
            #endif
        }
        let renderer = ImageRenderer(content: ShareCardView(content: card, cover: cover).environment(library))
        renderer.scale = 1
        if let cg = renderer.cgImage { image = Image(decorative: cg, scale: 1) }
    }
}
