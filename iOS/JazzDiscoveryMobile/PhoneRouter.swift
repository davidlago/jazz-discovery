import SwiftUI
import Observation

enum PhoneTab: String, Hashable, CaseIterable {
    case timeline, eras, artists, crate, search
}

/// Pages pushed onto a tab's navigation stack.
enum PhoneRoute: Hashable {
    case era(String)
    case artist(String)
    case album(String)
    case decade(Int)
    case decades
    case connections(focus: String?)
}

/// Tabs, each with its own navigation stack, and the sheets shown over them.
@MainActor
@Observable
final class PhoneRouter {
    enum ErasMode: String, CaseIterable { case styles = "Styles", decades = "Decades" }

    var tab: PhoneTab = .timeline
    private var paths: [PhoneTab: [PhoneRoute]] = [:]
    var showNowPlaying = false
    var showSettings = false
    var erasMode: ErasMode = .styles
    var query = ""

    func path(_ tab: PhoneTab) -> Binding<[PhoneRoute]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    /// Selecting the tab that's already showing goes back to its first page, as in Apple's apps.
    var tabSelection: Binding<PhoneTab> {
        Binding(get: { self.tab }, set: { new in
            if new == self.tab { self.paths[new] = [] }
            self.tab = new
        })
    }

    /// Pushes a page on the current tab (closing the player first, when it's open).
    func go(_ route: PhoneRoute) {
        showNowPlaying = false
        showSettings = false
        paths[tab, default: []].append(route)
    }

    func show(_ tab: PhoneTab, _ routes: [PhoneRoute] = []) {
        showNowPlaying = false
        showSettings = false
        self.tab = tab
        paths[tab] = routes
    }

    /// `jazzdiscovery://era/bebop`, `artist/<id>`, `album/<id>`, `decade/1950`, `decades`, `connections[/<id>]`,
    /// `tab/<timeline|eras|artists|crate|search>`, `now-playing`, `settings`.
    ///
    /// Links come from anywhere (a web page, another app), so they only show pages that exist. `play/album/<id>`,
    /// which starts music, is for the app's own `--open` launch argument (`fromLaunchArguments`) alone.
    func handle(_ url: URL, library: JazzLibrary, player: PlayerController, fromLaunchArguments: Bool = false) {
        guard url.scheme == "jazzdiscovery", let host = url.host() else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        let arg = parts.first
        switch host {
        case "era": if let id = arg, library.era(id) != nil { erasMode = .styles; show(.eras, [.era(id)]) }
        case "artist": if let id = arg, library.artist(id) != nil { show(.artists, [.artist(id)]) }
        case "album": if let id = arg, library.album(id) != nil { show(.crate, [.album(id)]) }
        case "decade": if let d = arg.flatMap(Int.init), library.decades.contains(d) { erasMode = .decades; show(.eras, [.decade(d)]) }
        case "decades": erasMode = .decades; show(.eras)
        case "connections": show(.artists, [.connections(focus: arg.flatMap { library.artist($0)?.id })])
        case "tab":
            if let t = arg.flatMap(PhoneTab.init(rawValue:)) {
                if let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value {
                    query = q
                }
                show(t)
            }
        case "now-playing": showSettings = false; showNowPlaying = player.current != nil
        case "settings": showNowPlaying = false; showSettings = true
        case "play":
            if fromLaunchArguments, parts.first == "album", parts.count > 1, let album = library.album(parts[1]) {
                Task {
                    guard let c = await ITunes.shared.album(for: album) else { return }
                    player.playAlbum(c, tracks: [])
                }
            }
        default: break  // lastfm-auth is answered by the sign-in sheet itself
        }
    }
}
