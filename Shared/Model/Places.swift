import SwiftUI
import CoreLocation

/// A place in the story: a city or district, a club, a studio or a festival (places.json).
struct Place: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case city, district, venue, studio, festival }

    let id: String
    let name: String
    let kind: Kind
    /// The city it belongs to, for rooms and districts.
    var city: String? = nil
    var wikipedia: String? = nil
    let lat: Double
    let lon: Double
    /// The years it mattered to the music (not when it was built); `to` nil means it still does.
    let from: Int
    var to: Int? = nil
    let summary: String
    let eras: [String]
    var artists: [String] = []
    /// How sessions.json names it, for "Recorded here".
    var sessionNames: [String]? = nil

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    func active(in year: Int) -> Bool { from <= year && (to ?? 9999) >= year }
    /// "1935 – still open", "1921 – 1927".
    var years: String { to.map { $0 == from ? String(from) : "\(String(from)) – \(String($0))" } ?? "\(String(from)) – now" }
    var isCity: Bool { kind == .city }
    var kindLabel: String {
        switch kind {
        case .city: return "City"
        case .district: return "Neighbourhood"
        case .venue: return "Club & hall"
        case .studio: return "Studio"
        case .festival: return "Festival"
        }
    }
    var symbol: String {
        switch kind {
        case .city: return "building.2.fill"
        case .district: return "map.fill"
        case .venue: return "music.mic"
        case .studio: return "waveform"
        case .festival: return "sparkles"
        }
    }
}

/// A record label with a page (labels.json).
struct LabelInfo: Codable, Identifiable, Hashable {
    struct Person: Codable, Hashable { let name: String; let role: String; var place: String? = nil }

    let id: String
    let name: String
    /// The `album.label` strings that mean this label.
    let matches: [String]
    let founded: Int
    var city: String? = nil
    let color: String
    var wikipedia: String? = nil
    let summary: String
    let sound: String
    let look: String
    var people: [Person] = []
    let eras: [String]

    var tint: Color { Color(hex: color) }
}

struct PlacesData: Codable { let places: [Place] }
struct LabelsData: Codable { let labels: [LabelInfo] }

extension JazzLibrary {
    func place(_ id: String) -> Place? { places.first { $0.id == id } }

    /// The rooms and districts of a city.
    func places(in cityID: String) -> [Place] {
        places.filter { $0.city == cityID }.sorted { ($0.from, $0.name) < ($1.from, $1.name) }
    }

    /// Places that belong to an era.
    func places(inEra eraID: String) -> [Place] { places.filter { $0.eras.contains(eraID) } }

    /// Records made at a place (from sessions.json's recording places), or, for a city, anywhere in it.
    func albums(recordedAt placeID: String) -> [Album] {
        guard let place = place(placeID) else { return [] }
        let ids = [place] + (place.isCity ? places(in: place.id) : [])
        let names = Set(ids.flatMap { $0.sessionNames ?? [] }.map { $0.lowercased() })
        guard !names.isEmpty else { return [] }
        return albums.filter { a in
            session(for: a.id)?.recorded?.contains { $0.place.map { names.contains($0.lowercased()) } ?? false } ?? false
        }
    }

    /// Who was there: the place's own list, then leaders of records made there.
    func artists(at placeID: String) -> [Artist] {
        guard let place = place(placeID) else { return [] }
        var ids = place.artists
        if place.isCity { for p in places(in: place.id) { ids += p.artists } }
        ids += albums(recordedAt: placeID).map(\.artist)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.compactMap { artist($0) }
    }

    func label(_ id: String) -> LabelInfo? { labels.first { $0.id == id } }
    func label(for album: Album) -> LabelInfo? { labels.first { $0.matches.contains(album.label) } }
    func albums(onLabel id: String) -> [Album] {
        guard let l = label(id) else { return [] }
        return albums.filter { l.matches.contains($0.label) }.sorted { $0.year < $1.year }
    }

    /// Who appears on the most of a label's records, leading or playing.
    func regulars(onLabel id: String, limit: Int = 12) -> [(artist: Artist, records: Int)] {
        var counts: [String: Int] = [:]
        for a in albums(onLabel: id) {
            var people = Set([a.artist])
            for c in session(for: a.id)?.personnel ?? [] { if let p = c.artist { people.insert(p) } }
            for p in people { counts[p, default: 0] += 1 }
        }
        return counts.filter { $0.value > 1 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).compactMap { k, v in artist(k).map { ($0, v) } }
    }
}
