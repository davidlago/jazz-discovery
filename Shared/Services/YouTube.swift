import Foundation

struct YouTubeVideo: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let channel: String?
    let length: String?
    var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg")! }
    var watchURL: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }

    /// YouTube's IDs are 11 URL-safe characters. Anything else is refused: the ID goes into URLs and the player's
    /// HTML as it is.
    static func isValidID(_ id: String) -> Bool { id.wholeMatch(of: /[A-Za-z0-9_-]{11}/) != nil }
}

/// Finds videos by reading YouTube's public search results page (no API key needed).
actor YouTube {
    static let shared = YouTube()
    private var inflight: [String: Task<[YouTubeVideo], Never>] = [:]

    func search(_ query: String, limit: Int = 8) async -> [YouTubeVideo] {
        let key = "yt-search-v1-\(query)"
        if let c = await DiskCache.shared.get(key, as: [YouTubeVideo].self) {
            return Array(c.filter { YouTubeVideo.isValidID($0.id) }.prefix(limit))
        }
        if let t = inflight[query] { return Array(await t.value.prefix(limit)) }
        let task = Task<[YouTubeVideo], Never> {
            guard let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  let url = URL(string: "https://www.youtube.com/results?search_query=\(q)&hl=en&gl=US"),
                  let data = try? await HTTP.data(url, headers: [
                    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
                    "Accept-Language": "en-US,en;q=0.9"]),
                  let html = String(data: data, encoding: .utf8) else { return [] }
            return Self.parse(html)
        }
        inflight[query] = task
        let videos = await task.value
        inflight[query] = nil
        if !videos.isEmpty { await DiskCache.shared.set(key, videos) }
        return Array(videos.prefix(limit))
    }

    static func parse(_ html: String) -> [YouTubeVideo] {
        guard let start = html.range(of: "var ytInitialData = ")
                ?? html.range(of: "window[\"ytInitialData\"] = ") else { return [] }
        let rest = html[start.upperBound...]
        guard let end = rest.range(of: ";</script>") else { return [] }
        let json = rest[..<end.lowerBound]
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var out: [YouTubeVideo] = []
        var seen = Set<String>()
        func text(_ any: Any?) -> String? {
            guard let d = any as? [String: Any] else { return nil }
            if let s = d["simpleText"] as? String { return s }
            if let runs = d["runs"] as? [[String: Any]] { return runs.compactMap { $0["text"] as? String }.joined() }
            return nil
        }
        func walk(_ node: Any) {
            if let d = node as? [String: Any] {
                if let v = d["videoRenderer"] as? [String: Any], let id = v["videoId"] as? String,
                   YouTubeVideo.isValidID(id), let title = text(v["title"]), seen.insert(id).inserted {
                    let isLive = (v["badges"] as? [[String: Any]])?.contains { "\($0)".contains("LIVE") } ?? false
                    if !isLive {
                        out.append(YouTubeVideo(id: id, title: title,
                                                channel: text(v["ownerText"]) ?? text(v["longBylineText"]),
                                                length: text(v["lengthText"])))
                    }
                    return
                }
                for (_, value) in d { walk(value) }
            } else if let a = node as? [Any] {
                for value in a { walk(value) }
            }
        }
        // Walk the main result list in order first; fall back to a full walk.
        if let r = root as? [String: Any],
           let c = r["contents"] as? [String: Any],
           let two = c["twoColumnSearchResultsRenderer"] as? [String: Any],
           let primary = two["primaryContents"] as? [String: Any],
           let list = primary["sectionListRenderer"] as? [String: Any],
           let sections = list["contents"] as? [Any] {
            for section in sections {
                if let item = (section as? [String: Any])?["itemSectionRenderer"] as? [String: Any],
                   let contents = item["contents"] as? [Any] {
                    for entry in contents where (entry as? [String: Any])?["videoRenderer"] != nil { walk(entry) }
                }
            }
        }
        if out.isEmpty { walk(root) }
        return out
    }
}
