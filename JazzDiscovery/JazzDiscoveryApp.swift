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
        WindowGroup("Jazz Discovery") {
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
            CommandGroup(after: .sidebar) {
                Button("Go Back") { router.back() }
                    .keyboardShortcut("[", modifiers: .command)
            }
            CommandMenu("Playback") {
                Button(player.isPlaying ? "Pause" : "Play") { player.togglePlayPause() }
                    .keyboardShortcut("p", modifiers: [.command, .option])
                    .disabled(player.current == nil)
                Button("Stop") { player.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(player.current == nil)
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
    }
}
