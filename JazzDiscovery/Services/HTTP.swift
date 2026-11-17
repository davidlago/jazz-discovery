import Foundation

enum HTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 64 << 20, diskCapacity: 512 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    static let userAgent = "JazzDiscovery/1.0 (macOS; educational jazz explorer)"

    static func data(_ url: URL, headers: [String: String] = [:]) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: ["status": http.statusCode])
        }
        return data
    }

    static func json<T: Decodable>(_ type: T.Type, _ url: URL) async throws -> T {
        try JSONDecoder().decode(T.self, from: try await data(url))
    }
}

/// Small persistent JSON cache in Application Support (survives relaunches).
actor DiskCache {
    static let shared = DiskCache()
    private var memory: [String: Data] = [:]
    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("JazzDiscovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private func file(_ key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? key
        return dir.appendingPathComponent(String(safe.prefix(200)) + ".json")
    }

    func get<T: Decodable>(_ key: String, as: T.Type) -> T? {
        if let d = memory[key] { return try? JSONDecoder().decode(T.self, from: d) }
        guard let d = try? Data(contentsOf: file(key)) else { return nil }
        memory[key] = d
        return try? JSONDecoder().decode(T.self, from: d)
    }

    func set<T: Encodable>(_ key: String, _ value: T) {
        guard let d = try? JSONEncoder().encode(value) else { return }
        memory[key] = d
        try? d.write(to: file(key), options: .atomic)
    }
}
