import SwiftUI
import Observation

enum PhoneTab: String, Hashable, CaseIterable {
    case timeline, eras, artists, crate, search

    init(_ tab: DeepLink.Tab) {
        switch tab {
        case .timeline: self = .timeline
        case .eras: self = .eras
        case .artists: self = .artists
        case .crate: self = .crate
        case .search: self = .search
        }
    }
}

/// Pages pushed onto a tab's navigation stack: the app's pages (`Route`, shared with the Mac app) and two that only the
/// iPhone shows as pages of their own.
enum PhoneRoute: Hashable {
    case page(Route)
    case decades
    case connections(focus: String?)
    case passport

    static func era(_ id: String) -> PhoneRoute { .page(.era(id)) }
    static func artist(_ id: String) -> PhoneRoute { .page(.artist(id)) }
    static func album(_ id: String) -> PhoneRoute { .page(.album(id)) }
    static func decade(_ decade: Int) -> PhoneRoute { .page(.decade(decade)) }
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
    /// A chain for the Connections map to draw when it next shows (from a `between/<a>/<b>` link).
    var pathRequest: PathRequest?

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

    /// Shows what a `jazzdiscovery://` link names (see `DeepLink`, which only accepts pages that exist).
    ///
    /// `play/album/<id>`, which starts music, is for the app's own `--open` launch argument (`fromLaunchArguments`) alone.
    func handle(_ url: URL, library: JazzLibrary, player: PlayerController, fromLaunchArguments: Bool = false) {
        guard let link = DeepLink(url, library: library) else { return }
        switch link {
        case .page(let route):
            switch route {
            case .era: erasMode = .styles; show(.eras, [.page(route)])
            case .artist: show(.artists, [.page(route)])
            case .album: show(.crate, [.page(route)])
            case .decade: erasMode = .decades; show(.eras, [.page(route)])
            }
        case .decades: erasMode = .decades; show(.eras)
        case .connections(let focus): show(.artists, [.connections(focus: focus)])
        case .between(let a, let b):
            pathRequest = PathRequest(from: a, to: b)
            show(.artists, [.connections(focus: nil)])
        case .tab(let tab, let q):
            if let q { query = q }
            show(PhoneTab(tab))
        case .nowPlaying: showSettings = false; showNowPlaying = player.current != nil
        case .settings: showNowPlaying = false; showSettings = true
        case .passport: show(.crate, [.passport])
        case .playAlbum(let id):
            guard fromLaunchArguments, let album = library.album(id) else { return }
            Task {
                guard let c = await ITunes.shared.album(for: album) else { return }
                player.playAlbum(c, tracks: [])
            }
        }
    }
}
