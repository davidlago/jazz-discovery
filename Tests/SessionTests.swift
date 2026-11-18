import Foundation
import Testing

@Suite("Sessions")
struct SessionTests {
    static func credit(_ artist: String?, _ name: String, _ instruments: [String],
                       only: [String]? = nil, except: [String]? = nil) -> Credit {
        Credit(artist: artist, name: name, instruments: instruments, only: only, except: except, tracks: nil)
    }

    static func session(_ personnel: [Credit], reviewed: Bool = true) -> Session {
        Session(reviewed: reviewed, kind: nil, recorded: [RecordingDate(date: "1959-03-02", place: "CBS 30th Street Studio")],
                recordedBetween: nil, personnel: personnel, crew: nil)
    }

    /// Kind of Blue and Giant Steps reviewed; Bitches Brew still a draft.
    static let library = JazzLibrary(data: JazzData(
        eras: Fixtures.library.eras, artists: Fixtures.library.artists, albums: Fixtures.library.albums, milestones: []),
        sessions: [
            "kind-of-blue": session([
                credit("miles-davis", "Miles Davis", ["trumpet"]),
                credit(nil, "Cannonball Adderley", ["alto saxophone"], except: ["Blue in Green"]),
                credit("john-coltrane", "John Coltrane", ["tenor saxophone"]),
                credit(nil, "Paul Chambers", ["bass"]),
            ]),
            "giant-steps": session([
                credit("john-coltrane", "John Coltrane", ["tenor saxophone"]),
                credit(nil, "Paul Chambers", ["bass"]),
            ]),
            "bitches-brew": session([
                credit("miles-davis", "Miles Davis", ["trumpet"]),
                credit("john-coltrane", "John Coltrane", ["soprano saxophone"]),  // not true; it's a draft
            ], reviewed: false),
            "no-such-album": session([credit("miles-davis", "Miles Davis", ["trumpet"])]),
        ])

    @Test("Track titles match Apple Music's, whatever the suffixes")
    func trackKeys() {
        #expect(Session.trackKey("Bouncin' With Bud (Alternate Take 1) [1998 Remaster] [The Rudy Van Gelder Edition]")
                == Session.trackKey("Bouncin’ With Bud"))
        #expect(Session.trackKey("Parisian Thoroughfare (1998 Remaster) [The Rudy Van Gelder Edition]tion)")
                == Session.trackKey("Parisian Thoroughfare"))
        #expect(Session.trackKey("Wee (A.K.A. Allen's Alley) [Live]") == Session.trackKey("Wee (Allen's Alley)"))
        #expect(Session.trackKey("'Round Midnight") == "roundmidnight")
        #expect(Session.trackKey("Garota de Ipanema") == Session.trackKey("GAROTA DE IPANEMA"))
        #expect(Session.trackKey("Blue in Green") != Session.trackKey("Blue Train"))
    }

    @Test func whoPlaysOnATrack() {
        let s = Self.library.session(for: "kind-of-blue")!
        #expect(s.players(on: "So What").count == 4)
        #expect(s.players(on: "Blue in Green (Take 3)").map(\.name) == ["Miles Davis", "John Coltrane", "Paul Chambers"])
        let only = Self.credit(nil, "Somebody", ["vibraphone"], only: ["Epistrophy", "Misterioso"])
        #expect(only.plays(on: "Epistrophy [Remastered]"))
        #expect(!only.plays(on: "Off Minor"))
    }

    @Test("Only reviewed sessions of albums in the library are used")
    func draftsAreHidden() {
        #expect(Self.library.session(for: "kind-of-blue") != nil)
        #expect(Self.library.session(for: "bitches-brew") == nil)
        #expect(Self.library.session(for: "no-such-album") == nil)
        #expect(Self.library.sessions.count == 2)
    }

    @Test func appearances() {
        // Coltrane is on Kind of Blue (not his) and leads Giant Steps: only the first is an appearance.
        #expect(Self.library.appearances(of: "john-coltrane").map(\.id) == ["kind-of-blue"])
        #expect(Self.library.appearances(of: "miles-davis").isEmpty)
        #expect(Self.library.appearances(of: "charlie-parker").isEmpty)
    }

    @Test func sharedAlbums() {
        #expect(Self.library.sharedAlbums("miles-davis", "john-coltrane").map(\.id) == ["kind-of-blue"])
        #expect(Self.library.sharedAlbums("john-coltrane", "miles-davis").map(\.id) == ["kind-of-blue"])
        #expect(Self.library.sharedAlbums("miles-davis", "charlie-parker").isEmpty)
    }

    @Test func instruments() {
        #expect(Self.library.instruments(of: "john-coltrane") == ["tenor saxophone"])
        #expect(Self.library.instruments(of: "joao-gilberto").isEmpty)
    }
}

@Suite("Bundled sessions.json")
struct BundledSessionsTests {
    @Test("Every entry, drafts included, decodes")
    func decodes() throws {
        let url = try #require(TestBundle.bundle.url(forResource: "sessions", withExtension: "json"))
        let all = try JSONDecoder().decode([String: Session].self, from: Data(contentsOf: url))
        #expect(all.count >= 85)
        #expect(all.values.allSatisfy { !$0.personnel.isEmpty || !$0.reviewed })
    }

    @Test("The app loads only the reviewed ones")
    func loadsReviewedOnly() {
        let library = JazzLibrary.load(from: TestBundle.bundle)
        let allReviewed = library.sessions.values.allSatisfy { $0.reviewed }
        #expect(allReviewed)
    }
}
