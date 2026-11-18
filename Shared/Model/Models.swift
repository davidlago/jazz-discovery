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

// MARK: - Sessions (sessions.json): who played on each album, when and where

/// One player's credit on an album: who, on what, and on which tracks if not all of them.
struct Credit: Codable, Hashable {
    /// The artist's ID when they have a page in the app; nil for someone shown by name only.
    let artist: String?
    let name: String
    let instruments: [String]
    /// The tracks they play on, when that's fewer than half; otherwise `except` lists the ones they sit out.
    let only: [String]?
    let except: [String]?
    /// On a compilation: how many of its tracks they're on.
    let tracks: Int?

    /// Whether they play on the track with this title (Apple Music's title is fine: suffixes such as
    /// "(Alternate Take 1) [1998 Remaster]" are ignored).
    func plays(on title: String) -> Bool {
        let t = Session.trackKey(title)
        if let only { return only.contains { Session.trackKey($0) == t } }
        if let except { return !except.contains { Session.trackKey($0) == t } }
        return true
    }
}

/// A recording session: a date (YYYY, YYYY-MM or YYYY-MM-DD) and the studio or venue.
struct RecordingDate: Codable, Hashable {
    let date: String?
    let place: String?
}

/// Someone behind the glass: producer, engineer, arranger, conductor, design or photography.
struct CrewCredit: Codable, Hashable {
    let artist: String?
    let name: String
    let role: String
}

struct Session: Codable, Hashable {
    /// Drafts (false) are in the file but never shown.
    let reviewed: Bool
    /// "compilation" for sets gathered from many sessions; nil for an album made in a few.
    let kind: String?
    let recorded: [RecordingDate]?
    /// For compilations: first and last year of recording.
    let recordedBetween: [Int]?
    let personnel: [Credit]
    let crew: [CrewCredit]?
    /// The tracks the credits refer to (titles as on the edition that was checked).
    var tracks: [String]? = nil

    var isCompilation: Bool { kind == "compilation" }

    /// The players on one track.
    func players(on title: String) -> [Credit] { personnel.filter { $0.plays(on: title) } }

    /// A track title reduced for matching: lowercased, accents and punctuation dropped, and everything from the first
    /// bracket on cut ("Bouncin' With Bud (Alternate Take 1) [1998 Remaster]" → "bouncinwithbud").
    static func trackKey(_ title: String) -> String {
        let cut = title.firstIndex(where: { $0 == "(" || $0 == "[" }).map { String(title[..<$0]) } ?? title
        return cut.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
