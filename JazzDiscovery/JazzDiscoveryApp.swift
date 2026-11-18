import SwiftUI

@main
struct JazzDiscoveryApp: App {
    @State private var library = JazzLibrary.load()
    @State private var router = Router()
    @State private var player = PlayerController()

    init() {
        if SelfTest.requested {
            let lib = library
            Task { @MainActor in await SelfTest.run(lib) }
        }
        if let dir = Snapshots.outputDir {
            let lib = library, p = player
            Task { @MainActor in await Snapshots.run(library: lib, player: p, to: dir) }
        }
    }

    var body: some Scene {
        WindowGroup("Jazz Discovery") {
            RootView()
                .environment(library)
                .environment(router)
                .environment(player)
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
