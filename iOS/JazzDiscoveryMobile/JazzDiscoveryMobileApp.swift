import SwiftUI

@main
struct JazzDiscoveryMobileApp: App {
    @State private var library: JazzLibrary
    @State private var router = PhoneRouter()
    @State private var player: PlayerController
    @State private var passport: Passport
    @State private var sync: PassportSync?

    // The objects are made here and handed to @State as they are: @State makes an Observable object lazily, so one
    // read from it in init would be a different object from the one the app ends up with.
    init() {
        let library = JazzLibrary.load()
        let player = PlayerController()
        /// `--demo-passport` (App Store screenshots) uses a made-up passport kept in memory only.
        let demo = CommandLine.arguments.contains("--demo-passport")
        let passport = Passport(fileURL: demo ? nil : Passport.defaultFile)
        player.onListen = { passport.listened($0) }
        if demo { passport.fillWithDemo(library: library) }
        _library = State(initialValue: library)
        _player = State(initialValue: player)
        _passport = State(initialValue: passport)
        _sync = State(initialValue: demo ? nil : PassportSync(passport: passport))
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environment(library)
                .environment(router)
                .environment(player)
                .environment(passport)
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
            Tab("Discover", systemImage: "sparkles", value: PhoneTab.timeline) {
                TabStack(tab: .timeline) { TimelineTab() }
            }
            Tab("Explore", systemImage: "square.stack.3d.up.fill", value: PhoneTab.eras) {
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
        case .page(let page):
            switch page {
            case .era(let id): if let e = library.era(id) { EraDetailView(era: e) }
            case .artist(let id): if let a = library.artist(id) { ArtistDetailView(artist: a) }
            case .album(let id): if let a = library.album(id) { AlbumDetailView(album: a) }
            case .decade(let d): DecadeDetailView(decade: d)
            case .tune(let id): if let t = library.tune(id) { TuneDetailView(tune: t) }
            case .place(let id): if let p = library.place(id) { PlaceDetailView(place: p) }
            case .label(let id): if let l = library.label(id) { LabelDetailView(label: l) }
            case .lineage(let id): if let l = library.lineage(id) { LineageDetailView(lineage: l) }
            case .term(let id): if let t = library.term(id) { TermDetailView(term: t) }
            case .journey(let id): if let p = library.journey(id) { PathDetailView(path: p) }
            }
        case .decades: DecadesPage()
        case .connections(let focus): ConnectionsMapView(focus: focus)
        case .passport: PassportView()
        case .songbook: SongbookPage()
        case .places: PlacesPage()
        case .labels: LabelsPage()
        case .lineages: LineagesPage()
        case .paths: PathsPage()
        case .almanac(let m, let d): AlmanacPage(month: m, day: d)
        case .glossary: GlossaryPage()
        case .radio: RadioPage()
        case .blindfold: BlindfoldPage()
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
