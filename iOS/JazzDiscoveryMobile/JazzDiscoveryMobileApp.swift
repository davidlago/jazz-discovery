import SwiftUI

@main
struct JazzDiscoveryMobileApp: App {
    @State private var library = JazzLibrary.load()
    @State private var router = PhoneRouter()
    @State private var player = PlayerController()

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(library)
                .environment(router)
                .environment(player)
                .preferredColorScheme(.dark)
                .onOpenURL { router.handle($0, library: library, player: player) }
                .task { await openLaunchLinks() }
        }
    }

    /// `--open <url>` (repeatable) opens deep links at launch, a few seconds apart, for scripted screenshots
    /// (scripts/app-store-screenshots.sh) without the system asking to open each link.
    @MainActor
    private func openLaunchLinks() async {
        let args = CommandLine.arguments
        let urls = args.indices.dropLast().filter { args[$0] == "--open" }.compactMap { URL(string: args[$0 + 1]) }
        for (i, url) in urls.enumerated() {
            if i > 0 { try? await Task.sleep(for: .seconds(3)) }
            router.handle(url, library: library, player: player, fromLaunchArguments: true)
        }
    }
}

struct PhoneRootView: View {
    @Environment(PhoneRouter.self) private var router
    @Environment(PlayerController.self) private var player

    var body: some View {
        @Bindable var router = router
        TabView(selection: router.tabSelection) {
            Tab("Timeline", systemImage: "timeline.selection", value: PhoneTab.timeline) {
                TabStack(tab: .timeline) { TimelineTab() }
            }
            Tab("Eras", systemImage: "square.stack.3d.up.fill", value: PhoneTab.eras) {
                TabStack(tab: .eras) { ErasTab() }
            }
            Tab("Artists", systemImage: "person.2.fill", value: PhoneTab.artists) {
                TabStack(tab: .artists) { ArtistsTab() }
            }
            Tab("Crate", systemImage: "square.grid.3x3.fill", value: PhoneTab.crate) {
                TabStack(tab: .crate) { CrateTab() }
            }
            Tab(value: PhoneTab.search, role: .search) {
                TabStack(tab: .search) { SearchTab() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: player.current != nil) { MiniPlayer() }
        .sheet(isPresented: $router.showNowPlaying) { NowPlayingView() }
        .sheet(isPresented: $router.showSettings) { SettingsView() }
        .overlay(alignment: .top) { ErrorToast() }
        .animation(.spring(response: 0.35), value: player.lastError)
        .tint(Theme.brass)
    }
}

/// A tab's navigation stack, with every page the app can push.
struct TabStack<Root: View>: View {
    let tab: PhoneTab
    @ViewBuilder var root: () -> Root
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        NavigationStack(path: router.path(tab)) {
            root()
                .navigationDestination(for: PhoneRoute.self) { RouteView(route: $0) }
        }
    }
}

struct RouteView: View {
    let route: PhoneRoute
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        switch route {
        case .era(let id): if let e = library.era(id) { EraDetailView(era: e) }
        case .artist(let id): if let a = library.artist(id) { ArtistDetailView(artist: a) }
        case .album(let id): if let a = library.album(id) { AlbumDetailView(album: a) }
        case .decade(let d): DecadeDetailView(decade: d)
        case .decades: DecadesPage()
        case .connections(let focus): ConnectionsMapView(focus: focus)
        }
    }
}

struct ErrorToast: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let msg = player.lastError {
            Label(msg, systemImage: "exclamationmark.circle")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.cream)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { player.lastError = nil }
                .task(id: msg) {
                    try? await Task.sleep(for: .seconds(4))
                    player.lastError = nil
                }
        }
    }
}
