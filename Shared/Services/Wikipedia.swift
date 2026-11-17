import Foundation

struct WikiSummary: Codable, Hashable {
    let title: String
    let extract: String
    let image: URL?
    let largeImage: URL?
    let pageURL: URL?
}

struct WikiImage: Codable, Hashable, Identifiable {
    let url: URL
    let caption: String?
    var id: URL { url }
}

/// Wikipedia REST API — public, CC BY-SA text and freely licensed Commons media.
actor Wikipedia {
    static let shared = Wikipedia()
    private var inflight: [String: Task<WikiSummary?, Never>] = [:]

    private struct RawSummary: Decodable {
        struct Img: Decodable { let source: URL; let width: Int? }
        struct URLs: Decodable { struct D: Decodable { let page: URL? }; let desktop: D? }
        let title: String
        let extract: String?
        let thumbnail: Img?
        let originalimage: Img?
        let content_urls: URLs?
    }

    private static func encode(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#")))
            ?? title
    }

    func summary(_ title: String) async -> WikiSummary? {
        let key = "wiki-summary-v3-\(title)"
        if let cached = await DiskCache.shared.get(key, as: WikiSummary.self) { return cached }
        if let t = inflight[title] { return await t.value }
        let task = Task<WikiSummary?, Never> {
            guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(Self.encode(title))"),
                  let raw = try? await HTTP.json(RawSummary.self, url) else { return nil }
            // Ask for sharper renditions than the default thumbnail, without exceeding the original.
            func rendition(_ width: Int) -> URL? {
                guard let thumb = raw.thumbnail?.source else { return raw.originalimage?.source }
                if let orig = raw.originalimage, (orig.width ?? .max) <= width { return orig.source }
                return Self.resize(thumb, to: width)
            }
            return WikiSummary(title: raw.title, extract: raw.extract ?? "", image: rendition(500),
                               largeImage: rendition(1280), pageURL: raw.content_urls?.desktop?.page)
        }
        inflight[title] = task
        let result = await task.value
        inflight[title] = nil
        if let result { await DiskCache.shared.set(key, result) }
        return result
    }

    /// The article's lead image, or the first gallery image when the article has none.
    func leadImage(_ title: String) async -> URL? {
        let s = await summary(title)
        if let img = s?.largeImage ?? s?.image { return img }
        return await images(title, limit: 1).first?.url
    }

    private struct RawMedia: Decodable {
        struct Item: Decodable {
            struct Src: Decodable { let src: String; let scale: String? }
            struct Cap: Decodable { let text: String? }
            let type: String
            let title: String?
            let srcset: [Src]?
            let caption: Cap?
            let showInGallery: Bool?
        }
        let items: [Item]
    }

    /// Freely licensed images used on the article (via Wikimedia Commons).
    func images(_ title: String, limit: Int = 12) async -> [WikiImage] {
        let key = "wiki-media-v2-\(title)"
        if let cached = await DiskCache.shared.get(key, as: [WikiImage].self) { return cached }
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/media-list/\(Self.encode(title))"),
              let raw = try? await HTTP.json(RawMedia.self, url) else { return [] }
        let images: [WikiImage] = raw.items.compactMap { item in
            guard item.type == "image", item.showInGallery ?? true,
                  let name = item.title?.lowercased(),
                  !name.hasSuffix(".svg"), !name.contains("icon"), !name.contains("logo"), !name.contains("flag"),
                  let src = item.srcset?.last?.src else { return nil }
            let full = src.hasPrefix("//") ? "https:" + src : src
            guard let u = URL(string: full) else { return nil }
            let cap = item.caption?.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return WikiImage(url: u, caption: (cap?.isEmpty ?? true) ? nil : cap)
        }
        let result = Array(images.prefix(limit))
        await DiskCache.shared.set(key, result)
        return result
    }

    /// Widths Wikimedia serves thumbnails at; other widths are refused (HTTP 400/429).
    nonisolated static let buckets = [120, 250, 330, 500, 960, 1280, 1920]

    /// Commons thumbnail URLs embed the width as `/NNNpx-`; swap it for another standard rendition.
    nonisolated static func resize(_ url: URL, to requested: Int) -> URL {
        let width = buckets.first { $0 >= requested } ?? buckets.last!
        let s = url.absoluteString
        guard s.contains("/thumb/"), let r = s.range(of: #"/\d+px-"#, options: .regularExpression) else { return url }
        return URL(string: s.replacingCharacters(in: r, with: "/\(width)px-")) ?? url
    }
}
