import SwiftUI

/// `Jazz Discovery --snapshots <dir>`: renders each section in an offscreen window and
/// saves PNGs (for design review without driving the UI).
enum Snapshots {
    static var outputDir: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    @MainActor
    static func run(library: JazzLibrary, player: PlayerController, to dir: String) async {
        let router = Router()
        let root = RootView().environment(library).environment(router).environment(player)
            .preferredColorScheme(.dark)
        let host = NSHostingView(rootView: root)
        let size = NSSize(width: 1440, height: 900)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        window.orderBack(nil)

        let artist = library.artist("miles-davis") ?? library.artists[0]
        let album = library.album("kind-of-blue") ?? library.albums[0]
        let shots: [(String, () -> Void)] = [
            ("01-timeline", { router.show(.timeline) }),
            ("02-eras", { router.show(.eras) }),
            ("03-era-detail", { router.show(.eras); router.go(.era("bebop")) }),
            ("04-decades", { router.show(.decades) }),
            ("05-decade-detail", { router.show(.decades); router.go(.decade(1950)) }),
            ("06-artists", { router.show(.artists) }),
            ("07-artist-detail", { router.show(.artists); router.go(.artist(artist.id)) }),
            ("08-crate", { router.show(.albums) }),
            ("09-album-detail", { router.show(.albums); router.go(.album(album.id)) }),
            ("10-connections", { router.show(.connections) }),
        ]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, setup) in shots {
            setup()
            try? await Task.sleep(for: .seconds(9))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("saved \(name)"); fflush(stdout)
        }
        exit(0)
    }
}
