import Foundation
import Testing

@Suite("Session text")
struct SessionTextTests {
    func session(dates: [(String?, String?)] = [], kind: String? = nil, between: [Int]? = nil, crew: [(String, String)] = [],
                 personnel: [Credit] = []) -> Session {
        Session(reviewed: true, kind: kind, recorded: dates.map { RecordingDate(date: $0.0, place: $0.1) },
                recordedBetween: between, personnel: personnel,
                crew: crew.map { CrewCredit(artist: nil, name: $0.0, role: $0.1) })
    }

    @Test func dates() {
        #expect(Session.datesText(["1959-03-02", "1959-04-22"]) == "March 2 and April 22, 1959")
        #expect(Session.datesText(["1964-12-09"]) == "December 9, 1964")
        #expect(Session.datesText(["1957-05-06", "1957-05-10", "1957-05-23", "1957-05-27"]) == "May 6–27, 1957")
        #expect(Session.datesText(["1960-11-18", "1960-11-30", "1960-12-10", "1960-12-15"]) == "November–December 1960")
        #expect(Session.datesText(["1976-12", "1977-01"]) == "December 1976; January 1977")
        #expect(Session.datesText(["1976-07-08", "1976-12"]) == "July 8 and December, 1976")
        #expect(Session.datesText(["1949"]) == "1949")
        #expect(Session.datesText(["1939-04-20", "1944-03-25", "1944-04-01", "1944-04-08"])
                == "April 20, 1939; March 25, April 1 and April 8, 1944")
        #expect(Session.datesText([]) == nil)
        #expect(Session.datesText(["1959-03-02", "1959-03-02"]) == "March 2, 1959")
    }

    @Test func recordedLine() {
        #expect(session(dates: [("1959-03-02", "CBS 30th Street Studio, New York"), ("1959-04-22", "CBS 30th Street Studio, New York")]).recordedText
                == "March 2 and April 22, 1959 · CBS 30th Street Studio, New York")
        #expect(session(dates: [(nil, "Avatar Studios, New York")]).recordedText == "Avatar Studios, New York")
        #expect(session(kind: "compilation", between: [1925, 1929]).recordedText == "1925–1929, across many sessions")
        #expect(session().recordedText == nil)
    }

    @Test func crewLine() {
        let s = session(crew: [("Fred Plaut", "engineer"), ("Irving Townsend", "producer"), ("Gil Evans", "arranger"),
                               ("Gil Evans", "conductor"), ("Pat Maher", "engineer")])
        #expect(s.crewText == "Produced by Irving Townsend · Arranged by Gil Evans · Conducted by Gil Evans · Engineered by Fred Plaut and Pat Maher")
        #expect(session().crewText == nil)
    }

    @Test func trackNotes() {
        func c(only: [String]? = nil, except: [String]? = nil, tracks: Int? = nil) -> Credit {
            Credit(artist: nil, name: "X", instruments: ["piano"], only: only, except: except, tracks: tracks)
        }
        #expect(c().tracksText(of: 5) == nil)
        #expect(c(only: ["Freddie Freeloader"]).tracksText(of: 5) == "only on “Freddie Freeloader”")
        #expect(c(only: ["A", "B", "C", "D"]).tracksText(of: 12) == "on 4 of 12 tracks")
        #expect(c(except: ["Blue in Green"]).tracksText(of: 5) == "not on “Blue in Green”")
        #expect(c(except: ["A", "B", "C"]).tracksText(of: 12) == "not on 3 tracks")
        #expect(c(tracks: 30).tracksText(of: 93) == "30 of 93 tracks")
        #expect(c(tracks: 13).tracksText(of: 13) == nil)
        #expect(Credit(artist: nil, name: "X", instruments: ["tenor saxophone", "soprano saxophone"], only: nil, except: nil, tracks: nil)
                .instrumentsText == "tenor saxophone, soprano saxophone")
    }

    @Test func perTrack() {
        let a = Credit(artist: nil, name: "A", instruments: ["piano"], only: ["x"], except: nil, tracks: nil)
        let b = Credit(artist: nil, name: "B", instruments: ["bass"], only: nil, except: nil, tracks: 3)
        #expect(session(personnel: [a]).hasPerTrackCredits)
        #expect(!session(personnel: [b]).hasPerTrackCredits)
        #expect(!session(kind: "compilation", personnel: [a]).hasPerTrackCredits)
    }

    @Test("Every reviewed album in the bundle has words to show")
    func bundled() {
        let library = JazzLibrary.load(from: TestBundle.bundle)
        for (id, s) in library.sessions {
            #expect(!s.personnel.isEmpty, "\(id)")
            if let r = s.recordedText { #expect(!r.contains("  ") && !r.hasPrefix(","), "\(id): \(r)") }
        }
    }
}
