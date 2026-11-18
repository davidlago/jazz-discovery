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
        #expect(link("jazzdiscovery://now-playing") == .nowPlaying)
        #expect(link("jazzdiscovery://settings") == .settings)
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
