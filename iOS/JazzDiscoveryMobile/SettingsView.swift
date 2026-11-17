import SwiftUI
import AuthenticationServices

struct SettingsView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AppleMusicSection()

                Section {
                    NavigationLink {
                        LastFMSettingsView(scrobbler: player.scrobbler)
                    } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(systemName: "dot.radiowaves.left.and.right", color: Theme.lastfmRed)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Last.fm")
                                Text(lastfmStatus).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } footer: {
                    Text("Scrobble the full tracks you play with Apple Music to your Last.fm profile.")
                }

                Section("About") {
                    LabeledContent("Version", value: Self.version)
                    Link(destination: URL(string: "https://github.com/davidlago/jazz-discovery")!) {
                        Label("Jazz Discovery for Mac", systemImage: "desktopcomputer")
                    }
                    Link(destination: URL(string: "https://github.com/davidlago/jazz-discovery/blob/main/docs/privacy.md")!) {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    Link(destination: URL(string: "https://github.com/davidlago/jazz-discovery/issues")!) {
                        Label("Support", systemImage: "questionmark.circle")
                    }
                }
                .tint(Theme.cream)

                Section {
                    Text("Text and pictures: Wikipedia and Wikimedia Commons (CC BY-SA). Catalog, artwork and previews: Apple Music. Videos: YouTube. Eras, artists and records are an original guide written for the app.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: {
                    Text("Sources")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                }
            }
        }
        .tint(Theme.brass)
        .presentationBackground(Theme.ink)
    }

    private var lastfmStatus: String {
        switch player.scrobbler.status {
        case .notConfigured: return "Not set up"
        case .disconnected: return "Not connected"
        case .authorizing: return "Connecting…"
        case .connected(let u): return player.scrobbler.scrobblingEnabled ? "Scrobbling as \(u)" : "Connected as \(u), paused"
        case .needsReauthorization(let u): return "\(u): connection expired"
        }
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var body: some View {
        Image(systemName: systemName)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color))
            .accessibilityHidden(true)
    }
}

struct AppleMusicSection: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        @Bindable var player = player
        Section {
            HStack(spacing: 12) {
                SettingsIcon(systemName: "applelogo", color: Theme.appleMusicRed)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Music")
                    HStack(spacing: 6) {
                        Circle().fill(player.appleMusic.isReady ? Color.green : Color.orange).frame(width: 7, height: 7)
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if player.appleMusic == .checking { ProgressView() }
            }
            .accessibilityElement(children: .combine)

            if case .unavailable(let why) = player.appleMusic {
                Text(why).font(.footnote).foregroundStyle(.secondary)
            }
            if player.appleMusic == .noSubscription {
                Text("Your Apple Account doesn't have an Apple Music subscription, so songs play as 30-second previews.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            switch player.appleMusic {
            case .denied:
                Button("Allow Access in Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { Platform.open(url) }
                }
            case .ready:
                Toggle("Play Full Tracks", isOn: $player.preferFullTracks)
                Button("Check Again") { Task { await player.connectAppleMusic() } }
            case .checking:
                EmptyView()
            default:
                Button("Connect Apple Music") { Task { await player.connectAppleMusic() } }
                    .fontWeight(.semibold)
            }
        } header: {
            Text("Listening")
        } footer: {
            Text("With an Apple Music subscription, songs and albums play in full. Without one, you hear 30-second previews, and every song and album opens in the Music app.")
        }
    }

    private var status: String {
        switch player.appleMusic {
        case .ready: return player.preferFullTracks ? "Connected · full tracks" : "Connected · previews by choice"
        case .checking: return "Checking…"
        case .unknown: return "Not connected · previews"
        case .denied: return "Access denied · previews"
        case .noSubscription: return "No subscription · previews"
        case .unavailable: return "Unavailable · previews"
        }
    }
}

// MARK: - Last.fm

struct LastFMSettingsView: View {
    @Bindable var scrobbler: Scrobbler
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var showOwnAccount = false
    @State private var pasteNote: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsIcon(systemName: "dot.radiowaves.left.and.right", color: Theme.lastfmRed)
                    Text("Scrobbling sends the songs you play to your Last.fm profile. A song counts once you've listened to half of it or 4 minutes, whichever comes first (songs under 30 seconds don't count). Only full tracks played with Apple Music are scrobbled, not previews.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                accountRows
                if let error = scrobbler.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange)
                }
            } header: {
                Text("Account")
            }

            if scrobbler.usesBuiltInAPI && !showOwnAccount && scrobbler.ownAPI == nil {
                Section {
                    Button("Use My Own API Account") { withAnimation { showOwnAccount = true } }
                        .font(.footnote)
                } footer: {
                    Text("Optional. Jazz Discovery has its own Last.fm API account, so you only need to sign in.")
                }
            } else {
                apiAccountSection
            }

            Section("Scrobbling") {
                Toggle("Scrobble Songs I Play", isOn: $scrobbler.scrobblingEnabled)
                Toggle("Show What's Playing on My Profile", isOn: $scrobbler.sendsNowPlaying)
                    .disabled(!scrobbler.scrobblingEnabled)
                HStack {
                    Text("Waiting to Send")
                    Spacer()
                    if scrobbler.isSending { ProgressView().padding(.trailing, 6) }
                    Text(scrobbler.pendingCount == 0 ? "Nothing" : "\(scrobbler.pendingCount)")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                if scrobbler.pendingCount > 0 {
                    Button("Send Now") { scrobbler.flush() }
                        .disabled(scrobbler.isSending || !scrobbler.isActive)
                }
            }

            if !scrobbler.recent.isEmpty {
                Section("Recently Scrobbled") {
                    ForEach(scrobbler.recent) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(s.title).lineLimit(1)
                                Spacer()
                                Text(s.startedAt, style: .relative).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Text(s.artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ink)
        .navigationTitle("Last.fm")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.default, value: scrobbler.status)
    }

    @ViewBuilder
    private var accountRows: some View {
        switch scrobbler.status {
        case .notConfigured:
            Text("Enter your Last.fm API key and shared secret below to connect.")
                .foregroundStyle(.secondary)
        case .disconnected:
            Button { connect() } label: {
                Label("Connect Last.fm…", systemImage: "person.crop.circle.badge.plus").fontWeight(.semibold)
            }
        case .authorizing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Allow access on last.fm…").foregroundStyle(.secondary)
            }
            Button("Open the Page Again") { scrobbler.reopenAuthorizationPage() }
            Button("Cancel", role: .cancel) { scrobbler.cancelAuthorization() }
        case .connected(let user):
            Label("Connected as \(user)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            if let url = scrobbler.profileURL {
                Link(destination: url) { Label("Open My Profile", systemImage: "arrow.up.forward") }
            }
            Button("Disconnect", role: .destructive) { scrobbler.disconnect() }
        case .needsReauthorization(let user):
            Label("\(user): the connection expired", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Button("Reconnect…") { connect() }.fontWeight(.semibold)
            Button("Disconnect", role: .destructive) { scrobbler.disconnect() }
        }
    }

    private var apiAccountSection: some View {
        Section {
            TextField("API Key", text: $scrobbler.apiKey)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("Shared Secret", text: $scrobbler.sharedSecret)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button { pasteCredentials() } label: { Label("Paste Key and Secret", systemImage: "doc.on.clipboard") }
            if let pasteNote { Text(pasteNote).font(.footnote).foregroundStyle(.secondary) }
            Link(destination: URL(string: "https://www.last.fm/api/account/create")!) {
                Label("Create a Free API Account", systemImage: "arrow.up.forward")
            }
        } header: {
            Text("API Account")
        } footer: {
            Text("Last.fm needs an API key and shared secret for each app; the callback URL can stay empty. Both are stored in your keychain on this iPhone.")
        }
    }

    /// Sign in in a sheet over the app; Last.fm sends it back here once access is allowed.
    private func connect() {
        let webAuth = webAuth
        scrobbler.connect { url in
            try? await webAuth.authenticate(using: url, callbackURLScheme: "jazzdiscovery")
        }
    }

    /// Last.fm's API account page shows the key and secret as two 32-character hex strings; take them both at once.
    private func pasteCredentials() {
        let text = UIPasteboard.general.string ?? ""
        let hex = text.matches(of: /\b[0-9a-fA-F]{32}\b/).map { String($0.output) }
        switch hex.count {
        case 0: pasteNote = "The clipboard doesn't have a Last.fm key in it."
        case 1:
            if scrobbler.apiKey.isEmpty { scrobbler.apiKey = hex[0]; pasteNote = "Pasted the API key. Now copy the shared secret and paste again." }
            else { scrobbler.sharedSecret = hex[0]; pasteNote = "Pasted the shared secret." }
        default:
            scrobbler.apiKey = hex[0]; scrobbler.sharedSecret = hex[1]
            pasteNote = "Pasted the API key and shared secret."
        }
    }
}
