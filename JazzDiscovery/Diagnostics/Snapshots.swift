import SwiftUI
import WidgetKit

/// `Jazz Discovery --snapshots <dir>`: renders each section in an offscreen window and
/// saves PNGs (for design review without driving the UI).
enum Snapshots {
    static var outputDir: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--snapshots"), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    @MainActor
    static func run(library: JazzLibrary, player: PlayerController, passport: Passport, to dir: String) async {
        // `--widgets-only`: just the widgets, at their iPhone sizes.
        if CommandLine.arguments.contains("--widgets-only") {
            await widgets(library: library, passport: passport, to: dir)
            exit(0)
        }
        let router = Router()
        let root = RootView().environment(library).environment(router).environment(player).environment(passport)
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
            ("03-era-detail", { router.show(.era("bebop")) }),
            ("04-decades", { router.show(.decades) }),
            ("05-decade-detail", { router.show(.decade(1950)) }),
            ("06-artists", { router.show(.artists) }),
            ("07-artist-detail", { router.show(.artist(artist.id)) }),
            ("08-crate", { router.show(.albums) }),
            ("09-album-detail", { router.show(.album(album.id)) }),
            ("10-connections", { router.show(.connections) }),
            ("11-passport", { router.show(.passport) }),
            ("12-radio", { router.show(.radio) }),
            ("13-blindfold", { router.show(.blindfold) }),
            ("14-songbook", { router.show(.songbook) }),
            ("15-tune", { router.show(.tune("body-and-soul")) }),
            ("16-places", { router.show(.places) }),
            ("17-place", { router.show(.place("village-vanguard")) }),
            ("18-label", { router.show(.label("blue-note")) }),
            ("19-lineage", { router.show(.lineage("saxophone")) }),
            ("20-glossary", { router.show(.glossary) }),
            ("21-term", { router.show(.term("rhythm-changes")) }),
            ("22-path", { router.show(.journey("nineteen-fifty-nine")) }),
            ("23-paths", { router.show(.paths) }),
            ("24-guides", { router.show(.guides) }),
            // A guide with its recording playing (a preview here: snapshots have no Apple Music), and the player.
            ("25-guide", {
                router.show(.guide("so-what"))
                if let t = library.tracks["Miles Davis|So What"] { player.play(t.track) }
            }),
            ("26-search", { router.show(.timeline); router.query = "blue" }),
        ]
        // `--only <prefix>`: just the shots whose names start with it ("25", "2").
        let only = CommandLine.arguments.firstIndex(of: "--only").flatMap { i in
            i + 1 < CommandLine.arguments.count ? CommandLine.arguments[i + 1] : nil
        }
        // A passport with something in it (in memory only: snapshots don't touch the real one).
        passport.fillWithDemo(library: library)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, setup) in shots where only.map(name.hasPrefix) ?? true {
            setup()
            try? await Task.sleep(for: .seconds(9))
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("saved \(name)"); fflush(stdout)
        }
        // Settings → Last.fm, in its own window like the real Settings window.
        let settings = NSHostingView(rootView: LastFMSettings(scrobbler: player.scrobbler).frame(width: 560)
            .preferredColorScheme(.dark))
        let sw = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 560, height: 560),
                          styleMask: [.titled], backing: .buffered, defer: false)
        sw.appearance = NSAppearance(named: .darkAqua)
        sw.contentView = settings
        sw.orderBack(nil)
        try? await Task.sleep(for: .seconds(1))
        settings.layoutSubtreeIfNeeded()
        if let rep = settings.bitmapImageRepForCachingDisplay(in: settings.bounds) {
            settings.cacheDisplay(in: settings.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/11-settings-lastfm.png"))
            print("saved 11-settings-lastfm"); fflush(stdout)
        }
        await widgets(library: library, passport: passport, to: dir)
        exit(0)
    }

    /// The widgets in every size, for a few days, with a demo passport for the Continue widget.
    @MainActor
    static func widgets(library: JazzLibrary, passport: Passport, to dir: String) async {
        passport.fillWithDemo(library: library)
        if let path = library.journey("nineteen-fifty-nine") {
            for stop in path.stops.prefix(2) { passport.setStop(stop.key, of: path.id, done: true) }
        }
        let snapshot = WidgetSnapshot(passport: passport, library: library)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(WidgetFamily, CGSize)] = [(.systemSmall, CGSize(width: 170, height: 170)),
                                               (.systemMedium, CGSize(width: 364, height: 170)),
                                               (.systemLarge, CGSize(width: 364, height: 382))]
        func save<V: View>(_ view: V, size: CGSize, padded: Bool = true, _ name: String) {
            let framed = view.padding(padded ? 16 : 0).frame(width: size.width, height: size.height)
                .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .padding(12).background(Color(white: 0.25)).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: framed)
            r.scale = 2
            guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return }
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            print("saved \(name)"); fflush(stdout)
        }
        // Today, a quiet day (it shows the nearest one), and a round anniversary.
        let days: [(String, DateComponents)] = [("today", Calendar.current.dateComponents([.year, .month, .day], from: .now)),
                                                ("miles-100", DateComponents(year: 2026, month: 5, day: 26)),
                                                ("jan-03", DateComponents(year: 2027, month: 1, day: 3))]
        for (label, comps) in days {
            guard let date = Calendar.current.date(from: comps), var content = library.todayWidget(on: date, snapshot: snapshot) else { continue }
            content.image = await WidgetImages.picture(for: content, library: library)
            for (family, size) in sizes {
                save(TodayWidgetView(content: content, familyOverride: family), size: size, "w-today-\(label)-\(family)")
            }
        }
        // The App Store screenshot of the widgets, at each size: a Home Screen page with Today in Jazz (large, on
        // Miles Davis's hundredth birthday) and, under it, Continue and a small Today.
        if let may26 = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 26, hour: 12)),
           var big = library.todayWidget(on: may26, snapshot: snapshot),
           let nov18 = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 12)),
           var small = library.todayWidget(on: nov18, snapshot: snapshot) {
            big.image = await WidgetImages.picture(for: big, library: library)
            small.image = await WidgetImages.picture(for: small, library: library)
            for (size, points, scale) in [("6.9", CGSize(width: 440, height: 956), 3.0), ("6.3", CGSize(width: 402, height: 874), 3.0)] {
                let widgetWidth = points.width - 48, smallSide = (widgetWidth - 22) / 2
                func tile<V: View>(_ v: V, _ w: CGFloat, _ h: CGFloat) -> some View {
                    v.padding(16).frame(width: w, height: h).background(Theme.ink)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                }
                let page = VStack(spacing: 30) {
                    Spacer(minLength: 0)
                    VStack(spacing: 10) {
                        Text("WIDGETS").font(Theme.label(13)).tracking(2.4).foregroundStyle(Theme.brass)
                        Text("Today in jazz,\non your Home Screen").font(Theme.display(40)).multilineTextAlignment(.center)
                            .foregroundStyle(Theme.cream)
                    }
                    tile(TodayWidgetView(content: big, familyOverride: .systemLarge), widgetWidth, widgetWidth * 382 / 364)
                    HStack(spacing: 22) {
                        tile(ContinueWidgetView(snapshot: snapshot, familyOverride: .systemSmall), smallSide, smallSide)
                        tile(TodayWidgetView(content: small, familyOverride: .systemSmall), smallSide, smallSide)
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: points.width, height: points.height)
                .background(LinearGradient(colors: [Color(hex: "#2B2340"), Color(hex: "#16121C"), Color(hex: "#0F0E0D")],
                                           startPoint: .top, endPoint: .bottom))
                .environment(\.colorScheme, .dark)
                let r = ImageRenderer(content: page)
                r.scale = scale
                if let cg = r.cgImage {
                    let rep = NSBitmapImageRep(cgImage: cg)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "\(dir)/appstore-widgets-\(size).png"))
                    print("saved appstore-widgets-\(size) (\(cg.width) × \(cg.height))"); fflush(stdout)
                }
            }
        }
        let states: [(String, WidgetSnapshot?)] = [
            ("path", snapshot),
            ("stamp", { var s = snapshot; s.path = nil; return s }()),
            ("empty", nil),
        ]
        for (label, s) in states {
            for (family, size) in sizes.prefix(2) {
                save(ContinueWidgetView(snapshot: s, familyOverride: family), size: size, "w-continue-\(label)-\(family)")
            }
        }
    }
}
