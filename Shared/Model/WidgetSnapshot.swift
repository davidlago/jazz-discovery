import Foundation

/// What the app hands its widgets through the app group: where you are on a path, the next era stamp, and what you've
/// heard and saved (so Today in Jazz ranks the day's events the way the app does). Small, and rewritten whenever the
/// passport changes.
struct WidgetSnapshot: Codable, Equatable {
    struct PathState: Codable, Equatable {
        let id: String
        let title: String
        let tint: String
        let done: Int
        let total: Int
        let nextTitle: String
        let nextSubtitle: String
    }
    struct EraState: Codable, Equatable {
        let id: String
        let name: String
        let tint: String
        let heard: Int
        let total: Int
    }

    var path: PathState? = nil
    /// The unfinished era stamp with the most heard (the nearest to inking in).
    var era: EraState? = nil
    var heardCount = 0
    var albumCount = 0
    var heard: [String] = []
    var saved: [String] = []
    var savedArtists: [String] = []
}

/// The app group the app and its widgets share, when the build is signed with it.
///
/// Its name comes from Info.plist (`JazzDiscoveryAppGroup`), which a build fills in only when it signs with the group
/// (scripts/build-app.sh, scripts/testflight.sh): macOS asks the user before an app opens a group container it isn't
/// entitled to, so an unsigned or ad-hoc build never touches one, and the widgets then show what needs no passport.
enum AppGroup {
    static var identifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "JazzDiscoveryAppGroup") as? String,
              id.hasPrefix("group.") else { return nil }
        return id
    }

    static var snapshotURL: URL? {
        guard let id = identifier,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return nil }
        return dir.appendingPathComponent("widgets.json")
    }

    static func read() -> WidgetSnapshot? {
        guard let url = snapshotURL, let d = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: d)
    }

    /// Writes the snapshot; false when there's no group to write to, or it's unchanged.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL, read() != snapshot, let d = try? JSONEncoder().encode(snapshot) else { return false }
        return (try? d.write(to: url, options: .atomic)) != nil
    }
}
