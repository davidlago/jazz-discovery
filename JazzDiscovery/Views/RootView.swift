import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            NavigationStack(path: $router.path) {
                Group {
                    if !router.query.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchResultsView(query: router.query)
                    } else {
                        switch router.section {
                        case .timeline: HomeView()
                        case .eras: EraIndexView()
                        case .decades: DecadesView()
                        case .artists: ArtistsView()
                        case .albums: CrateView()
                        case .connections: ConnectionsView()
                        case .passport: PassportView()
                        case .radio: RadioView()
                        case .blindfold: BlindfoldPage()
                        }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .era(let id): if let e = library.era(id) { EraDetailView(era: e) }
                    case .artist(let id): if let a = library.artist(id) { ArtistDetailView(artist: a) }
                    case .album(let id): if let a = library.album(id) { AlbumDetailView(album: a) }
                    case .decade(let d): DecadeDetailView(decade: d)
                    }
                }
                .background(Theme.ink)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { NowPlayingBar() }
            .animation(.spring(response: 0.35), value: player.current)
        }
        .searchable(text: $router.query, placement: .sidebar, prompt: "Artists, albums, eras")
        .onChange(of: router.path) { if !router.path.isEmpty, !router.query.isEmpty { router.query = "" } }
        .onOpenURL { url in
            guard let link = DeepLink(url, library: library) else { return }
            if link == .settings { openSettings() } else { router.open(link) }
        }
        .overlay(alignment: .top) { ErrorToast() }
    }
}

struct Sidebar: View {
    @Environment(Router.self) private var router
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let selection = Binding<AppSection?>(get: { router.section }, set: { if let s = $0 { router.show(s) } })
        VStack(spacing: 0) {
            List(selection: selection) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("JAZZ").font(Theme.display(40)).foregroundStyle(Theme.cream)
                    Text("DISCOVERY").font(Theme.label(10)).tracking(5).foregroundStyle(Theme.brass)
                }
                .padding(.vertical, 8)
                .selectionDisabled()

                Section("Explore") {
                    ForEach(AppSection.explore) { s in
                        Label(s.rawValue, systemImage: s.symbol).tag(s)
                    }
                }
                Section("Listen") {
                    ForEach(AppSection.listen) { s in
                        Label(s.rawValue, systemImage: s.symbol).tag(s)
                    }
                }
                Section("You") {
                    Label(AppSection.passport.rawValue, systemImage: AppSection.passport.symbol).tag(AppSection.passport)
                }
                Section("Eras") {
                    ForEach(library.eras) { era in
                        Button {
                            router.show(.era(era.id))
                        } label: {
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2).fill(era.tint).frame(width: 10, height: 10)
                                Text(era.name).lineLimit(1)
                                Spacer()
                                Text(String(era.start)).font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .selectionDisabled()
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Button { openSettings() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "applelogo")
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Apple Music").font(.system(size: 12, weight: .semibold))
                        Text(statusText).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Circle().fill(player.appleMusic.isReady ? Color.green : Color.orange).frame(width: 7, height: 7)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Theme.panel)
    }

    private var statusText: String {
        switch player.appleMusic {
        case .ready: return player.preferFullTracks ? "Full tracks" : "Previews (by choice)"
        case .checking: return "Checking…"
        case .unknown: return "Previews · click to connect"
        case .denied: return "Access denied · previews"
        case .noSubscription: return "No subscription · previews"
        case .unavailable: return "Not enabled · previews"
        }
    }
}

struct ErrorToast: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        if let msg = player.lastError {
            Text(msg)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(Theme.panelHi))
                .overlay(Capsule().strokeBorder(Theme.brass.opacity(0.4)))
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { player.lastError = nil }
                }
        }
    }
}

struct SearchResultsView: View {
    let query: String
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let r = library.search(query)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Results for “\(query)”").font(Theme.display(40)).foregroundStyle(Theme.cream)
                    .padding(.horizontal, 40).padding(.top, 30)
                if r.isEmpty {
                    Text("Nothing in the guide matches that yet.").foregroundStyle(Theme.muted).padding(.horizontal, 40)
                }
                if !r.eras.isEmpty {
                    SectionHeader(title: "Eras").padding(.horizontal, 40)
                    HRow { ForEach(r.eras) { EraPosterCard(era: $0, width: 300, height: 200) } }
                }
                if !r.artists.isEmpty {
                    SectionHeader(title: "Artists").padding(.horizontal, 40)
                    HRow { ForEach(r.artists) { ArtistCard(artist: $0) } }
                }
                if !r.albums.isEmpty {
                    SectionHeader(title: "Albums").padding(.horizontal, 40)
                    HRow { ForEach(r.albums) { AlbumCard(album: $0) } }
                }
                if !r.players.isEmpty {
                    SectionHeader(title: "On the Records", subtitle: "Players credited on the albums who don't have a page yet.")
                        .padding(.horizontal, 40)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(r.players) { p in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 8) {
                                    Text(p.name.uppercased()).font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.cream)
                                    Text(p.instruments.joined(separator: ", ")).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                FlowLayout(spacing: 6) {
                                    ForEach(p.albums) { a in
                                        Button { router.go(.album(a.id)) } label: {
                                            Chip(text: "\(a.title) (\(String(a.year)))", tint: library.color(forEra: a.era))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Theme.ink)
    }
}

struct SettingsView: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        TabView {
            AppleMusicSettings().tabItem { Label("Apple Music", systemImage: "applelogo") }
            LastFMSettings(scrobbler: player.scrobbler).tabItem { Label("Last.fm", systemImage: "dot.radiowaves.left.and.right") }
        }
        .frame(width: 560)
    }
}

struct AppleMusicSettings: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        @Bindable var player = player
        Form {
            Section("Apple Music") {
                LabeledContent("Status") { Text(status).foregroundStyle(.secondary) }
                if case .unavailable(let why) = player.appleMusic {
                    Text(why).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Play full tracks with Apple Music when available", isOn: $player.preferFullTracks)
                HStack {
                    Button(player.appleMusic.isReady ? "Re-check" : "Connect Apple Music") {
                        Task { await player.connectAppleMusic() }
                    }
                    if player.appleMusic == .denied {
                        Button("Open Privacy Settings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")!)
                        }
                    }
                }
                Text("Without Apple Music access, the app plays 30-second previews and opens the full track or album in the Music app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sound Quality") {
                Toggle("Switch the output to 44.1 kHz while playing", isOn: $player.matchOutputRate)
                if let output = player.output { LabeledContent("Output") { Text(output.summary).foregroundStyle(.secondary) } }
                Text("Apple Music gives apps on the Mac its AAC stream: 256 kbps at 44.1 kHz, even for songs in Lossless or Hi-Res Lossless (those play only in the Music app, where *Open in Music* takes you). With this on, a USB DAC or other output runs at 44.1 kHz while Jazz Discovery plays, instead of the Mac resampling to the device's rate, and goes back to its own rate when you stop or quit. Like Audio MIDI Setup, the change applies to every app using the device. AirPlay and Bluetooth keep their own rate.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Section("Sources") {
                Text("Text and images: Wikipedia & Wikimedia Commons (CC BY-SA). Catalog, artwork and previews: Apple Music / iTunes. Video: YouTube.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 10)
    }

    private var status: String {
        switch player.appleMusic {
        case .ready: return "Connected"
        case .checking: return "Checking…"
        case .unknown: return "Not connected"
        case .denied: return "Access denied"
        case .noSubscription: return "No active subscription"
        case .unavailable: return "Unavailable"
        }
    }
}

struct LastFMSettings: View {
    @Bindable var scrobbler: Scrobbler

    var body: some View {
        Form {
            Section {
                Text("Scrobbling sends the songs you play to your Last.fm profile. A song counts once you've listened to half of it or 4 minutes, whichever comes first (songs under 30 seconds don't count). Only full tracks played with Apple Music are scrobbled, not previews.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                TextField(text: $scrobbler.apiKey) { Text("API key").font(.body) }
                    .font(.system(.body, design: .monospaced))
                SecureField("Shared secret", text: $scrobbler.sharedSecret)
                Link("Create a free API account at last.fm (the callback URL can stay empty)",
                     destination: URL(string: "https://www.last.fm/api/account/create")!)
                    .font(.caption)
            } header: {
                Text("API account")
            } footer: {
                Text("Last.fm needs an API key and shared secret for each app. Both are stored in your keychain on this Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Account") {
                accountRow
                if let error = scrobbler.lastError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Scrobbling") {
                Toggle("Scrobble songs I play", isOn: $scrobbler.scrobblingEnabled)
                Toggle("Show what's playing now on my profile", isOn: $scrobbler.sendsNowPlaying)
                    .disabled(!scrobbler.scrobblingEnabled)
                LabeledContent("Waiting to send") {
                    HStack {
                        Text(scrobbler.pendingCount == 0 ? "Nothing" : "\(scrobbler.pendingCount) scrobble\(scrobbler.pendingCount == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                        if scrobbler.isSending { ProgressView().controlSize(.small) }
                        if scrobbler.pendingCount > 0 {
                            Button("Send Now") { scrobbler.flush() }.disabled(scrobbler.isSending || !scrobbler.isActive)
                        }
                    }
                }
            }
            if !scrobbler.recent.isEmpty {
                Section("Recently scrobbled") {
                    ForEach(scrobbler.recent) { s in
                        HStack {
                            Text(s.title).lineLimit(1)
                            Text(s.artist).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text(s.startedAt, style: .relative)
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(height: 560)
    }

    @ViewBuilder
    private var accountRow: some View {
        switch scrobbler.status {
        case .notConfigured:
            LabeledContent("Status") { Text("Enter your API key and secret first").foregroundStyle(.secondary) }
        case .disconnected:
            LabeledContent("Status") {
                HStack {
                    Text("Not connected").foregroundStyle(.secondary)
                    Button("Connect…") { scrobbler.connect() }
                }
            }
        case .authorizing:
            LabeledContent("Status") {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Allow access in your browser…").foregroundStyle(.secondary)
                    Button("Open Page Again") { scrobbler.reopenAuthorizationPage() }
                    Button("Cancel") { scrobbler.cancelAuthorization() }
                }
            }
        case .connected(let user):
            LabeledContent("Status") {
                HStack {
                    Label("Connected as \(user)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    if let url = scrobbler.profileURL { Link("Profile", destination: url) }
                    Button("Disconnect") { scrobbler.disconnect() }
                }
            }
        case .needsReauthorization(let user):
            LabeledContent("Status") {
                HStack {
                    Label("\(user): connection expired", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                    Button("Reconnect…") { scrobbler.connect() }
                    Button("Disconnect") { scrobbler.disconnect() }
                }
            }
        }
    }
}
