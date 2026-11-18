import Foundation

/// Keeps the passport in step across your devices through iCloud key-value storage: one key holding the passport's
/// JSON, compressed. Each side merges what the other wrote (field by field, the later change winning), so it doesn't
/// matter which writes first.
///
/// It needs the `com.apple.developer.ubiquity-kvstore-identifier` entitlement. Without it (a build made before iCloud
/// was turned on for the App ID, or a test build) the store won't synchronize and this stays idle.
@MainActor
final class PassportSync {
    static let key = "passport.v1"
    private let store = NSUbiquitousKeyValueStore.default
    private let passport: Passport
    private var observer: Any?
    private var pending: Task<Void, Never>?

    init(passport: Passport) {
        self.passport = passport
        // False when the app isn't entitled to the store.
        guard store.synchronize() else { return }
        passport.syncsWithICloud = FileManager.default.ubiquityIdentityToken != nil
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.pull() }
            }
        pull()
        passport.onChange { [weak self] in self?.schedulePush() }
        push()
    }

    /// Merges in what's in iCloud.
    func pull() {
        guard let d = store.data(forKey: Self.key),
              let raw = try? (d as NSData).decompressed(using: .lzfse) as Data,
              let other = Passport.decode(raw) else { return }
        passport.merge(other)
    }

    /// Changes come in bursts (a record marked heard, then saved): send them a moment later, together.
    private func schedulePush() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    private func push() {
        guard let raw = passport.encoded(), let d = try? (raw as NSData).compressed(using: .lzfse) as Data else { return }
        if store.data(forKey: Self.key) != d { store.set(d, forKey: Self.key) }
    }
}
