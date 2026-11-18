import Foundation

struct CatalogAlbum: Codable, Hashable {
    let collectionId: Int
    let name: String
    let artistName: String
    let artwork: URL?
    let url: URL?
    let releaseYear: Int?
    let trackCount: Int?

    func artwork(_ size: Int) -> URL? { artwork.flatMap { ITunes.art($0, size: size) } }
}

struct CatalogTrack: Codable, Hashable, Identifiable {
    let trackId: Int
    let name: String
    let artistName: String
    let albumName: String?
    let collectionId: Int?
    let artwork: URL?
    let preview: URL?
    let url: URL?
    let durationMillis: Int?
    let trackNumber: Int?
    let discNumber: Int?
    var id: Int { trackId }

    var duration: String {
        guard let ms = durationMillis else { return "" }
        let s = ms / 1000
        return String(format: "%d:%02d", s / 60, s % 60)
    }
    func artwork(_ size: Int) -> URL? { artwork.flatMap { ITunes.art($0, size: size) } }
}

/// The public iTunes Search API: Apple Music catalog IDs (shared with MusicKit),
/// artwork and 30-second previews. No key required, but rate-limited (~20/min),
/// so results are cached on disk and requests are spaced out.
actor ITunes {
    static let shared = ITunes()

    private var bundled: [String: CatalogAlbum] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: CatalogAlbum].self, from: data) else { return [:] }
        return map
    }()
    /// Named tracks resolved ahead of time (tracks.json), by "artist|title".
    private lazy var bundledTracks: [String: CatalogTrack] = {
        guard let url = Bundle.main.url(forResource: "tracks", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: CatalogTrack].self, from: data) else { return [:] }
        return map
    }()
    /// Crate albums' tracklists (tracklists.json), by Apple Music album ID.
    private lazy var bundledLists: [Int: [CatalogTrack]] = {
        guard let url = Bundle.main.url(forResource: "tracklists", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let map = try? JSONDecoder().decode([String: [CatalogTrack]].self, from: data) else { return [:] }
        var out: [Int: [CatalogTrack]] = [:]
        for (albumID, list) in map { if let c = bundled[albumID]?.collectionId { out[c] = list } }
        return out
    }()
    private var lastRequest = Date.distantPast
    private var inflight: [String: Task<Data?, Never>] = [:]

    nonisolated static func art(_ url: URL, size: Int) -> URL {
        let s = url.absoluteString
        guard let r = s.range(of: #"\d+x\d+bb"#, options: .regularExpression) else { return url }
        return URL(string: s.replacingCharacters(in: r, with: "\(size)x\(size)bb")) ?? url
    }

    private func fetch(_ urlString: String) async -> Data? {
        if let t = inflight[urlString] { return await t.value }
        let task = Task<Data?, Never> { [weak self] in
            guard let self, let url = URL(string: urlString) else { return nil }
            for attempt in 0..<3 {
                await self.throttle()
                do { return try await HTTP.data(url) }
                catch {
                    if (error as? URLError)?.code == .badServerResponse {
                        try? await Task.sleep(for: .seconds(3 * (attempt + 1)))
                        continue
                    }
                    return nil
                }
            }
            return nil
        }
        inflight[urlString] = task
        let d = await task.value
        inflight[urlString] = nil
        return d
    }

    private func throttle() async {
        let gap = Date().timeIntervalSince(lastRequest)
        let minGap = 0.35
        lastRequest = Date().addingTimeInterval(max(0, minGap - gap))
        if gap < minGap { try? await Task.sleep(for: .seconds(minGap - gap)) }
    }

    private struct Response: Decodable { let results: [Item] }
    private struct Item: Decodable {
        let wrapperType: String?
        let kind: String?
        let collectionId: Int?
        let trackId: Int?
        let artistId: Int?
        let artistName: String?
        let collectionName: String?
        let trackName: String?
        let artworkUrl100: URL?
        let collectionViewUrl: URL?
        let trackViewUrl: URL?
        let previewUrl: URL?
        let releaseDate: String?
        let trackCount: Int?
        let trackTimeMillis: Int?
        let trackNumber: Int?
        let discNumber: Int?
        let isStreamable: Bool?

        var album: CatalogAlbum? {
            guard let collectionId, let collectionName else { return nil }
            return CatalogAlbum(collectionId: collectionId, name: collectionName, artistName: artistName ?? "",
                                artwork: artworkUrl100, url: collectionViewUrl,
                                releaseYear: releaseDate.flatMap { Int($0.prefix(4)) }, trackCount: trackCount)
        }
        var track: CatalogTrack? {
            guard kind == "song", let trackId, let trackName else { return nil }
            return CatalogTrack(trackId: trackId, name: trackName, artistName: artistName ?? "",
                                albumName: collectionName, collectionId: collectionId, artwork: artworkUrl100,
                                preview: previewUrl, url: trackViewUrl, durationMillis: trackTimeMillis,
                                trackNumber: trackNumber, discNumber: discNumber)
        }
    }

    private func q(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? s
    }

    private static func norm(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: "and")
            .filter { $0.isLetter || $0.isNumber }
    }

    /// Finds the Apple Music album for a curated album.
    func album(for album: Album) async -> CatalogAlbum? {
        if let b = bundled[album.id] { return b }
        let key = "itunes-album-v1-\(album.id)"
        if let c = await DiskCache.shared.get(key, as: CatalogAlbum.self) { return c }
        let url = "https://itunes.apple.com/search?term=\(q(album.searchTerm))&entity=album&media=music&limit=15"
        guard let d = await fetch(url), let r = try? JSONDecoder().decode(Response.self, from: d) else { return nil }
        let candidates = r.results.compactMap(\.album)
        let title = Self.norm(album.title)
        let artist = Self.norm(album.artistName.components(separatedBy: " & ").first ?? album.artistName)
        func score(_ c: CatalogAlbum) -> Int {
            var s = 0
            let n = Self.norm(c.name)
            if n == title { s += 10 } else if n.hasPrefix(title) { s += 6 } else if n.contains(title) { s += 4 }
            if Self.norm(c.artistName).contains(artist) { s += 5 }
            let lower = c.name.lowercased()
            for bad in ["karaoke", "tribute", "made famous", "in the style of"] where lower.contains(bad) { s -= 20 }
            return s
        }
        guard let best = candidates.max(by: { score($0) < score($1) }), score(best) > 4 else { return nil }
        await DiskCache.shared.set(key, best)
        return best
    }

    func tracks(collectionId: Int) async -> [CatalogTrack] {
        if let list = bundledLists[collectionId], !list.isEmpty { return list }
        let key = "itunes-tracks-v1-\(collectionId)"
        if let c = await DiskCache.shared.get(key, as: [CatalogTrack].self) { return c }
        guard let d = await fetch("https://itunes.apple.com/lookup?id=\(collectionId)&entity=song&limit=200"),
              let r = try? JSONDecoder().decode(Response.self, from: d) else { return [] }
        let tracks = r.results.compactMap(\.track)
            .sorted { ($0.discNumber ?? 1, $0.trackNumber ?? 0) < ($1.discNumber ?? 1, $1.trackNumber ?? 0) }
        if !tracks.isEmpty { await DiskCache.shared.set(key, tracks) }
        return tracks
    }

    /// Best catalog match for a named track by an artist.
    func track(_ title: String, artist: String) async -> CatalogTrack? {
        if let t = bundledTracks["\(artist)|\(title)"] { return refreshed[t.trackId] ?? t }
        let key = "itunes-track-v1-\(artist)-\(title)"
        if let c = await DiskCache.shared.get(key, as: CatalogTrack.self) { return c }
        guard let d = await fetch("https://itunes.apple.com/search?term=\(q(artist + " " + title))&entity=song&media=music&limit=15"),
              let r = try? JSONDecoder().decode(Response.self, from: d) else { return nil }
        let tracks = r.results.compactMap(\.track)
        let t = Self.norm(title), a = Self.norm(artist)
        func score(_ c: CatalogTrack) -> Int {
            var s = 0
            let n = Self.norm(c.name)
            if n == t { s += 10 } else if n.hasPrefix(t) { s += 6 } else if n.contains(t) { s += 3 }
            if Self.norm(c.artistName).contains(a) || a.contains(Self.norm(c.artistName)) { s += 6 }
            if c.preview != nil { s += 1 }
            let lower = c.name.lowercased() + (c.albumName ?? "").lowercased()
            for bad in ["karaoke", "tribute", "made famous", "in the style of", "lullaby"] where lower.contains(bad) { s -= 20 }
            return s
        }
        guard let best = tracks.max(by: { score($0) < score($1) }), score(best) >= 8 else { return nil }
        await DiskCache.shared.set(key, best)
        return best
    }

    /// Tracks looked up again because their stored preview link stopped working.
    private var refreshed: [Int: CatalogTrack] = [:]

    /// Looks a song up again by its ID, for a fresh preview link (Apple changes them now and then). Once per song.
    func refresh(trackId: Int) async -> CatalogTrack? {
        if let r = refreshed[trackId] { return r }
        guard let d = await fetch("https://itunes.apple.com/lookup?id=\(trackId)"),
              let r = try? JSONDecoder().decode(Response.self, from: d), let t = r.results.compactMap(\.track).first
        else { return nil }
        refreshed[trackId] = t
        return t
    }

    /// Most popular songs for an artist on Apple Music.
    func topSongs(artist: String, limit: Int = 12) async -> [CatalogTrack] {
        let key = "itunes-top-v1-\(artist)"
        if let c = await DiskCache.shared.get(key, as: [CatalogTrack].self) { return c }
        guard let d = await fetch("https://itunes.apple.com/search?term=\(q(artist))&entity=musicArtist&limit=5"),
              let r = try? JSONDecoder().decode(Response.self, from: d) else { return [] }
        let a = Self.norm(artist)
        guard let artistId = (r.results.first { Self.norm($0.artistName ?? "") == a } ?? r.results.first)?.artistId,
              let d2 = await fetch("https://itunes.apple.com/lookup?id=\(artistId)&entity=song&limit=\(limit + 10)&sort=popular"),
              let r2 = try? JSONDecoder().decode(Response.self, from: d2) else { return [] }
        var seen = Set<String>()
        let songs = r2.results.compactMap(\.track).filter { seen.insert(Self.norm($0.name)).inserted }
        let result = Array(songs.prefix(limit))
        if !result.isEmpty { await DiskCache.shared.set(key, result) }
        return result
    }
}
