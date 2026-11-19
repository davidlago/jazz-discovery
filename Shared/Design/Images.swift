import SwiftUI

// Shared by the Mac and iPhone apps: remote images, duotone portraits and album covers.

// MARK: - Image loading

@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, PlatformImage>()
    private var tasks: [URL: Task<PlatformImage?, Never>] = [:]

    init() { cache.totalCostLimit = 160 << 20 }

    func cached(_ url: URL) -> PlatformImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> PlatformImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = tasks[url] { return await t.value }
        let t = Task<PlatformImage?, Never> {
            guard let data = try? await HTTP.data(url) else { return nil }
            return PlatformImage(data: data)
        }
        tasks[url] = t
        let img = await t.value
        tasks[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL, cost: Self.cost(img)) }
        return img
    }

    private static func cost(_ img: PlatformImage) -> Int {
        #if canImport(UIKit)
        Int(img.size.width * img.scale * img.size.height * img.scale * 4)
        #else
        Int(img.size.width * img.size.height * 4)
        #endif
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: PlatformImage?

    var body: some View {
        // The image never drives layout: it fills whatever frame the caller gives it.
        Color.clear
            .overlay {
                if let image {
                    Image(platformImage: image).resizable().aspectRatio(contentMode: contentMode)
                        .transition(AnyTransition.opacity)
                } else {
                    placeholder()
                }
            }
            .clipped()
        .task(id: url) {
            guard let url else { image = nil; return }
            if let c = ImageStore.shared.cached(url) { image = c; return }
            let img = await ImageStore.shared.load(url)
            withAnimation(.easeOut(duration: 0.35)) { image = img }
        }
    }
}

/// A Blue Note–style duotone: grayscale photo printed in one ink over a dark ground.
struct Duotone: ViewModifier {
    let tint: Color
    var strength: Double = 1
    func body(content: Content) -> some View {
        content
            .grayscale(1)
            .contrast(1.25)
            .overlay(Rectangle().fill(tint.opacity(0.85 * strength)).blendMode(.multiply))
            .overlay(Rectangle().fill(tint.opacity(0.18 * strength)).blendMode(.screen))
    }
}

extension View {
    func duotone(_ tint: Color, strength: Double = 1) -> some View { modifier(Duotone(tint: tint, strength: strength)) }
}

// MARK: - Wikipedia-backed artist portrait

struct ArtistPortrait: View {
    let artist: Artist
    var tint: Color
    var duotone = true
    /// The sharper rendition, for big heroes.
    var large = false
    @State private var summary: WikiSummary?

    var body: some View {
        GeometryReader { geo in
            RemoteImage(url: large ? (summary?.largeImage ?? summary?.image) : summary?.image) {
                ZStack {
                    tint.opacity(0.35)
                    Text(artist.initials)
                        .font(Theme.display(geo.size.width * 0.38, fixed: true))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .modifier(OptionalDuotone(enabled: duotone && summary?.image != nil, tint: tint))
        }
        .task(id: artist.wikipedia) { summary = await Wikipedia.shared.summary(artist.wikipedia) }
    }
}

private struct OptionalDuotone: ViewModifier {
    let enabled: Bool
    let tint: Color
    func body(content: Content) -> some View {
        if enabled { content.duotone(tint) } else { content }
    }
}

// MARK: - Album cover (Apple Music artwork, typographic fallback)

struct AlbumCover: View {
    let album: Album
    var size: Int = 600
    var cornerRadius: CGFloat = 4
    @Environment(JazzLibrary.self) private var library
    @State private var catalog: CatalogAlbum?
    @State private var looked = false

    var body: some View {
        RemoteImage(url: catalog?.artwork(size)) {
            TypographicCover(title: album.title, artist: album.artistName, year: album.year,
                             tint: library.color(forEra: album.era), loading: !looked)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: album.id) {
            catalog = await ITunes.shared.album(for: album)
            looked = true
        }
    }
}

struct TypographicCover: View {
    let title: String
    let artist: String
    let year: Int
    let tint: Color
    var loading = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                Theme.ink
                Rectangle().fill(tint).frame(width: w * 0.62, height: w * 0.18).offset(y: w * 0.12)
                VStack(alignment: .leading, spacing: w * 0.02) {
                    Spacer()
                    Text(artist.uppercased())
                        .font(Theme.display(w * 0.08, weight: .heavy, fixed: true)).foregroundStyle(tint)
                    Text(title.uppercased())
                        .font(Theme.display(w * 0.12, fixed: true)).foregroundStyle(Theme.cream)
                        .lineLimit(3).minimumScaleFactor(0.5)
                    Text(String(year)).font(Theme.label(w * 0.05, fixed: true)).foregroundStyle(Theme.muted)
                }
                .padding(w * 0.08)
                .opacity(loading ? 0.35 : 1)
            }
        }
    }
}
