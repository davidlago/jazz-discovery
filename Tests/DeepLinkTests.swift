import Foundation
import Testing

@Suite("jazzdiscovery:// links")
struct DeepLinkTests {
    let library = Fixtures.library

    func link(_ s: String) -> DeepLink? { DeepLink(URL(string: s)!, library: library) }

    @Test func pages() {
        #expect(link("jazzdiscovery://era/bebop") == .page(.era("bebop")))
        #expect(link("jazzdiscovery://artist/miles-davis") == .page(.artist("miles-davis")))
        #expect(link("jazzdiscovery://album/kind-of-blue") == .page(.album("kind-of-blue")))
        #expect(link("jazzdiscovery://decade/1950") == .page(.decade(1950)))
    }

    @Test func otherScreens() {
        #expect(link("jazzdiscovery://decades") == .decades)
        #expect(link("jazzdiscovery://connections") == .connections(focus: nil))
        #expect(link("jazzdiscovery://connections/john-coltrane") == .connections(focus: "john-coltrane"))
        #expect(link("jazzdiscovery://between/miles-davis/joao-gilberto") == .between("miles-davis", "joao-gilberto"))
        #expect(link("jazzdiscovery://between/miles-davis/nobody") == nil)
        #expect(link("jazzdiscovery://between/miles-davis/miles-davis") == nil)
        #expect(link("jazzdiscovery://between/miles-davis") == nil)
        #expect(link("jazzdiscovery://now-playing") == .nowPlaying)
        #expect(link("jazzdiscovery://settings") == .settings)
        #expect(link("jazzdiscovery://passport") == .passport)
    }

    @Test("A link written from a page reads back as the same page (Handoff hands pages over as links)")
    func roundTrip() {
        let links: [DeepLink] = [
            .page(.era("bebop")), .page(.artist("miles-davis")), .page(.album("kind-of-blue")), .page(.decade(1950)),
            .decades, .connections(focus: nil), .connections(focus: "john-coltrane"), .between("miles-davis", "joao-gilberto"),
            .tab(.discover, query: nil), .tab(.crate, query: nil), .tab(.search, query: "blue note"), .songbook, .map, .labels,
            .lineages, .glossary, .paths, .guides, .almanac(month: nil, day: nil), .almanac(month: 5, day: 26), .passport,
            .radio, .blindfold,
        ]
        for l in links {
            let url = try! #require(l.url)
            #expect(DeepLink(url, library: library) == l, "\(url)")
        }
        // Music, Settings and Now Playing aren't handed off.
        #expect(DeepLink.playAlbum("kind-of-blue").url == nil)
        #expect(DeepLink.settings.url == nil)
        #expect(Handoff.title(of: .page(.album("kind-of-blue")), library: library).hasPrefix("Kind of Blue"))
        #expect(Handoff.title(of: .page(.decade(1950)), library: library) == "The 1950s")
    }

    @Test func tabs() {
        for tab in DeepLink.Tab.allCases {
            #expect(link("jazzdiscovery://tab/\(tab.rawValue)") == .tab(tab, query: nil))
        }
        #expect(link("jazzdiscovery://tab/search?q=Coltrane") == .tab(.search, query: "Coltrane"))
        #expect(link("jazzdiscovery://tab/library") == nil)
        #expect(link("jazzdiscovery://tab") == nil)
    }

    @Test("Pages that don't exist don't parse")
    func unknownPages() {
        #expect(link("jazzdiscovery://era/polka") == nil)
        #expect(link("jazzdiscovery://artist/nobody") == nil)
        #expect(link("jazzdiscovery://album/nothing") == nil)
        #expect(link("jazzdiscovery://era") == nil)
        #expect(link("jazzdiscovery://artist/") == nil)
    }

    @Test("A made-up decade doesn't parse (it used to crash the iPhone app)")
    func unknownDecades() {
        #expect(link("jazzdiscovery://decade/1955") == nil)
        #expect(link("jazzdiscovery://decade/2100") == nil)
        #expect(link("jazzdiscovery://decade/1880") == nil)
        #expect(link("jazzdiscovery://decade/fifties") == nil)
    }

    @Test("An unknown artist still opens Connections, with nobody selected")
    func connectionsUnknownArtist() {
        #expect(link("jazzdiscovery://connections/nobody") == .connections(focus: nil))
    }

    @Test("Only play/album/<a real album> parses as music; the apps decide whether to honour it")
    func play() {
        #expect(link("jazzdiscovery://play/album/kind-of-blue") == .playAlbum("kind-of-blue"))
        #expect(link("jazzdiscovery://play/album/nothing") == nil)
        #expect(link("jazzdiscovery://play/album") == nil)
        #expect(link("jazzdiscovery://play/track/so-what") == nil)
        #expect(link("jazzdiscovery://play/album/kind-of-blue/extra") == nil)
    }

    @Test func otherSchemesAndHosts() {
        #expect(link("https://era/bebop") == nil)
        #expect(link("music://era/bebop") == nil)
        #expect(link("jazzdiscovery://lastfm-auth?token=abc") == nil)
        #expect(link("jazzdiscovery://unknown/thing") == nil)
        #expect(link("JazzDiscovery://ERA/bebop") == .page(.era("bebop")))
    }
}
