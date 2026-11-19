import Foundation
import Testing

/// Serves files by name, as raw.githubusercontent.com would, and notes what was asked for.
final class FakeServer: @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: Data] = [:]
    private var asked: [String] = []

    subscript(name: String) -> Data? {
        get { lock.withLock { files[name] } }
        set { lock.withLock { files[name] = newValue } }
    }

    var requested: [String] { lock.withLock { asked } }
    func forget() { lock.withLock { asked = [] } }

    func fetch(_ url: URL) throws -> Data {
        let name = url.lastPathComponent
        return try lock.withLock {
            asked.append(name)
            guard let d = files[name] else { throw URLError(.fileDoesNotExist) }
            return d
        }
    }
}

@Suite("Content from GitHub")
struct ContentTests {
    let bundle = TestBundle.bundle
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("content-tests-\(UUID().uuidString)")
    let main = ContentSource.github("main")
    let server = FakeServer()

    var store: ContentStore {
        let server = server
        return ContentStore(root: root, bundle: bundle, fetch: { try server.fetch($0) })
    }

    func bundled(_ name: String) throws -> Data {
        try Data(contentsOf: try #require(bundle.url(forResource: name, withExtension: "json")))
    }

    /// Publishes the bundle's files, with another jazz.json if given.
    @discardableResult
    func publish(jazz: Data? = nil, servedJazz: Data? = nil, schema: Int = JazzContent.schema) throws -> ContentManifest {
        var manifest = try #require(ContentManifest.bundled(in: bundle))
        manifest.schema = schema
        for name in manifest.files.keys { server[name] = try bundled(String(name.dropLast(5))) }
        if let jazz {
            manifest.files["jazz.json"] = .init(sha256: JazzContent.sha256(jazz), size: jazz.count)
            server["jazz.json"] = servedJazz ?? jazz
        }
        server["content.json"] = try JSONEncoder().encode(manifest)
        return manifest
    }

    /// jazz.json with its first artist renamed.
    func renamedJazz(_ name: String) throws -> Data {
        var obj = try #require(JSONSerialization.jsonObject(with: try bundled("jazz")) as? [String: Any])
        var artists = try #require(obj["artists"] as? [[String: Any]])
        artists[0]["name"] = name
        obj["artists"] = artists
        return try JSONSerialization.data(withJSONObject: obj)
    }

    func firstArtist(_ files: ContentFiles) -> String? {
        JazzLibrary.load(from: files).artists.first?.name
    }

    @Test("Sources: bundle, a branch, a folder, a web address")
    func sources() {
        #expect(ContentSource("bundle") == .bundle)
        #expect(ContentSource("main") == .github("main"))
        #expect(ContentSource("content/new-artists") == .github("content/new-artists"))
        #expect(ContentSource("/tmp/Resources") == .direct(URL(fileURLWithPath: "/tmp/Resources", isDirectory: true)))
        #expect(ContentSource("http://localhost:8642") == .direct(URL(string: "http://localhost:8642")!))
        #expect(ContentSource("ftp://example.com") == nil)
        #expect(ContentSource("  ") == nil)
        #expect(ContentSource.github("main").baseURL?.absoluteString
                == "https://raw.githubusercontent.com/davidlago/jazz-discovery/main/Shared/Resources/")
        #expect(ContentSource.github("a/b").cacheKey != ContentSource.github("main").cacheKey)
    }

    @Test("A launch argument picks the source")
    func configured() throws {
        let defaults = try #require(UserDefaults(suiteName: "content-tests-\(UUID().uuidString)"))
        #expect(ContentSource.configured(defaults) == ContentSource.standard)
        defaults.set("my-branch", forKey: ContentSource.defaultsKey)
        #expect(ContentSource.configured(defaults) == .github("my-branch"))
    }

    @Test("content.json matches the files it lists, in this app's schema")
    func bundledManifest() throws {
        let manifest = try #require(ContentManifest.bundled(in: bundle), "run scripts/build-content-manifest.py")
        #expect(manifest.schema == JazzContent.schema)
        #expect(manifest.files["jazz.json"] != nil)
        for (name, file) in manifest.files {
            let data = try bundled(String(name.dropLast(5)))
            #expect(JazzContent.sha256(data) == file.sha256, "\(name) changed: run scripts/build-content-manifest.py")
            #expect(data.count == file.size)
        }
        // The revision doesn't depend on how the file is written.
        let compact = try JSONDecoder().decode(ContentManifest.self, from: JSONEncoder().encode(manifest))
        #expect(compact.revision == manifest.revision)
    }

    @Test("New content: only what changed is downloaded, checked, and used from then on")
    func update() async throws {
        let jazz = try renamedJazz("Test Artist")
        try publish(jazz: jazz)
        #expect(store.cached(main) == nil)

        guard case .updated = try await store.update(main) else { Issue.record("not updated"); return }
        #expect(server.requested == ["content.json", "jazz.json"])
        let cached = try #require(store.cached(main))
        #expect(firstArtist(cached.files) == "Test Artist")
        // The unchanged files are copied in, so the folder is complete on its own.
        #expect(cached.files.url("sessions")?.path.hasPrefix(root.path) == true)

        server.forget()
        #expect(try await store.update(main) == .unchanged)
        #expect(server.requested == ["content.json"])

        // What a launch picks.
        let active = JazzContent.resolve(main, store: store)
        #expect(active.files.folder == cached.files.folder)
        #expect(firstArtist(active.files) == "Test Artist")
    }

    @Test("Published files the same as the build's: the build's own are used")
    func builtIn() async throws {
        try publish(jazz: try renamedJazz("Test Artist"))
        _ = try await store.update(main)
        try publish()
        #expect(try await store.update(main) == .builtIn)
        #expect(store.cached(main) == nil)
        #expect(JazzContent.resolve(main, store: store).files.folder == nil)
    }

    @Test("A file that doesn't match content.json (the CDN behind) leaves the content as it was")
    func mismatch() async throws {
        try publish(jazz: try renamedJazz("Test Artist"), servedJazz: try bundled("jazz"))
        await #expect(throws: ContentError.self) { try await store.update(main) }
        #expect(store.cached(main) == nil)
    }

    @Test("Content this version can't read isn't used")
    func undecodable() async throws {
        try publish(jazz: Data(#"{"eras": 5}"#.utf8))
        await #expect(throws: ContentError.self) { try await store.update(main) }
        #expect(store.cached(main) == nil)
        #expect(JazzContent.resolve(main, store: store).files.folder == nil)
    }

    @Test("Another schema: nothing is downloaded")
    func incompatible() async throws {
        try publish(jazz: try renamedJazz("Test Artist"), schema: JazzContent.schema + 1)
        #expect(try await store.update(main) == .incompatible(schema: JazzContent.schema + 1))
        #expect(server.requested == ["content.json"])
        #expect(store.cached(main) == nil)
    }

    @Test("A new build drops content an older one downloaded")
    func newBuild() async throws {
        try publish(jazz: try renamedJazz("Test Artist"))
        _ = try await store.update(main)
        let pointerURL = root.appendingPathComponent(main.cacheKey).appendingPathComponent("current.json")
        var pointer = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: pointerURL)) as? [String: Any])
        pointer["built"] = "an older build"
        try JSONSerialization.data(withJSONObject: pointer).write(to: pointerURL)
        #expect(store.cached(main) == nil)
    }

    @Test("Old revisions are removed")
    func prune() async throws {
        try publish(jazz: try renamedJazz("First"))
        _ = try await store.update(main)
        try publish(jazz: try renamedJazz("Second"))
        _ = try await store.update(main)
        store.prune(main)
        let dir = root.appendingPathComponent(main.cacheKey)
        let items = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(items.count == 2 && items.contains("current.json"))
        #expect(firstArtist(try #require(store.cached(main)).files) == "Second")
    }

    @Test("A folder is read as it is, and the bundle fills in what it doesn't have")
    func folder() async throws {
        let dir = root.appendingPathComponent("edits", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try renamedJazz("Edited").write(to: dir.appendingPathComponent("jazz.json"))
        let active = JazzContent.resolve(.direct(dir), store: store)
        #expect(active.files.folder == dir)
        #expect(firstArtist(active.files) == "Edited")
        #expect(active.files.url("sessions") == bundle.url(forResource: "sessions", withExtension: "json"))

        // One that doesn't decode: the built-in content, and Settings says why.
        try Data("{".utf8).write(to: dir.appendingPathComponent("jazz.json"))
        let broken = JazzContent.resolve(.direct(dir), store: store)
        #expect(broken.files.folder == nil)
        #expect(broken.summary.contains("didn't load"))
    }

    @Test("A web address is downloaded at launch")
    func web() async throws {
        server["jazz.json"] = try renamedJazz("Served")
        let active = JazzContent.resolve(.direct(URL(string: "http://localhost:8642/")!), store: store)
        #expect(firstArtist(active.files) == "Served")
        #expect(server.requested.contains("sessions.json"))
    }
}
