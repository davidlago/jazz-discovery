import Foundation

/// Finds the Crate's records among the albums you've played most on Last.fm, so they can be marked as heard.
enum LastFMImport {
    struct TopAlbum: Equatable { let artist: String; let title: String; let plays: Int }

    /// Your most played albums on Last.fm, up to 500 (read-only; needs only your user name).
    @MainActor
    static func topAlbums(_ scrobbler: Scrobbler) async throws -> [TopAlbum] {
        guard let api = scrobbler.api, let user = scrobbler.userName else { return [] }
        var out: [TopAlbum] = []
        for page in 1...2 {
            let json = try await api.call("user.getTopAlbums", ["user": user, "period": "overall", "limit": "250", "page": "\(page)"])
            let albums = ((json["topalbums"] as? [String: Any])?["album"] as? [[String: Any]]) ?? []
            for a in albums {
                guard let title = a["name"] as? String, let artist = (a["artist"] as? [String: Any])?["name"] as? String else { continue }
                out.append(TopAlbum(artist: artist, title: title, plays: Int(a["playcount"] as? String ?? "") ?? 0))
            }
            if albums.count < 250 { break }
        }
        return out
    }

    /// The Crate records among them, matched by title and artist, most played first.
    static func matches(_ top: [TopAlbum], library: JazzLibrary) -> [(album: Album, plays: Int)] {
        var best: [String: Int] = [:]
        for t in top {
            let title = norm(t.title), artist = norm(t.artist)
            for album in library.albums where norm(album.title) == title {
                let names = [album.artistName] + [library.artist(album.artist)?.name].compactMap { $0 }
                if names.map(norm).contains(where: { $0 == artist || $0.contains(artist) || artist.contains($0) }) {
                    best[album.id] = max(best[album.id] ?? 0, t.plays)
                }
            }
        }
        return best.compactMap { id, plays in library.album(id).map { ($0, plays) } }.sorted { $0.plays > $1.plays }
    }

    /// Lowercased letters and digits, without accents, edition notes in brackets, or a leading "The".
    static func norm(_ s: String) -> String {
        var t = s
        if let i = t.firstIndex(where: { $0 == "(" || $0 == "[" }) { t = String(t[..<i]) }
        t = t.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).replacingOccurrences(of: "&", with: "and")
        if t.hasPrefix("the ") { t.removeFirst(4) }
        return t.filter { $0.isLetter || $0.isNumber }
    }
}

extension Passport {
    /// Marks records as heard from Last.fm (leaving ones already heard as they are). Returns how many were marked.
    @discardableResult
    func importHeard(_ albumIDs: [String]) -> Int {
        let new = albumIDs.filter { !isHeard($0) }
        for id in new { setHeard(id, true, how: .lastFM) }
        return new.count
    }
}
