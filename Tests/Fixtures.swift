import Foundation

/// A small, hand-made library for tests, so they don't change when jazz.json does.
enum Fixtures {
    static func era(_ id: String, _ start: Int, _ end: Int, artists: [String] = []) -> Era {
        Era(id: id, name: id.capitalized, start: start, end: end, color: "#888888", tagline: "", summary: "",
            characteristics: [], places: [], wikipedia: id, keyArtists: artists, keyAlbums: [], essentialTracks: [],
            documentaryQuery: id)
    }

    static func artist(_ id: String, _ name: String, born: Int?, era: String, connections: [String] = [],
                       albums: [String] = [], instrument: String = "Piano") -> Artist {
        Artist(id: id, name: name, born: born, died: nil, instrument: instrument, eras: [era], primaryEra: era,
               wikipedia: name, blurb: "", connections: connections, albums: albums, signatureTracks: [],
               videoQuery: name)
    }

    static func album(_ id: String, _ title: String, by artist: Artist, year: Int, label: String = "Blue Note") -> Album {
        Album(id: id, title: title, artist: artist.id, artistName: artist.name, year: year, label: label,
              era: artist.primaryEra, why: "", highlights: [], starter: false)
    }

    static let library: JazzLibrary = {
        let miles = artist("miles-davis", "Miles Davis", born: 1926, era: "modal",
                           connections: ["john-coltrane", "charlie-parker", "nobody"], albums: ["kind-of-blue"],
                           instrument: "Trumpet")
        let trane = artist("john-coltrane", "John Coltrane", born: 1926, era: "modal", instrument: "Saxophone")
        let bird = artist("charlie-parker", "Charlie Parker", born: 1920, era: "bebop",
                          connections: ["miles-davis"], instrument: "Saxophone")
        let joao = artist("joao-gilberto", "João Gilberto", born: 1931, era: "latin", instrument: "Guitar")
        return JazzLibrary(data: JazzData(
            eras: [era("modal", 1958, 1968), era("bebop", 1942, 1956), era("latin", 1947, 1970)],
            artists: [miles, trane, bird, joao],
            albums: [
                album("kind-of-blue", "Kind of Blue", by: miles, year: 1959, label: "Columbia"),
                album("bitches-brew", "Bitches Brew", by: miles, year: 1970, label: "Columbia"),
                album("giant-steps", "Giant Steps", by: trane, year: 1960, label: "Atlantic"),
            ],
            milestones: []))
    }()
}

/// Finds this test bundle, whose resources include Shared/Resources (jazz.json, catalog.json).
final class TestBundle {
    static var bundle: Bundle { Bundle(for: TestBundle.self) }
}
