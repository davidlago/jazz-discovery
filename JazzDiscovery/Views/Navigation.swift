import SwiftUI
import Observation

/// The Mac app's sidebar sections.
enum AppSection: String, CaseIterable, Identifiable {
    case timeline = "Discover"
    case eras = "Eras & Styles"
    case decades = "Decades"
    case artists = "Artists"
    case albums = "The Crate"
    case connections = "Connections"
    case songbook = "Songbook"
    case places = "Places"
    case labels = "Labels"
    case lineages = "Lineages"
    case glossary = "Glossary"
    case radio = "Radio"
    case blindfold = "Blindfold Test"
    case passport = "Passport"
    var id: String { rawValue }
    /// The sections under Explore in the sidebar (Listen and You have their own).
    static var explore: [AppSection] { allCases.filter { ![.passport, .radio, .blindfold].contains($0) } }
    static var listen: [AppSection] { [.radio, .blindfold] }
    var symbol: String {
        switch self {
        case .timeline: return "timeline.selection"
        case .eras: return "square.stack.3d.up.fill"
        case .decades: return "calendar"
        case .artists: return "person.2.fill"
        case .albums: return "square.grid.3x3.fill"
        case .connections: return "point.3.connected.trianglepath.dotted"
        case .songbook: return "music.quarternote.3"
        case .places: return "map.fill"
        case .labels: return "opticaldisc.fill"
        case .lineages: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .glossary: return "character.book.closed.fill"
        case .passport: return "checkmark.seal.fill"
        case .radio: return "dot.radiowaves.left.and.right"
        case .blindfold: return "eyes"
        }
    }

    /// The section a page belongs to, so a link opens it with the right sidebar item selected.
    init(for route: Route) {
        switch route {
        case .era: self = .eras
        case .artist: self = .artists
        case .album: self = .albums
        case .decade: self = .decades
        case .tune: self = .songbook
        case .place: self = .places
        case .label: self = .labels
        case .lineage: self = .lineages
        case .term: self = .glossary
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
        case .songbook:
            query = ""
            show(.songbook)
        case .map:
            query = ""
            show(.places)
        case .labels:
            query = ""
            show(.labels)
        case .lineages:
            query = ""
            show(.lineages)
        case .glossary:
            query = ""
            show(.glossary)
        case .radio:
            query = ""
            show(.radio)
        case .blindfold:
            query = ""
            show(.blindfold)
        case .tab(let tab, let q):
            switch tab {
            case .timeline, .discover: query = ""; show(.timeline)
            case .eras, .explore: query = ""; show(.eras)
            case .artists: query = ""; show(.artists)
            case .crate: query = ""; show(.albums)
            case .search: path = []; query = q ?? query
            }
        case .nowPlaying, .settings, .playAlbum:
            break
        }
    }
}
