import SwiftUI

struct RootView: View {
    @Environment(Router.self) private var router
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @State private var query = ""

    var body: some View {
        @Bindable var router = router
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 280)
        } detail: {
            NavigationStack(path: $router.path) {
                Group {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        SearchResultsView(query: query)
                    } else {
                        switch router.section {
                        case .timeline: HomeView()
                        case .eras: EraIndexView()
                        case .decades: DecadesView()
                        case .artists: ArtistsView()
                        case .albums: CrateView()
                        case .connections: ConnectionsView()
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
        .searchable(text: $query, placement: .sidebar, prompt: "Artists, albums, eras")
        .onChange(of: router.path) { if !router.path.isEmpty, !query.isEmpty { query = "" } }
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
                    ForEach(AppSection.allCases) { s in
                        Label(s.rawValue, systemImage: s.symbol).tag(s)
                    }
                }
                Section("Eras") {
                    ForEach(library.eras) { era in
                        Button {
                            router.show(.eras)
                            router.go(.era(era.id))
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
            }
            .padding(.bottom, 40)
        }
        .background(Theme.ink)
    }
}

struct SettingsView: View {
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
            Section("Sources") {
                Text("Text and images: Wikipedia & Wikimedia Commons (CC BY-SA). Catalog, artwork and previews: Apple Music / iTunes. Video: YouTube.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
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
