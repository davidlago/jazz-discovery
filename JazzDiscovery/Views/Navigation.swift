import SwiftUI
import Observation

/// The Mac app's sidebar sections.
enum AppSection: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case eras = "Eras & Styles"
    case decades = "Decades"
    case artists = "Artists"
    case albums = "The Crate"
    case connections = "Connections"
    case passport = "Passport"
    var id: String { rawValue }
    /// The sections under Explore in the sidebar (Passport has its own, You).
    static var explore: [AppSection] { allCases.filter { $0 != .passport } }
    var symbol: String {
        switch self {
        case .timeline: return "timeline.selection"
        case .eras: return "square.stack.3d.up.fill"
        case .decades: return "calendar"
        case .artists: return "person.2.fill"
        case .albums: return "square.grid.3x3.fill"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .passport: return "checkmark.seal.fill"
        }
    }

    /// The section a page belongs to, so a link opens it with the right sidebar item selected.
    init(for route: Route) {
        switch route {
        case .era: self = .eras
        case .artist: self = .artists
        case .album: self = .albums
        case .decade: self = .decades
        }
    }
}

/// The Mac window's sidebar section, its navigation stack and its search.
@Observable
final class Router {
    var section: AppSection = .timeline
    var path: [Route] = []
    /// The sidebar's search field; while it has text, the window shows results instead of the section.
    var query = ""
    /// An artist for Connections to select when it next shows (from a `connections/<id>` link).
    var connectionsFocus: String?
    /// A chain for Connections to draw when it next shows (from a `between/<a>/<b>` link).
    var pathRequest: PathRequest?

    func go(_ route: Route) { path.append(route) }
    func back() { if !path.isEmpty { path.removeLast() } }
    func show(_ section: AppSection) { self.section = section; path = [] }

    /// Shows a page as the first one in its section. When that means changing section, the window resets the
    /// section's stack once it has switched (the split view does this for a new sidebar selection), which would drop
    /// a page pushed at the same time; so the page goes on the stack on the next turn of the run loop.
    func show(_ route: Route) {
        let section = AppSection(for: route)
        guard section != self.section else { path = [route]; return }
        show(section)
        DispatchQueue.main.async { [self] in
            if self.section == section { path = [route] }
        }
    }

    /// Shows what a `jazzdiscovery://` link names. Links only show pages: `play/…` doesn't start music on the Mac,
    /// there's no Now Playing window to open, and Settings is opened by the window (`RootView`), which can.
    func open(_ link: DeepLink) {
        switch link {
        case .page(let route):
            query = ""
            show(route)
        case .decades:
            query = ""
            show(.decades)
        case .connections(let focus):
            query = ""
            connectionsFocus = focus
            show(.connections)
        case .between(let a, let b):
            query = ""
            pathRequest = PathRequest(from: a, to: b)
            show(.connections)
        case .passport:
            query = ""
            show(.passport)
        case .tab(let tab, let q):
            switch tab {
            case .timeline: query = ""; show(.timeline)
            case .eras: query = ""; show(.eras)
            case .artists: query = ""; show(.artists)
            case .crate: query = ""; show(.albums)
            case .search: path = []; query = q ?? query
            }
        case .nowPlaying, .settings, .playAlbum:
            break
        }
    }
}
