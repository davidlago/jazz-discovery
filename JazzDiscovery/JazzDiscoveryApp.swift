import SwiftUI

@main
struct JazzDiscoveryApp: App {
    @State private var library: JazzLibrary
    @State private var router = Router()
    @State private var player: PlayerController
    @State private var passport: Passport
    @State private var sync: PassportSync?
    @State private var widgets: WidgetPublisher?
    @Environment(\.scenePhase) private var scenePhase

    // The objects are made here and handed to @State as they are: @State makes an Observable object lazily, so one
    // read from it in init would be a different object from the one the app ends up with.
    init() {
        let library = JazzLibrary.load()
        let player = PlayerController()
        let snapshots = Snapshots.outputDir
        // Snapshots use a made-up passport kept in memory, so they never touch the real one.
        let passport = Passport(fileURL: snapshots == nil ? Passport.defaultFile : nil)
        player.onListen = { passport.listened($0) }
        _library = State(initialValue: library)
        _player = State(initialValue: player)
        _passport = State(initialValue: passport)
        _sync = State(initialValue: snapshots == nil ? PassportSync(passport: passport) : nil)
        _widgets = State(initialValue: snapshots == nil ? WidgetPublisher(passport: passport, library: library) : nil)
        AppContext.shared.library = library
        AppContext.shared.passport = passport
        AppContext.shared.player = player
        MorningNote.shared.start(library: library)
        if GuideEditorModel.isEnabled { GuideEditorModel.applySaved(to: library) }
        if SelfTest.requested {
            Task { @MainActor in await SelfTest.run(library) }
        }
        if let dir = snapshots {
            Task { @MainActor in await Snapshots.run(library: library, player: player, passport: passport, to: dir) }
        }
    }

    var body: some Scene {
        WindowGroup("Jazz Discovery", id: MenuBarPlayer.mainWindowID) {
            RootView()
                .environment(library)
                .environment(router)
                .environment(player)
                .environment(passport)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 720)
                // jazzdiscovery:// links go to the open window instead of opening another one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                // New content from GitHub, for the next launch (Shared/Services/Content.swift).
                .onChange(of: scenePhase, initial: true) { _, phase in if phase == .active { ContentUpdater.check() } }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandMenu("Go") {
                Button("Back") { router.back() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(router.path.isEmpty)
                Button("Search") { router.searchRequest += 1 }
                    .keyboardShortcut("f", modifiers: .command)
                Divider()
                ForEach(Array(AppSection.shortcuts.enumerated()), id: \.element) { i, section in
                    Button(section.rawValue) { router.query = ""; router.show(section) }
                        .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: .command)
                }
                Divider()
                ForEach(AppSection.allCases.filter { !AppSection.shortcuts.contains($0) }) { section in
                    Button(section.rawValue) { router.query = ""; router.show(section) }
                }
            }
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(player.current == nil)
                Button("Next Track") { player.next() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(player.current == nil)
                Button("Previous Track") { player.previous() }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(player.current == nil)
                Button("Stop") { player.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(player.current == nil)
                Divider()
                Button("Go to Current Record") { if let id = playingRecord { router.query = ""; router.go(.album(id)) } }
                    .keyboardShortcut("l", modifiers: .command)
                    .disabled(playingRecord == nil)
                if GuideEditorModel.isEnabled {
                    Divider()
                    GuideEditorMenuItem()
                }
            }
        }

        // Timing the listening guides; only with `-guideEditor YES` (scripts/guide-editor.sh).
        Window("Guide Editor", id: GuideEditorView.windowID) {
            GuideEditorView()
                .environment(library)
                .environment(player)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1100, height: 760)

        Settings {
            SettingsView()
                .environment(player)
                .preferredColorScheme(.dark)
        }

        // The player in the menu bar, while something is playing (Settings ▸ Apple Music turns it off).
        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarPlayer()
                .environment(library)
                .environment(router)
                .environment(player)
                .environment(passport)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: player.isPlaying ? "waveform" : "music.note")
                .accessibilityLabel("Jazz Discovery player")
        }
        .menuBarExtraStyle(.window)
    }

    @AppStorage(MenuBarPlayer.settingKey) private var showsMenuBarPlayer = true

    /// In the menu bar while there's music and the setting is on. Taking it out of the menu bar (⌘-drag) turns the
    /// setting off.
    private var menuBarInserted: Binding<Bool> {
        Binding(get: { showsMenuBarPlayer && player.current != nil },
                set: { inserted in if !inserted && player.current != nil { showsMenuBarPlayer = false } })
    }

    /// The Crate record playing now, if it's one.
    private var playingRecord: String? {
        player.currentCollectionId.flatMap { passport.albumID(forCollection: $0) }.flatMap { library.album($0)?.id }
    }
}
