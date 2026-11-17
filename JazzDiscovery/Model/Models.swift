import SwiftUI

struct Era: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let start: Int
    let end: Int
    let color: String
    let tagline: String
    let summary: String
    let characteristics: [String]
    let places: [String]
    let wikipedia: String
    let keyArtists: [String]
    let keyAlbums: [String]
    let essentialTracks: [TrackRef]
    let documentaryQuery: String

    var tint: Color { Color(hex: color) }
    var years: String { end >= 2025 ? "\(start)–now" : "\(start)–\(end)" }
    func overlaps(decade: Int) -> Bool { start < decade + 10 && end >= decade }
}

struct TrackRef: Codable, Hashable, Identifiable {
    let title: String
    let artist: String
    let year: Int?
    var id: String { "\(artist)|\(title)" }
}

struct Artist: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let born: Int?
    let died: Int?
    let instrument: String
    let eras: [String]
    let primaryEra: String
    let wikipedia: String
    let blurb: String
    let connections: [String]
    let albums: [String]
    let signatureTracks: [String]
    let videoQuery: String

    var lifespan: String {
        switch (born, died) {
        case let (b?, d?): return "\(b)–\(d)"
        case let (b?, nil): return "b. \(b)"
        default: return ""
        }
    }
    func active(in decade: Int) -> Bool {
        guard let born else { return false }
        let startActive = born + 18
        let endActive = died ?? 2100
        return startActive < decade + 10 && endActive >= decade
    }
    var initials: String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}

struct Album: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let artistName: String
    let year: Int
    let label: String
    let era: String
    let why: String
    let highlights: [String]
    let starter: Bool

    var decade: Int { year / 10 * 10 }
    var searchTerm: String { "\(artistName) \(title)" }
}

struct Milestone: Codable, Identifiable, Hashable {
    let year: Int
    let title: String
    let detail: String
    var id: String { "\(year)-\(title)" }
}

struct JazzData: Codable {
    let eras: [Era]
    let artists: [Artist]
    let albums: [Album]
    let milestones: [Milestone]
}
