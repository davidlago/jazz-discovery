import SwiftUI

@main
struct JazzDiscoveryApp: App {
    @State private var library: JazzLibrary
    @State private var router = Router()
    @State private var player: PlayerController
    @State private var passport: Passport
    @State private var sync: PassportSync?
    @State private var widgets: WidgetPublisher?

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
            }
        }

        Settings {
            SettingsView()
                .environment(player)
                .preferredColorScheme(.dark)
        }
    }
}
