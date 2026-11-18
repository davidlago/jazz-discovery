import CryptoKit
import Foundation
import Observation
import Security

/// One play, as Last.fm sees it.
struct ScrobbleTrack: Codable, Equatable, Identifiable {
    var artist: String
    var title: String
    var album: String?
    var duration: Double?
    var startedAt: Date
    var id: String { "\(Int(startedAt.timeIntervalSince1970))-\(artist)-\(title)" }
}

enum LastFMError: LocalizedError {
    case api(code: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .api(let code, let message): return message.isEmpty ? "Last.fm error \(code)." : "Last.fm: \(message)"
        case .badResponse: return "Last.fm sent a response the app couldn't read."
        }
    }
}

/// Signed calls to the Last.fm API (https://www.last.fm/api).
struct LastFMAPI {
    let key: String
    let secret: String

    private static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private static let session = URLSession(configuration: .ephemeral)

    func call(_ method: String, _ params: [String: String] = [:], sessionKey: String? = nil) async throws -> [String: Any] {
        var p = params
        p["method"] = method
        p["api_key"] = key
        if let sessionKey { p["sk"] = sessionKey }
        p["api_sig"] = Self.signature(p, secret: secret)
        p["format"] = "json"

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = Data(Self.form(p).utf8)
        // Last.fm puts its error object in the body of 4xx responses too, so read the body whatever the status.
        let (data, _) = try await Self.session.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LastFMError.badResponse }
        if let code = json["error"] as? Int { throw LastFMError.api(code: code, message: json["message"] as? String ?? "") }
        return json
    }

    /// The page where the user allows access. With a callback, Last.fm sends the browser back to it once they have,
    /// which closes the iPhone's sign-in sheet by itself.
    func authorizeURL(token: String, callback: URL? = nil) -> URL {
        var c = URLComponents(string: "https://www.last.fm/api/auth/")!
        c.queryItems = [URLQueryItem(name: "api_key", value: key), URLQueryItem(name: "token", value: token)]
        if let callback { c.queryItems?.append(URLQueryItem(name: "cb", value: callback.absoluteString)) }
        return c.url!
    }

    /// md5 of every parameter (except format and callback) as name+value, sorted by name, then the shared secret.
    static func signature(_ params: [String: String], secret: String) -> String {
        let base = params.filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key < $1.key }
            .map { $0.key + $0.value }
            .joined() + secret
        return Insecure.MD5.hash(data: Data(base.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func form(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        return params.map { enc($0.key) + "=" + enc($0.value) }.joined(separator: "&")
    }
}

/// Connects to Last.fm with the user's own API account and scrobbles full tracks as they play.
///
/// Follows Last.fm's rules: a track is scrobbled once it has played for half its length or 4 minutes, whichever comes
/// first, and only if it's longer than 30 seconds. Scrobbles that can't be sent (offline, Last.fm down) wait on disk
/// and go out with the next one, or with Send Now.
@MainActor
@Observable
final class Scrobbler {
    enum Status: Equatable {
        case notConfigured
        case disconnected
        case authorizing
        case connected(user: String)
        case needsReauthorization(user: String)
    }

    /// Presents Last.fm's authorization page. The Mac opens it in the browser; the iPhone app shows it in a sign-in
    /// sheet (and gets the URL Last.fm redirects to back, or nil once the user closes it).
    typealias AuthorizationPresenter = @MainActor (URL) async -> URL?

    /// The app's own API account, when the build has one (LASTFM_API_KEY and LASTFM_SHARED_SECRET build settings, in
    /// the Info.plist as LastFMAPIKey and LastFMSharedSecret). The user's own account, if they enter one, wins.
    static let builtInAPI: LastFMAPI? = {
        let info = Bundle.main.infoDictionary
        let k = (info?["LastFMAPIKey"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        let s = (info?["LastFMSharedSecret"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return k.isEmpty || s.isEmpty || k.hasPrefix("$(") ? nil : LastFMAPI(key: k, secret: s)
    }()

    /// Where Last.fm sends the browser back to after the user allows access (the iPhone app's URL scheme).
    static let callbackURL = URL(string: "jazzdiscovery://lastfm-auth")!

    /// The user's Last.fm API account. Both are kept in the keychain.
    var apiKey: String {
        didSet {
            guard apiKey != oldValue else { return }
            let saved = Keychain.set(apiKey, for: Keys.apiKey)
            credentialsChanged(keyChanged: true)
            if !saved { lastError = Self.notSaved("API key") }
        }
    }
    var sharedSecret: String {
        didSet {
            guard sharedSecret != oldValue else { return }
            let saved = Keychain.set(sharedSecret, for: Keys.secret)
            credentialsChanged(keyChanged: false)
            if !saved { lastError = Self.notSaved("shared secret") }
        }
    }

    private static func notSaved(_ what: String) -> String {
        "The keychain wouldn't keep the \(what), so it will be gone the next time the app opens."
    }
    var scrobblingEnabled: Bool {
        didSet { UserDefaults.standard.set(scrobblingEnabled, forKey: Keys.enabled); if scrobblingEnabled { flush() } }
    }
    var sendsNowPlaying: Bool {
        didSet { UserDefaults.standard.set(sendsNowPlaying, forKey: Keys.nowPlaying) }
    }

    private(set) var status: Status = .notConfigured
    private(set) var lastError: String?
    private(set) var pendingCount = 0
    private(set) var isSending = false
    /// Most recent first; only scrobbles sent during this run.
    private(set) var recent: [ScrobbleTrack] = []
    /// Whether the track playing now has already been scrobbled.
    private(set) var currentScrobbled = false

    var isConfigured: Bool { api != nil }
    /// Whether plays are being scrobbled right now.
    var isActive: Bool { scrobblingEnabled && sessionKey != nil && api != nil }
    var userName: String? {
        switch status {
        case .connected(let u), .needsReauthorization(let u): return u
        default: return nil
        }
    }

    @ObservationIgnored private var sessionKey: String?
    @ObservationIgnored private var current: ScrobbleTrack?
    @ObservationIgnored private var playedSeconds: Double = 0
    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private var authURL: URL?
    @ObservationIgnored private var presenter: AuthorizationPresenter = Scrobbler.openInBrowser
    @ObservationIgnored private var presenting: Task<Void, Never>?
    private var queue: [ScrobbleTrack] = [] { didSet { pendingCount = queue.count } }

    private enum Keys {
        static let apiKey = "apiKey"
        static let secret = "apiSecret"
        static let session = "session"
        static let user = "lastfmUser"
        static let enabled = "lastfmScrobbling"
        static let nowPlaying = "lastfmNowPlaying"
    }

    private static let queueFile: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("JazzDiscovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lastfm-queue.json")
    }()

    init() {
        let d = UserDefaults.standard
        #if os(iOS)
        Keychain.tightenAccess()
        #endif
        apiKey = Keychain.string(Keys.apiKey) ?? ""
        sharedSecret = Keychain.string(Keys.secret) ?? ""
        scrobblingEnabled = d.object(forKey: Keys.enabled) as? Bool ?? true
        sendsNowPlaying = d.object(forKey: Keys.nowPlaying) as? Bool ?? true
        if let data = try? Data(contentsOf: Self.queueFile),
           let saved = try? JSONDecoder().decode([ScrobbleTrack].self, from: data) {
            queue = saved
        }
        pendingCount = queue.count
        sessionKey = Keychain.string(Keys.session)
        updateStatus()
        flush()
    }

    var api: LastFMAPI? { ownAPI ?? Self.builtInAPI }

    /// The API account the user entered, if any.
    var ownAPI: LastFMAPI? {
        let k = apiKey.trimmingCharacters(in: .whitespaces), s = sharedSecret.trimmingCharacters(in: .whitespaces)
        return k.isEmpty || s.isEmpty ? nil : LastFMAPI(key: k, secret: s)
    }

    /// Whether scrobbling works without the user creating an API account.
    var usesBuiltInAPI: Bool { ownAPI == nil && Self.builtInAPI != nil }

    var profileURL: URL? {
        guard let u = userName?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "https://www.last.fm/user/\(u)")
    }

    private func updateStatus() {
        guard authTask == nil else { status = .authorizing; return }
        let user = UserDefaults.standard.string(forKey: Keys.user)
        if !isConfigured { status = .notConfigured }
        else if sessionKey != nil { status = .connected(user: user ?? "Last.fm") }
        else if let user { status = .needsReauthorization(user: user) }
        else { status = .disconnected }
    }

    /// A session belongs to the API key it was made with, so a new key needs a new connection.
    private func credentialsChanged(keyChanged: Bool) {
        if keyChanged, sessionKey != nil || UserDefaults.standard.string(forKey: Keys.user) != nil { disconnect() }
        lastError = nil
        updateStatus()
    }

    // MARK: Connecting

    /// Desktop auth: get a token, let the user approve it on last.fm, then trade it for a session. The token is polled
    /// for, so it works whether or not the page comes back to the app.
    func connect(presentingWith presenter: AuthorizationPresenter? = nil) {
        guard let api else { updateStatus(); return }
        if let presenter { self.presenter = presenter }
        authTask?.cancel()
        lastError = nil
        status = .authorizing
        authTask = Task {
            defer {
                if !Task.isCancelled {
                    // Closes the iPhone's sign-in sheet too, once access was allowed (or the attempt failed).
                    presenting?.cancel(); presenting = nil
                    authTask = nil; authURL = nil; updateStatus()
                }
            }
            do {
                let json = try await api.call("auth.getToken")
                guard let token = json["token"] as? String else { throw LastFMError.badResponse }
                let url = api.authorizeURL(token: token, callback: Self.usesCallback ? Self.callbackURL : nil)
                authURL = url
                present(url)
                // Tokens last an hour; give the user a few minutes to approve.
                for _ in 0..<(300 / Self.pollSeconds) {
                    try await Task.sleep(for: .seconds(Self.pollSeconds))
                    let reply: [String: Any]
                    do {
                        reply = try await api.call("auth.getSession", ["token": token])
                    } catch LastFMError.api(let code, _) where code == 14 {
                        continue  // not approved yet
                    } catch let e as LastFMError {
                        throw e  // e.g. the token expired
                    } catch {
                        if Task.isCancelled { return }
                        continue  // a network blip; keep waiting
                    }
                    guard let session = reply["session"] as? [String: Any], let key = session["key"] as? String else {
                        throw LastFMError.badResponse
                    }
                    if !Keychain.set(key, for: Keys.session) { lastError = Self.notSaved("Last.fm connection") }
                    UserDefaults.standard.set(session["name"] as? String ?? "Last.fm", forKey: Keys.user)
                    sessionKey = key
                    authTask = nil
                    presenting?.cancel()
                    presenting = nil
                    flush()
                    return
                }
                lastError = "Timed out waiting for Last.fm authorization. Try connecting again."
            } catch {
                if !Task.isCancelled { lastError = error.localizedDescription }
            }
        }
    }

    func reopenAuthorizationPage() {
        if let authURL { present(authURL) }
    }

    func cancelAuthorization() {
        authTask?.cancel()
        authTask = nil
        authURL = nil
        presenting?.cancel()
        presenting = nil
        updateStatus()
    }

    private func present(_ url: URL) {
        let presenter = self.presenter
        presenting?.cancel()
        presenting = Task { _ = await presenter(url) }
    }

    @MainActor private static func openInBrowser(_ url: URL) async -> URL? {
        Platform.open(url)
        return nil
    }

    #if os(iOS)
    private static let usesCallback = true
    private static let pollSeconds = 2
    #else
    private static let usesCallback = false
    private static let pollSeconds = 3
    #endif

    func disconnect() {
        authTask?.cancel()
        authTask = nil
        presenting?.cancel()
        presenting = nil
        authURL = nil
        sessionKey = nil
        Keychain.set(nil, for: Keys.session)
        UserDefaults.standard.removeObject(forKey: Keys.user)
        updateStatus()
    }

    // MARK: Playback events (from PlayerController)

    func trackStarted(_ track: ScrobbleTrack) {
        current = track
        playedSeconds = 0
        currentScrobbled = false
        flush()
        guard isActive, sendsNowPlaying, let api, let sk = sessionKey else { return }
        var p = ["artist": track.artist, "track": track.title]
        if let a = track.album, !a.isEmpty { p["album"] = a }
        if let d = track.duration, d > 0 { p["duration"] = String(Int(d)) }
        Task {
            do { _ = try await api.call("track.updateNowPlaying", p, sessionKey: sk) }
            catch let e as LastFMError { handleAccountError(e) }
            catch {}
        }
    }

    /// Fills in details MusicKit only had once the track had started.
    func refineCurrent(album: String?, duration: Double?) {
        guard var t = current else { return }
        if t.album == nil { t.album = album }
        if t.duration == nil, let duration, duration > 0 { t.duration = duration }
        if t != current { current = t }
    }

    /// Called as the track plays, with the seconds of real listening since the last call.
    func played(_ seconds: Double) {
        guard let t = current, !currentScrobbled else { return }
        playedSeconds += seconds
        guard isActive, playedSeconds >= Self.threshold(for: t) else { return }
        currentScrobbled = true
        queue.append(t)
        if queue.count > 2000 { queue.removeFirst(queue.count - 2000) }
        saveQueue()
        flush()
    }

    func trackStopped() {
        current = nil
        playedSeconds = 0
        currentScrobbled = false
    }

    static func threshold(for t: ScrobbleTrack) -> Double {
        guard let d = t.duration, d > 0 else { return 240 }
        return d > 30 ? min(d / 2, 240) : .infinity
    }

    // MARK: Sending

    /// Sends queued scrobbles in batches of 50. Failures leave them queued for the next try.
    func flush() {
        guard !isSending, !queue.isEmpty, isActive, let api, let sk = sessionKey else { return }
        isSending = true
        Task {
            defer { isSending = false }
            while !queue.isEmpty, isActive {
                let batch = Array(queue.prefix(50))
                var p: [String: String] = [:]
                for (i, t) in batch.enumerated() {
                    p["artist[\(i)]"] = t.artist
                    p["track[\(i)]"] = t.title
                    p["timestamp[\(i)]"] = String(Int(t.startedAt.timeIntervalSince1970))
                    if let a = t.album, !a.isEmpty { p["album[\(i)]"] = a }
                    if let d = t.duration, d > 0 { p["duration[\(i)]"] = String(Int(d)) }
                }
                do {
                    let reply = try await api.call("track.scrobble", p, sessionKey: sk)
                    // Scrobbles Last.fm ignores (too old, filtered) won't succeed later either, so they go too.
                    queue.removeFirst(min(batch.count, queue.count))
                    saveQueue()
                    recent.insert(contentsOf: batch.reversed(), at: 0)
                    if recent.count > 20 { recent.removeLast(recent.count - 20) }
                    lastError = Self.ignoredCount(reply) > 0 ? "Last.fm ignored \(Self.ignoredCount(reply)) of the scrobbles it was sent." : nil
                } catch let e as LastFMError {
                    if case .api(let code, _) = e, code == 6 || code == 7 {
                        // A request Last.fm will never accept; drop it rather than block the queue.
                        queue.removeFirst(min(batch.count, queue.count))
                        saveQueue()
                    }
                    lastError = e.localizedDescription
                    handleAccountError(e)
                    return
                } catch {
                    lastError = "Couldn't reach Last.fm (\(error.localizedDescription)). Scrobbles are kept and sent later."
                    return
                }
            }
        }
    }

    private static func ignoredCount(_ reply: [String: Any]) -> Int {
        let attr = (reply["scrobbles"] as? [String: Any])?["@attr"] as? [String: Any]
        if let n = attr?["ignored"] as? Int { return n }
        return Int(attr?["ignored"] as? String ?? "") ?? 0
    }

    private func handleAccountError(_ e: LastFMError) {
        guard case .api(let code, _) = e else { return }
        switch code {
        case 9:  // invalid session key: access was revoked on last.fm
            sessionKey = nil
            Keychain.set(nil, for: Keys.session)
            updateStatus()
            lastError = "Last.fm no longer accepts this session. Connect again to resume scrobbling; plays are kept until then."
        case 10, 13, 26:  // invalid or suspended API key, bad signature (wrong secret)
            lastError = "Last.fm rejected the API key or secret: \(e.localizedDescription)"
        default:
            break  // 11, 16, 29: Last.fm is busy; retry later
        }
    }

    private func saveQueue() {
        if queue.isEmpty { try? FileManager.default.removeItem(at: Self.queueFile); return }
        if let data = try? JSONEncoder().encode(queue) { try? data.write(to: Self.queueFile, options: .atomic) }
    }
}

/// Generic passwords in the login keychain, for the Last.fm API key, shared secret and session key.
enum Keychain {
    /// "io.github.davidlago.JazzDiscovery.lastfm" for the app. A build with another bundle ID (a test copy, a Personal
    /// Team build) keeps its own items: on the Mac, reading another app's items makes the system ask to allow it, once
    /// per item, and again after every rebuild.
    private static let service = (Bundle.main.bundleIdentifier ?? "io.github.davidlago.JazzDiscovery") + ".lastfm"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func string(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Stores the value (nil or empty removes it). False when the keychain refused to keep it.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        #if os(iOS)
        q[kSecAttrAccessible as String] = accessibility
        #endif
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    #if os(iOS)
    /// Readable once the iPhone has been unlocked since it started (songs scrobble while it's locked), and never
    /// copied into a backup or onto another device.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// Moves items saved before that rule (as "when unlocked", which travels with backups) over to it.
    static func tightenAccess() {
        let all: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemUpdate(all as CFDictionary, [kSecAttrAccessible as String: accessibility] as CFDictionary)
    }
    #endif
}
