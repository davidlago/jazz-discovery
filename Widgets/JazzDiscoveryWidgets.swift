import SwiftUI
import WidgetKit

/// The widgets, on the iPhone (Home Screen, Lock Screen, StandBy) and the Mac (desktop, Notification Center).
@main
struct JazzDiscoveryWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        ContinueWidget()
    }
}

/// The library the widgets need: the eras, artists and records, the sessions (for "began recording") and the almanac.
/// The rest of the app's data (tracks, tracklists, the Songbook…) isn't in the extension, which has little memory.
enum WidgetLibrary {
    static let shared: JazzLibrary = {
        guard let url = Bundle.main.url(forResource: "jazz", withExtension: "json"), let d = try? Data(contentsOf: url),
              let data = try? JSONDecoder().decode(JazzData.self, from: d) else { fatalError("jazz.json missing from the widgets") }
        return JazzLibrary(data: data,
                           sessions: JazzLibrary.optional([String: Session].self, "sessions", in: .main) ?? [:],
                           almanac: JazzLibrary.optional(AlmanacData.self, "almanac", in: .main) ?? AlmanacData())
    }()
}

// MARK: - Today in Jazz

struct TodayEntry: TimelineEntry {
    let date: Date
    let content: TodayWidgetContent?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, content: WidgetLibrary.shared.todayWidget(on: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        Task { completion(await entry(for: .now, picture: !context.isPreview)) }
    }

    /// Today now, and tomorrow from midnight; then a new timeline after midnight.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        Task {
            let now = Date.now
            let midnight = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now)
            let entries = [await entry(for: now, picture: true), await entry(for: midnight, picture: true)]
            completion(Timeline(entries: entries, policy: .after(midnight.addingTimeInterval(60))))
        }
    }

    private func entry(for date: Date, picture: Bool) async -> TodayEntry {
        var content = WidgetLibrary.shared.todayWidget(on: date, snapshot: AppGroup.read())
        if picture, let c = content { content?.image = await WidgetImages.picture(for: c, library: WidgetLibrary.shared) }
        return TodayEntry(date: date, content: content)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
            TodayWidgetView(content: entry.content)
                .widgetURL(entry.content?.link ?? URL(string: "\(DeepLink.scheme)://today"))
        }
        .configurationDisplayName("Today in Jazz")
        .description("Whose birthday it is and what was recorded on this date.")
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    #endif
}

// MARK: - Continue

struct ContinueEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// The app reloads this widget when the passport changes, so its timeline is one entry.
struct ContinueProvider: TimelineProvider {
    func placeholder(in context: Context) -> ContinueEntry { ContinueEntry(date: .now, snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (ContinueEntry) -> Void) {
        completion(ContinueEntry(date: .now, snapshot: AppGroup.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ContinueEntry>) -> Void) {
        completion(Timeline(entries: [ContinueEntry(date: .now, snapshot: AppGroup.read())], policy: .never))
    }
}

struct ContinueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "continue", provider: ContinueProvider()) { entry in
            ContinueWidgetView(snapshot: entry.snapshot)
                .widgetURL(entry.snapshot?.link ?? URL(string: "\(DeepLink.scheme)://paths"))
        }
        .configurationDisplayName("Continue")
        .description("Your next stop on a path, or the era stamp you're closest to.")
        .supportedFamilies(Self.families)
    }

    #if os(iOS)
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium]
    #endif
}
