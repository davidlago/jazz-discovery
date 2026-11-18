import Foundation

/// The app's pages, shared by the Mac and iPhone apps: a new page is one case here. Each app pushes them on its own
/// navigation stacks (`Router` on the Mac, `PhoneRouter` on the iPhone) and decides how to show them.
enum Route: Hashable {
    case era(String)
    case artist(String)
    case album(String)
    case decade(Int)
}

/// A `jazzdiscovery://` link, parsed and checked against the library.
///
///     era/<id>  artist/<id>  album/<id>  decade/<1950>  decades  connections[/<artist id>]
///     tab/<timeline|eras|artists|crate|search>[?q=<search>]  now-playing  settings
///
/// Links come from anywhere (a web page, another app, a widget), so a link only parses when the page it names exists.
/// `play/album/<id>` parses as `.playAlbum`; it's the one link that starts music, and the apps honour it only from their
/// own `--open` launch argument (scripted screenshots), never from a link opened from outside.
enum DeepLink: Equatable {
    case page(Route)
    case decades
    case connections(focus: String?)
    case tab(Tab, query: String?)
    case nowPlaying
    case settings
    case playAlbum(String)

    enum Tab: String, CaseIterable { case timeline, eras, artists, crate, search }

    static let scheme = "jazzdiscovery"

    init?(_ url: URL, library: JazzLibrary) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        let arg = parts.first
        switch host {
        case "era":
            guard let id = arg, library.era(id) != nil else { return nil }
            self = .page(.era(id))
        case "artist":
            guard let id = arg, library.artist(id) != nil else { return nil }
            self = .page(.artist(id))
        case "album":
            guard let id = arg, library.album(id) != nil else { return nil }
            self = .page(.album(id))
        case "decade":
            guard let d = arg.flatMap(Int.init), library.decades.contains(d) else { return nil }
            self = .page(.decade(d))
        case "decades":
            self = .decades
        case "connections":
            // An unknown artist still opens the map, just without one selected.
            self = .connections(focus: arg.flatMap { library.artist($0)?.id })
        case "tab":
            guard let tab = arg.flatMap(Tab.init(rawValue:)) else { return nil }
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "q" }?.value
            self = .tab(tab, query: q)
        case "now-playing":
            self = .nowPlaying
        case "settings":
            self = .settings
        case "play":
            guard parts.count == 2, parts[0] == "album", library.album(parts[1]) != nil else { return nil }
            self = .playAlbum(parts[1])
        default:
            // Includes lastfm-auth, which the iPhone's Last.fm sign-in sheet answers itself.
            return nil
        }
    }
}
