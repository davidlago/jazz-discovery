import SwiftUI

// MARK: - Image loading

@MainActor
final class ImageStore {
    static let shared = ImageStore()
    private let cache = NSCache<NSURL, NSImage>()
    private var tasks: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> NSImage? {
        if let img = cache.object(forKey: url as NSURL) { return img }
        if let t = tasks[url] { return await t.value }
        let t = Task<NSImage?, Never> {
            guard let data = try? await HTTP.data(url) else { return nil }
            return NSImage(data: data)
        }
        tasks[url] = t
        let img = await t.value
        tasks[url] = nil
        if let img { cache.setObject(img, forKey: url as NSURL) }
        return img
    }
}

struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        // The image never drives layout: it fills whatever frame the caller gives it.
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: contentMode)
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
    func hoverLift(_ amount: CGFloat = 1.04) -> some View { modifier(HoverLift(amount: amount)) }
}

struct HoverLift: ViewModifier {
    let amount: CGFloat
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? amount : 1)
            .shadow(color: .black.opacity(hovering ? 0.5 : 0.25), radius: hovering ? 18 : 6, y: hovering ? 10 : 3)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Wikipedia-backed artist portrait

struct ArtistPortrait: View {
    let artist: Artist
    var tint: Color
    var duotone = true
    @State private var summary: WikiSummary?

    var body: some View {
        GeometryReader { geo in
            RemoteImage(url: summary?.image) {
                ZStack {
                    tint.opacity(0.35)
                    Text(artist.initials)
                        .font(Theme.display(geo.size.width * 0.38))
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
    @Environment(JazzLibrary.self) private var library
    @State private var catalog: CatalogAlbum?
    @State private var looked = false

    var body: some View {
        RemoteImage(url: catalog?.artwork(size)) {
            TypographicCover(title: album.title, artist: album.artistName, year: album.year,
                             tint: library.color(forEra: album.era), loading: !looked)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                        .font(Theme.display(w * 0.08, weight: .heavy)).foregroundStyle(tint)
                    Text(title.uppercased())
                        .font(Theme.display(w * 0.12)).foregroundStyle(Theme.cream)
                        .lineLimit(3).minimumScaleFactor(0.5)
                    Text(String(year)).font(Theme.label(w * 0.05)).foregroundStyle(Theme.muted)
                }
                .padding(w * 0.08)
                .opacity(loading ? 0.35 : 1)
            }
        }
    }
}

// MARK: - Small pieces

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var tint: Color = Theme.brass
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Rectangle().fill(tint).frame(width: 28, height: 4)
                Text(title.uppercased()).font(Theme.label(13)).tracking(2).foregroundStyle(Theme.cream)
            }
            if let subtitle {
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Theme.brass
    var filled = false
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(filled ? Theme.ink : tint)
            .background(Capsule().fill(filled ? tint : tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 1))
    }
}

struct EraChip: View {
    let era: Era
    @Environment(Router.self) private var router
    var body: some View {
        Button { router.go(.era(era.id)) } label: { Chip(text: era.name, tint: era.tint) }
            .buttonStyle(.plain)
    }
}

struct HRow<Content: View>: View {
    var spacing: CGFloat = 18
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) { content() }
                .padding(.horizontal, 40)
                .padding(.vertical, 12)
        }
        .scrollClipDisabled()
    }
}

// MARK: - Cards

struct ArtistCard: View {
    let artist: Artist
    var width: CGFloat = 170
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        Button { router.go(.artist(artist.id)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                ArtistPortrait(artist: artist, tint: library.color(forEra: artist.primaryEra))
                    .frame(width: width, height: width * 1.22)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .hoverLift()
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text("\(artist.instrument) · \(artist.lifespan)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct AlbumCard: View {
    let album: Album
    var width: CGFloat = 180
    var showArtist = true
    @Environment(Router.self) private var router
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        Button { router.go(.album(album.id)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                AlbumCover(album: album, size: 400)
                    .frame(width: width, height: width)
                    .hoverLift()
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                    if showArtist {
                        Text(album.artistName).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Text("\(String(album.year)) · \(album.label)").font(.system(size: 11)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Large hero banner with a duotone image and poster typography.
struct HeroBanner<Trailing: View>: View {
    let imageURL: URL?
    let tint: Color
    let kicker: String
    let title: String
    let subtitle: String
    var height: CGFloat = 360
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: imageURL) { tint.opacity(0.25) }
                .frame(maxWidth: .infinity).frame(height: height)
                .clipped()
                .duotone(tint, strength: 0.9)
            LinearGradient(colors: [.clear, Theme.ink.opacity(0.6), Theme.ink], startPoint: .top, endPoint: .bottom)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(kicker.uppercased()).font(Theme.label(12)).tracking(3).foregroundStyle(tint)
                    Text(title.uppercased())
                        .font(Theme.display(76)).foregroundStyle(Theme.cream)
                        .lineLimit(2).minimumScaleFactor(0.4)
                        .shadow(color: .black.opacity(0.4), radius: 12)
                    Text(subtitle).font(Theme.serif(20)).italic().foregroundStyle(Theme.cream.opacity(0.85))
                }
                Spacer(minLength: 20)
                trailing()
            }
            .padding(.horizontal, 40).padding(.bottom, 28)
        }
        .frame(height: height)
    }
}

extension HeroBanner where Trailing == EmptyView {
    init(imageURL: URL?, tint: Color, kicker: String, title: String, subtitle: String, height: CGFloat = 360) {
        self.init(imageURL: imageURL, tint: tint, kicker: kicker, title: title, subtitle: subtitle, height: height) { EmptyView() }
    }
}

struct Attribution: View {
    let text: String
    var url: URL? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            if let url { Link(text, destination: url) } else { Text(text) }
        }
        .font(.system(size: 11)).foregroundStyle(Theme.faint)
    }
}
