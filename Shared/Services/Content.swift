import Foundation
import CryptoKit
import os

// The data files (jazz.json and the rest of Shared/Resources) come with the app, and release builds also follow them on
// main on GitHub, so a merged pull request that changes them reaches the apps without a new release:
//
// 1. At launch and when the app comes back to the front (at most once an hour), the app fetches content.json from main:
//    the SHA-256 of every file (scripts/build-content-manifest.py writes it; CI checks it's up to date).
// 2. It downloads only the files whose hash differs from the ones it has, checks each one against the manifest, and
//    decodes them all, as the app will. Anything that fails (a file the CDN hasn't caught up on, a change this version
//    can't read) leaves the content as it was, to try again later.
// 3. The next launch uses them. The running app never changes its data under the views that show it.
//
// Debug builds use the files they were built with. `-ContentSource <value>` at launch picks another source, in any
// build: `bundle`, a branch (`-ContentSource my-branch`, fetched before the app opens), a folder
// (`-ContentSource ~/Develop/Jazz\ Discovery/Shared/Resources`, in the simulator) or a web address
// (`-ContentSource http://localhost:8642`, scripts/serve-content.sh), read as they are at every launch.

// MARK: - Files

/// Where the data files are read from: a folder of downloaded content when there is one, else the app's bundle.
/// A file missing from the folder is read from the bundle.
struct ContentFiles: @unchecked Sendable {
    var folder: URL?
    var bundle: Bundle

    init(folder: URL? = nil, bundle: Bundle = .main) {
        self.folder = folder
        self.bundle = bundle
    }

    func url(_ name: String) -> URL? {
        if let folder {
            let u = folder.appendingPathComponent("\(name).json")
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return bundle.url(forResource: name, withExtension: "json")
    }

    func data(_ name: String) -> Data? { url(name).flatMap { try? Data(contentsOf: $0) } }

    /// The files this process reads, chosen once at launch.
    static var active: ContentFiles { JazzContent.active.files }
}

// MARK: - Manifest

/// content.json: every data file's hash and size, and the format's version.
struct ContentManifest: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        var sha256: String
        var size: Int
    }

    var schema: Int
    /// By file name ("jazz.json").
    var files: [String: File]

    /// Names the content: the same files with the same hashes give the same revision, however the file is formatted.
    var revision: String {
        let lines = ["schema \(schema)"] + files.keys.sorted().map { "\($0) \(files[$0]!.sha256)" }
        return JazzContent.sha256(Data(lines.joined(separator: "\n").utf8))
    }

    static func bundled(in bundle: Bundle) -> ContentManifest? {
        guard let url = bundle.url(forResource: "content", withExtension: "json"), let d = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(ContentManifest.self, from: d)
    }
}

// MARK: - Sources

enum ContentSource: Equatable, Sendable, CustomStringConvertible {
    /// The files the app was built with.
    case bundle
    /// A branch (or tag, or commit) on GitHub, followed through its content.json.
    case github(String)
    /// A folder or a web address, read as it is at every launch, with no manifest: for trying edits.
    case direct(URL)

    static let repository = "davidlago/jazz-discovery"
    static let resourcesPath = "Shared/Resources"
    /// The user default (and launch argument, `-ContentSource …`) that picks another source.
    static let defaultsKey = "ContentSource"

    /// `bundle`, a path, a web address, or else a branch name.
    init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if t == "bundle" || t == "built-in" {
            self = .bundle
        } else if t.hasPrefix("/") || t.hasPrefix("~") {
            self = .direct(URL(fileURLWithPath: (t as NSString).expandingTildeInPath, isDirectory: true))
        } else if t.contains("://") {
            guard let u = URL(string: t), let scheme = u.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else {
                return nil
            }
            self = .direct(u)
        } else {
            self = .github(t)
        }
    }

    /// Release builds follow main; debug builds (Xcode, the scripts) show the files they were built with.
    static var standard: ContentSource {
        #if DEBUG
        return .bundle
        #else
        return .github("main")
        #endif
    }

    /// The source this launch uses: `-ContentSource` (or the user default) if given, else the standard one.
    static func configured(_ defaults: UserDefaults = .standard) -> ContentSource {
        defaults.string(forKey: defaultsKey).flatMap(ContentSource.init) ?? standard
    }

    /// The folder the files are in.
    var baseURL: URL? {
        switch self {
        case .bundle:
            return nil
        case .github(let ref):
            let r = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
            return URL(string: "https://raw.githubusercontent.com/\(Self.repository)/\(r)/\(Self.resourcesPath)/")
        case .direct(let url):
            return url
        }
    }

    /// The cache folder's name.
    var cacheKey: String {
        switch self {
        case .bundle: return "bundle"
        case .github(let ref): return "github-" + JazzContent.sha256(Data(ref.utf8)).prefix(12)
        case .direct(let url): return "direct-" + JazzContent.sha256(Data(url.absoluteString.utf8)).prefix(12)
        }
    }

    var description: String {
        switch self {
        case .bundle: return "built in"
        case .github(let ref): return "GitHub \(ref)"
        case .direct(let url): return url.isFileURL ? url.path : url.absoluteString
        }
    }
}

// MARK: - The store

enum ContentError: Error, CustomStringConvertible {
    case missing(String)
    case unreadable(String, Error)
    case mismatch(String)
    case badName(String)

    var description: String {
        switch self {
        case .missing(let f): return "\(f) is missing"
        case .unreadable(let f, let e): return "\(f) doesn't decode: \(e)"
        case .mismatch(let f): return "\(f) doesn't match content.json (not published yet, or content.json is out of date)"
        case .badName(let f): return "content.json lists an unexpected file, \(f)"
        }
    }
}

/// Downloaded content, one folder per source and revision, and which revision each source is on.
struct ContentStore: Sendable {
    typealias Fetch = @Sendable (URL) async throws -> Data

    enum UpdateResult: Equatable {
        /// Already has this revision.
        case unchanged
        /// The published files are the ones the app was built with.
        case builtIn
        /// Downloaded and checked; used from the next launch.
        case updated(revision: String)
        /// Published in a format this version doesn't read.
        case incompatible(schema: Int)
    }

    /// Which revision a source is on, and the build it was downloaded by (a new build drops it: its own files are at
    /// least as new as main was when it was made).
    struct Pointer: Codable, Equatable {
        var revision: String
        var built: String
        var fetched: Date
    }

    let root: URL
    let bundle: ContentFiles
    let fetch: Fetch

    init(root: URL, bundle: Bundle = .main, fetch: @escaping Fetch = ContentStore.download) {
        self.root = root
        self.bundle = ContentFiles(bundle: bundle)
        self.fetch = fetch
    }

    /// The app group's container when the build is signed with one (so the widgets read the same content), else
    /// Application Support.
    static var defaultRoot: URL {
        if let id = AppGroup.identifier,
           let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) {
            return dir.appendingPathComponent("Content", isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("JazzDiscovery/Content", isDirectory: true)
    }

    /// Names the build's own files.
    var builtRevision: String { ContentManifest.bundled(in: bundle.bundle)?.revision ?? "none" }

    private func dir(_ source: ContentSource) -> URL { root.appendingPathComponent(source.cacheKey, isDirectory: true) }
    private func pointerURL(_ source: ContentSource) -> URL { dir(source).appendingPathComponent("current.json") }
    private func folder(_ source: ContentSource, _ revision: String) -> URL {
        dir(source).appendingPathComponent(String(revision.prefix(16)), isDirectory: true)
    }

    func pointer(_ source: ContentSource) -> Pointer? {
        guard let d = try? Data(contentsOf: pointerURL(source)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Pointer.self, from: d)
    }

    private func setPointer(_ p: Pointer?, _ source: ContentSource) throws {
        guard let p else { try? FileManager.default.removeItem(at: pointerURL(source)); return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(p).write(to: pointerURL(source), options: .atomic)
    }

    /// The source's downloaded content, when it has some this build can use.
    func cached(_ source: ContentSource) -> (files: ContentFiles, pointer: Pointer)? {
        guard let p = pointer(source), p.built == builtRevision else { return nil }
        let f = folder(source, p.revision)
        guard FileManager.default.fileExists(atPath: f.appendingPathComponent("jazz.json").path) else { return nil }
        return (ContentFiles(folder: f, bundle: bundle.bundle), p)
    }

    /// Brings a GitHub source's downloaded content up to date with its content.json.
    func update(_ source: ContentSource) async throws -> UpdateResult {
        guard case .github = source, let base = source.baseURL else { return .unchanged }
        let manifestData = try await fetch(base.appendingPathComponent("content.json"))
        let manifest = try JSONDecoder().decode(ContentManifest.self, from: manifestData)
        guard manifest.schema == JazzContent.schema else { return .incompatible(schema: manifest.schema) }
        let revision = manifest.revision
        let built = builtRevision
        let fm = FileManager.default
        try fm.createDirectory(at: dir(source), withIntermediateDirectories: true)
        if revision == built {
            try setPointer(nil, source)
            return .builtIn
        }
        let current = cached(source)
        if let current, current.pointer.revision == revision { return .unchanged }

        let partial = dir(source).appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: partial, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: partial) }
        for (name, file) in manifest.files.sorted(by: { $0.key < $1.key }) {
            guard name.range(of: #"^[a-z0-9-]+\.json$"#, options: .regularExpression) != nil, name != "content.json" else {
                throw ContentError.badName(name)
            }
            let stem = String(name.dropLast(5))
            // A file that hasn't changed is copied from what the app has; only the rest is downloaded.
            let have = [current?.files.data(stem), bundle.data(stem)].lazy.compactMap { $0 }
                .first { JazzContent.sha256($0) == file.sha256 }
            let bytes: Data
            if let have {
                bytes = have
            } else {
                // The hash in the query asks the CDN for this version, not one it has kept from before.
                var c = URLComponents(url: base.appendingPathComponent(name), resolvingAgainstBaseURL: false)!
                c.queryItems = [URLQueryItem(name: "v", value: String(file.sha256.prefix(12)))]
                bytes = try await fetch(c.url!)
                guard JazzContent.sha256(bytes) == file.sha256 else { throw ContentError.mismatch(name) }
            }
            try bytes.write(to: partial.appendingPathComponent(name))
        }
        try manifestData.write(to: partial.appendingPathComponent("content.json"))
        // Read it all as the app will before using any of it.
        try JazzLibrary.validate(ContentFiles(folder: partial, bundle: bundle.bundle))

        let target = folder(source, revision)
        try? fm.removeItem(at: target)
        try fm.moveItem(at: partial, to: target)
        try setPointer(Pointer(revision: revision, built: built, fetched: Date()), source)
        return .updated(revision: revision)
    }

    /// Reads a folder or web address as it is, into a folder of its own: every data file the app has, each from there
    /// when it's there (and from the bundle when it isn't).
    func loadDirect(_ base: URL) async throws -> ContentFiles {
        if base.isFileURL {
            let files = ContentFiles(folder: base, bundle: bundle.bundle)
            guard FileManager.default.fileExists(atPath: base.appendingPathComponent("jazz.json").path) else {
                throw ContentError.missing(base.appendingPathComponent("jazz.json").path)
            }
            try JazzLibrary.validate(files)
            return files
        }
        let source = ContentSource.direct(base)
        let target = dir(source)
        let fm = FileManager.default
        try? fm.removeItem(at: target)
        try fm.createDirectory(at: target, withIntermediateDirectories: true)
        let names = (bundle.bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            .map(\.lastPathComponent).filter { $0 != "content.json" }
        for name in names.sorted() {
            guard let d = try? await fetch(base.appendingPathComponent(name)) else { continue }
            try d.write(to: target.appendingPathComponent(name))
        }
        let files = ContentFiles(folder: target, bundle: bundle.bundle)
        guard fm.fileExists(atPath: target.appendingPathComponent("jazz.json").path) else {
            throw ContentError.missing(base.appendingPathComponent("jazz.json").absoluteString)
        }
        try JazzLibrary.validate(files)
        return files
    }

    /// Removes a source's revisions other than the one it's on.
    func prune(_ source: ContentSource) {
        let keep = pointer(source).map { String($0.revision.prefix(16)) }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir(source), includingPropertiesForKeys: nil) else { return }
        for item in items where item.lastPathComponent != "current.json" && item.lastPathComponent != keep {
            try? fm.removeItem(at: item)
        }
    }

    /// Plain downloads that always ask the server (the app's shared session answers from its cache when it can).
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    @Sendable static func download(_ url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        var req = URLRequest(url: url)
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse, userInfo: ["status": http.statusCode, "url": url.absoluteString])
        }
        return data
    }
}

// MARK: - This launch

enum JazzContent {
    /// The data format's version, the same as "schema" in content.json. The app only takes published content with its
    /// own schema, so bump both (scripts/build-content-manifest.py --schema N) when a change would break older apps: a
    /// field they need renamed, removed or given another type. Older apps then keep what they have.
    static let schema = 1

    static let log = Logger(subsystem: "io.github.davidlago.JazzDiscovery", category: "content")

    struct Active: Sendable {
        let source: ContentSource
        let files: ContentFiles
        /// For Settings: where the content came from, and when.
        let summary: String
    }

    /// What this process reads, chosen at first use (when the app makes its library).
    static let active: Active = {
        #if WIDGET_EXTENSION
        // The widgets read what the app has downloaded, and never fetch.
        let source = ContentSource.standard
        let store = ContentStore(root: ContentStore.defaultRoot)
        if let c = store.cached(source) { return Active(source: source, files: c.files, summary: "") }
        return Active(source: source, files: store.bundle, summary: "")
        #else
        return resolve(ContentSource.configured(), store: ContentStore(root: ContentStore.defaultRoot))
        #endif
    }()

    static func resolve(_ source: ContentSource, store: ContentStore) -> Active {
        let bundled = store.bundle
        switch source {
        case .bundle:
            return Active(source: source, files: bundled, summary: "Built in")
        case .direct(let base):
            switch wait(seconds: 30, { try await store.loadDirect(base) }) {
            case .success(let files)?:
                log.notice("Content from \(source.description, privacy: .public)")
                return Active(source: source, files: files, summary: "From \(source)")
            case .failure(let error)?:
                log.error("Couldn't read \(source.description, privacy: .public): \(String(describing: error), privacy: .public)")
                print("Jazz Discovery: couldn't read the content at \(source): \(error). Showing the built-in content.")
                return Active(source: source, files: bundled, summary: "Built in (\(source) didn't load: \(error))")
            case nil:
                return Active(source: source, files: bundled, summary: "Built in (\(source) timed out)")
            }
        case .github(let ref):
            var note = ""
            if source != ContentSource.standard {
                // Asked for at launch: fetch it now, so what opens is the branch as it is.
                switch wait(seconds: 20, { try await store.update(source) }) {
                case .success(.incompatible(let schema))?:
                    note = " (\(ref) has schema \(schema); this build reads \(JazzContent.schema))"
                case .failure(let error)?:
                    print("Jazz Discovery: couldn't update the content from \(source): \(error)")
                    note = " (update failed: \(error))"
                case nil:
                    note = " (update timed out)"
                default:
                    break
                }
            }
            store.prune(source)
            if let c = store.cached(source) {
                let date = c.pointer.fetched.formatted(date: .abbreviated, time: .shortened)
                let label = source == ContentSource.standard ? "Updated \(date)" : "\(source), \(date)"
                log.notice("Content \(c.pointer.revision.prefix(12), privacy: .public) from \(source.description, privacy: .public)")
                return Active(source: source, files: c.files, summary: label + note)
            }
            return Active(source: source, files: bundled,
                          summary: (source == ContentSource.standard ? "Built in" : "Built in, same as \(ref)") + note)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Runs async work from synchronous code (the app's launch) and waits for it, up to a limit. Nil when it ran out.
    private static func wait<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) -> Result<T, Error>? {
        let box = ResultBox<T>()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
            done.signal()
        }
        guard done.wait(timeout: .now() + seconds) == .success else { return nil }
        return box.result
    }
}

private final class ResultBox<T>: @unchecked Sendable { var result: Result<T, Error>? }

#if !WIDGET_EXTENSION
/// Checks for new content in the background: at launch and when the app comes to the front, at most once an hour.
actor ContentUpdater {
    static let shared = ContentUpdater()
    private var lastCheck: Date?
    private var checking = false

    /// Call when the app becomes active.
    nonisolated static func check() { Task.detached(priority: .utility) { await shared.checkIfDue() } }

    func checkIfDue() async {
        let source = JazzContent.active.source
        guard case .github = source, !checking else { return }
        if let lastCheck, Date().timeIntervalSince(lastCheck) < 3600 { return }
        checking = true
        defer { checking = false }
        lastCheck = Date()
        do {
            let result = try await ContentStore(root: ContentStore.defaultRoot).update(source)
            JazzContent.log.notice("Content check (\(source.description, privacy: .public)): \(String(describing: result), privacy: .public)")
        } catch {
            JazzContent.log.error("Content check failed: \(String(describing: error), privacy: .public)")
        }
    }
}
#endif
