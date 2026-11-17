import SwiftUI

extension Theme {
    /// Side margin of every page on the phone.
    static let gutter: CGFloat = 20
    static let lastfmRed = Color(hex: "#D51007")
    static let appleMusicRed = Color(hex: "#FA2D48")
}

// MARK: - Press feedback

/// Cards shrink a little under the finger, the way App Store and Music cards do.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Page chrome

/// The poster-style title at the top of each tab.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.display(48))
                .foregroundStyle(Theme.cream)
                .lineLimit(1).minimumScaleFactor(0.55)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.system(.callout, design: .serif)).italic()
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows the page's title in the navigation bar only once its own big title has scrolled away.
struct RevealedTitle: ViewModifier {
    let title: String
    let threshold: CGFloat
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > threshold
            } action: { _, new in
                withAnimation(.easeInOut(duration: 0.2)) { shown = new }
            }
            // Heroes run under the bar and bring their own shading; the bar's blur only comes in with the title.
            .scrollEdgeEffectHidden(!shown, for: .top)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title).font(.headline).foregroundStyle(Theme.cream).lineLimit(1)
                        .opacity(shown ? 1 : 0)
                        .accessibilityHidden(!shown)
                }
            }
    }
}

extension View {
    func revealedTitle(_ title: String, after threshold: CGFloat) -> some View {
        modifier(RevealedTitle(title: title, threshold: threshold))
    }

    /// The settings button at the top right of every tab's first page.
    func rootToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
        }
    }
}

struct SettingsButton: View {
    @Environment(PhoneRouter.self) private var router
    @Environment(PlayerController.self) private var player

    var body: some View {
        Button { router.showSettings = true } label: {
            Image(systemName: "gearshape")
                .overlay(alignment: .topTrailing) {
                    // A nudge until Apple Music is connected: without it, songs are 30-second previews.
                    if !player.appleMusic.isReady {
                        Circle().fill(Theme.appleMusicRed).frame(width: 7, height: 7).offset(x: 3, y: -2)
                    }
                }
        }
        .accessibilityLabel(player.appleMusic.isReady ? "Settings" : "Settings, Apple Music not connected")
    }
}

// MARK: - Section pieces

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var tint: Color = Theme.brass
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Rectangle().fill(tint).frame(width: 22, height: 4)
                    Text(title.uppercased()).font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
                        .accessibilityAddTraits(.isHeader)
                }
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, Theme.gutter)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, tint: Color = Theme.brass) {
        self.init(title: title, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

/// "See All" at the end of a section header.
struct SeeAllLink: View {
    let route: PhoneRoute
    var tint: Color = Theme.brass
    var body: some View {
        NavigationLink(value: route) {
            Text("See All").font(.subheadline.weight(.semibold)).foregroundStyle(tint)
        }
    }
}

struct Chip: View {
    let text: String
    var tint: Color = Theme.brass
    var filled = false
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .foregroundStyle(filled ? Theme.ink : tint)
        .background(Capsule().fill(filled ? tint : tint.opacity(0.14)))
        .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 1))
        .contentShape(Capsule())
    }
}

struct EraChip: View {
    let era: Era
    var body: some View {
        NavigationLink(value: PhoneRoute.era(era.id)) { Chip(text: era.name, tint: era.tint) }
            .buttonStyle(.pressable)
    }
}

/// A filter chip that toggles, with a selection tick.
struct FilterChip: View {
    let text: String
    var tint: Color = Theme.cream
    let selected: Bool
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) { Chip(text: text, tint: tint, filled: selected, systemImage: systemImage) }
            .buttonStyle(.pressable)
            .sensoryFeedback(.selection, trigger: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A horizontally scrolling shelf that snaps to its cards and lines up with the page margins.
struct HRow<Content: View>: View {
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: spacing) { content() }
                .scrollTargetLayout()
                .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
    }
}

/// Long text that opens up with "More".
struct ExpandableText: View {
    let text: String
    var lines = 6
    var font: Font = .system(.body, design: .serif)
    var color: Color = Theme.cream.opacity(0.88)
    var tint: Color = Theme.brass
    @State private var expanded = false
    @State private var truncated = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(font).lineSpacing(4).foregroundStyle(color)
                .lineLimit(expanded ? nil : lines)
                .background {
                    // Measure the full text to know whether "More" is needed.
                    ViewThatFits(in: .vertical) {
                        Text(text).font(font).lineSpacing(4).hidden().onAppear { truncated = false }
                        Color.clear.onAppear { truncated = true }
                    }
                }
            if truncated {
                Button(expanded ? "Less" : "More") {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                }
                .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            }
        }
    }
}

struct Attribution: View {
    let text: String
    var url: URL? = nil
    var body: some View {
        Group {
            if let url {
                Link(destination: url) { Label(text, systemImage: "info.circle") }
            } else {
                Label(text, systemImage: "info.circle")
            }
        }
        .font(.caption).foregroundStyle(Theme.faint)
    }
}

/// A rounded panel for groups of facts.
struct Panel<Content: View>: View {
    var tint: Color = Theme.brass
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content() }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.18)))
            .padding(.horizontal, Theme.gutter)
    }
}

struct Kicker: View {
    let text: String
    var tint: Color = Theme.brass
    var body: some View {
        Text(text.uppercased()).font(Theme.label(11)).tracking(1.8).foregroundStyle(tint)
    }
}

// MARK: - Cards

struct ArtistCard: View {
    let artist: Artist
    /// A fixed width for shelves; nil fills the grid column.
    var width: CGFloat? = 140
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        NavigationLink(value: PhoneRoute.artist(artist.id)) {
            VStack(alignment: .leading, spacing: 8) {
                ArtistPortrait(artist: artist, tint: library.color(forEra: artist.primaryEra))
                    .aspectRatio(1 / 1.22, contentMode: .fit)
                    .frame(width: width)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
                        .lineLimit(1)
                    Text([artist.instrument, artist.lifespan].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}

struct AlbumCard: View {
    let album: Album
    var width: CGFloat? = 150
    var showArtist = true

    var body: some View {
        NavigationLink(value: PhoneRoute.album(album.id)) {
            VStack(alignment: .leading, spacing: 8) {
                AlbumCover(album: album, size: 400, cornerRadius: 6)
                    .frame(width: width)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                    if showArtist {
                        Text(album.artistName).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                    Text("\(String(album.year)) · \(album.label)").font(.caption2).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            .frame(width: width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}

/// Full-bleed duotone hero with poster typography, for era pages.
struct HeroBanner: View {
    let imageURL: URL?
    let tint: Color
    let kicker: String
    let title: String
    let subtitle: String
    var height: CGFloat = 440

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemoteImage(url: imageURL) { tint.opacity(0.25) }
                .frame(maxWidth: .infinity).frame(height: height)
                .clipped()
                .duotone(tint, strength: 0.9)
            LinearGradient(stops: [.init(color: Theme.ink.opacity(0.35), location: 0),
                                   .init(color: .clear, location: 0.25),
                                   .init(color: Theme.ink.opacity(0.55), location: 0.6),
                                   .init(color: Theme.ink, location: 1)],
                           startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: kicker, tint: tint)
                Text(title.uppercased())
                    .font(Theme.display(54)).foregroundStyle(Theme.cream)
                    .lineLimit(2).minimumScaleFactor(0.5)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle).font(.system(.title3, design: .serif)).italic()
                    .foregroundStyle(Theme.cream.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
        }
        .frame(height: height)
        .clipped()
    }
}
