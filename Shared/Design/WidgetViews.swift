import SwiftUI
import WidgetKit

// The widgets' content and views. They live here, beside the app's, so the Mac app's snapshots can draw them too;
// the widget extension (Widgets/) supplies the timelines.

// MARK: - Today in Jazz

/// The day's lead event, ready to draw.
struct TodayWidgetContent {
    /// The day shown: today, or the nearest day with something.
    let day: Date
    let label: String
    let line: String
    /// For the Lock Screen's one line: "Miles Davis · born 1926".
    let short: String
    /// The day's other events.
    let more: [String]
    let tint: Color
    let initials: String
    let albumID: String?
    let artistID: String?
    /// For a record: what its typographic cover says until the artwork is in.
    var cover: (title: String, artist: String, year: Int)? = nil
    /// The next days with something, for the large widget's empty space.
    var upcoming: [(day: Date, line: String)] = []
    let link: URL
    /// The cover or portrait, small and already fetched (widgets can't load images as they draw).
    var image: Data? = nil
}

extension JazzLibrary {
    /// What Today in Jazz shows on `date`, ranked as the app ranks it (saved and unheard first, from the snapshot).
    func todayWidget(on date: Date, snapshot: WidgetSnapshot? = nil, calendar: Calendar = .current) -> TodayWidgetContent? {
        let cal = self.calendar
        let saved = Set(snapshot?.saved ?? []), heard = Set(snapshot?.heard ?? []), savedArtists = Set(snapshot?.savedArtists ?? [])
        let isSaved: (DayEvent) -> Bool = { e in
            if let a = e.album { return saved.contains(a) }
            return e.artist.map { savedArtists.contains($0) } ?? false
        }
        let isHeard: (DayEvent) -> Bool = { e in e.album.map { heard.contains($0) } ?? false }
        let todays = cal.rank(cal.events(on: date, calendar: calendar), on: date, isSaved: isSaved, isHeard: isHeard, calendar: calendar)
        let near = todays.isEmpty ? cal.nearest(to: date, calendar: calendar) : nil
        let day = near?.date ?? date
        let events = near.map { cal.rank(cal.events(on: $0.date, calendar: calendar), on: $0.date, isSaved: isSaved, isHeard: isHeard,
                                         calendar: calendar) } ?? todays
        guard let lead = events.first else { return nil }

        let album = lead.album.flatMap { self.album($0) }
        let artist = lead.artist.flatMap { self.artist($0) }
        let tint = album.map { color(forEra: $0.era) } ?? artist.map { color(forEra: $0.primaryEra) } ?? Theme.brass
        let short: String
        switch lead.kind {
        case .born: short = "\(artist?.name ?? "Someone") · born \(String(lead.year))"
        case .died: short = "Remembering \(artist?.name ?? "someone")"
        case .recorded: short = album.map { "\($0.title) · \(String(lead.year))" } ?? "A session in \(String(lead.year))"
        case .milestone: short = "\(lead.milestone ?? "A turning point") · \(String(lead.year))"
        }
        let link = route(for: lead).flatMap { r -> URL? in
            switch r {
            case .album(let id): return URL(string: "\(DeepLink.scheme)://album/\(id)")
            case .artist(let id): return URL(string: "\(DeepLink.scheme)://artist/\(id)")
            case .decade(let d): return URL(string: "\(DeepLink.scheme)://decade/\(d)")
            default: return nil
            }
        } ?? URL(string: "\(DeepLink.scheme)://today")!
        return TodayWidgetContent(
            day: day, label: Almanac.label(offset: near?.offset),
            line: line(for: lead, on: day, today: near == nil, calendar: calendar), short: short,
            more: events.dropFirst().prefix(3).map { line(for: $0, on: day, today: near == nil, calendar: calendar) },
            tint: tint, initials: album.map { String($0.title.prefix(1)) } ?? artist?.initials ?? "J",
            albumID: album?.id, artistID: artist?.id, cover: album.map { ($0.title, $0.artistName, $0.year) },
            upcoming: cal.upcoming(from: day, days: 7, calendar: calendar).prefix(3)
                .map { ($0.date, line(for: $0.event, on: $0.date, today: false, calendar: calendar)) },
            link: link)
    }
}

struct TodayWidgetView: View {
    let content: TodayWidgetContent?
    /// Set only when drawn outside WidgetKit (the Mac app's snapshots); a widget takes it from the environment.
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    var body: some View {
        Group {
            if let c = content {
                switch family {
                case .accessoryInline:
                    Label(c.short, systemImage: "music.note")
                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.day.formatted(.dateTime.month(.abbreviated).day()).uppercased()).font(.system(size: 11, weight: .bold))
                            .widgetAccentable()
                        Text(c.line).font(.system(size: 13, design: .serif)).lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .systemSmall:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            DateBadge(date: c.day, size: 52, tint: c.tint)
                            Spacer(minLength: 0)
                            WidgetPicture(content: c).frame(width: 52, height: 52)
                        }
                        Spacer(minLength: 0)
                        Text(c.line).font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(Theme.cream)
                            .lineLimit(4).minimumScaleFactor(0.85)
                    }
                case .systemLarge:
                    VStack(alignment: .leading, spacing: 10) {
                        ZStack(alignment: .bottomLeading) {
                            WidgetPicture(content: c).frame(maxWidth: .infinity).frame(height: 124)
                            DateBadge(date: c.day, size: 76, tint: c.tint).offset(x: 12, y: 40)
                        }
                        .padding(.bottom, 36)
                        Text(c.label).font(Theme.label(10)).tracking(1.4).foregroundStyle(c.tint).widgetAccentable()
                        Text(c.line).font(.system(size: 19, weight: .semibold, design: .serif)).foregroundStyle(Theme.cream)
                            .lineLimit(4).fixedSize(horizontal: false, vertical: true).layoutPriority(2)
                        ForEach(Array(c.more.prefix(2).enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 13, design: .serif)).foregroundStyle(Theme.cream.opacity(0.7)).lineLimit(2)
                        }
                        // Room left: the days ahead.
                        if c.more.count < 2, !c.upcoming.isEmpty {
                            Text("COMING UP").font(Theme.label(9)).tracking(1.3).foregroundStyle(Theme.muted).padding(.top, 4)
                            ForEach(Array(c.upcoming.prefix(2 - c.more.count).enumerated()), id: \.offset) { _, u in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(u.day.formatted(.dateTime.month(.abbreviated).day()).uppercased()).font(Theme.label(9))
                                        .foregroundStyle(c.tint).widgetAccentable().frame(width: 46, alignment: .leading)
                                    Text(u.line).font(.system(size: 12, design: .serif)).foregroundStyle(Theme.cream.opacity(0.75))
                                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                default:   // systemMedium
                    HStack(alignment: .top, spacing: 14) {
                        ZStack(alignment: .bottomLeading) {
                            WidgetPicture(content: c).frame(width: 112, height: 138).offset(x: 22)
                            DateBadge(date: c.day, size: 60, tint: c.tint).offset(x: -4, y: 4)
                        }
                        .frame(width: 134, height: 138, alignment: .topLeading)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(c.label).font(Theme.label(9)).tracking(1.3).foregroundStyle(c.tint).widgetAccentable()
                            Text(c.line).font(.system(size: 15, weight: .semibold, design: .serif)).foregroundStyle(Theme.cream)
                                .lineLimit(5).minimumScaleFactor(0.8)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                Text("Open Jazz Discovery for today in jazz.").font(.system(size: 13, design: .serif)).foregroundStyle(Theme.muted)
            }
        }
        .containerBackground(for: .widget) { Theme.ink }
    }
}

/// The tear-off calendar page; type alone when the widget is tinted, since tinting flattens its colours.
struct DateBadge: View {
    let date: Date
    let size: CGFloat
    let tint: Color
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        if mode == .fullColor {
            CalendarPage(date: date, size: size, tint: tint)
        } else {
            VStack(spacing: 0) {
                Text(date.formatted(.dateTime.month(.abbreviated)).uppercased()).font(Theme.label(size * 0.16)).widgetAccentable()
                Text(date.formatted(.dateTime.day())).font(Theme.display(size * 0.55))
            }
            .frame(width: size)
        }
    }
}

/// The cover, or the portrait in duotone; initials on the era's colour until there's a picture.
struct WidgetPicture: View {
    let content: TodayWidgetContent

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let d = content.image, let img = PlatformImage(data: d) {
                    // Covers centred; portraits from the top, where the face is.
                    let picture = Image(platformImage: img).resizable().widgetAccentedRenderingMode(.desaturated)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: content.albumID != nil ? .center : .top)
                    if content.albumID != nil { picture } else { picture.duotone(content.tint) }
                } else if let c = content.cover {
                    TypographicCover(title: c.title, artist: c.artist, year: c.year, tint: content.tint)
                } else {
                    content.tint.opacity(0.35)
                    Text(content.initials).font(Theme.display(geo.size.width * 0.4)).foregroundStyle(content.tint)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

// MARK: - Continue

struct ContinueWidgetView: View {
    let snapshot: WidgetSnapshot?
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var widgetFamily
    private var family: WidgetFamily { familyOverride ?? widgetFamily }

    var body: some View {
        Group {
            if let p = snapshot?.path {
                card(label: "ON YOUR PATH", title: p.title, tint: Color(hex: p.tint), done: p.done, total: p.total,
                     count: "Stop \(min(p.done + 1, p.total)) of \(p.total)", next: p.nextTitle, nextLine: p.nextSubtitle)
                    .overlay(alignment: .bottomTrailing) {
                        // Plays the next stop in the app, when it's a record or a track.
                        if p.nextPlayable, family == .systemSmall || family == .systemMedium {
                            Button(intent: PlayNextStopIntent()) {
                                Image(systemName: "play.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.ink)
                                    .frame(width: 30, height: 30).background(Circle().fill(Color(hex: p.tint))).widgetAccentable()
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play the next stop")
                        }
                    }
            } else if let e = snapshot?.era {
                card(label: "NEXT STAMP", title: e.name, tint: Color(hex: e.tint), done: e.heard, total: e.total,
                     count: "\(e.heard) of \(e.total) records heard", next: nil, nextLine: "Hear the rest to ink the stamp.")
            } else {
                card(label: "PATHS", title: "Start Here", tint: Theme.brass, done: 0, total: 0, count: nil, next: nil,
                     nextLine: "A few records with something to listen for in each. Open Jazz Discovery to begin.")
            }
        }
        .containerBackground(for: .widget) { Theme.ink }
    }

    @ViewBuilder
    private func card(label: String, title: String, tint: Color, done: Int, total: Int, count: String?, next: String?, nextLine: String) -> some View {
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).widgetAccentable()
                if total > 0 { WidgetBar(done: done, total: total, tint: .primary) }
                Text(next.map { "Next: \($0)" } ?? count ?? nextLine).font(.system(size: 12)).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text(next.map { "Next: \($0)" } ?? title)
        default:
            VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                Text(label).font(Theme.label(9)).tracking(1.3).foregroundStyle(tint).widgetAccentable()
                Text(title).font(Theme.display(family == .systemSmall ? 24 : 28)).foregroundStyle(Theme.cream).lineLimit(2)
                    .minimumScaleFactor(0.7)
                if total > 0 {
                    WidgetBar(done: done, total: total, tint: tint)
                    if let count { Text(count.uppercased()).font(Theme.label(8)).tracking(1).foregroundStyle(Theme.muted) }
                }
                Spacer(minLength: 0)
                if let next {
                    Text("NEXT").font(Theme.label(8)).tracking(1.2).foregroundStyle(tint).widgetAccentable()
                    Text(next).font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.cream).lineLimit(2).padding(.trailing, snapshot?.path?.nextPlayable == true ? 34 : 0)
                    if family != .systemSmall { Text(nextLine).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1) }
                } else {
                    Text(nextLine).font(.system(size: 12, design: .serif)).foregroundStyle(Theme.cream.opacity(0.8))
                        .lineLimit(family == .systemSmall ? 3 : 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Progress as a thin bar (drawn, so it looks the same in a widget, tinted, and in snapshots).
struct WidgetBar: View {
    let done: Int
    let total: Int
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.cream.opacity(0.15))
                if done > 0 && total > 0 {
                    Capsule().fill(tint).widgetAccentable()
                        .frame(width: max(5, geo.size.width * CGFloat(min(done, total)) / CGFloat(total)))
                }
            }
        }
        .frame(height: 5)
        .accessibilityLabel("\(done) of \(total)")
    }
}

extension WidgetSnapshot {
    /// Where the Continue widget goes.
    var link: URL {
        if let p = path { return URL(string: "\(DeepLink.scheme)://path/\(p.id)")! }
        if let e = era { return URL(string: "\(DeepLink.scheme)://era/\(e.id)")! }
        return URL(string: "\(DeepLink.scheme)://paths")!
    }
}
