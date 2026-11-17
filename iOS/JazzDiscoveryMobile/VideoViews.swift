import SwiftUI
import WebKit

/// A shelf of YouTube results for a query; tapping one plays it in the app.
struct VideoStrip: View {
    let query: String
    var tint: Color = Theme.brass
    var limit = 8
    @State private var videos: [YouTubeVideo] = []
    @State private var loaded = false
    @State private var playing: YouTubeVideo?

    var body: some View {
        Group {
            if !loaded {
                HRow {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.panel).frame(width: 260, height: 146)
                    }
                }
                .redacted(reason: .placeholder)
                .accessibilityLabel("Loading videos")
            } else if videos.isEmpty {
                HStack {
                    Text("Couldn't load videos right now.").foregroundStyle(Theme.muted)
                    Button("Search YouTube", action: openSearch).foregroundStyle(tint)
                }
                .font(.subheadline)
                .padding(.horizontal, Theme.gutter)
            } else {
                HRow {
                    ForEach(videos) { v in VideoCard(video: v, tint: tint) { playing = v } }
                    Button(action: openSearch) {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.title3)
                            Text("More on YouTube").font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(Theme.muted)
                        .frame(width: 130, height: 146)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.panelHi, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .task(id: query) {
            videos = await YouTube.shared.search(query, limit: limit)
            loaded = true
        }
        .sheet(item: $playing) { v in VideoPlayerSheet(video: v, tint: tint) }
    }

    private func openSearch() {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "https://www.youtube.com/results?search_query=\(q)") { Platform.open(url) }
    }
}

struct VideoCard: View {
    let video: YouTubeVideo
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RemoteImage(url: video.thumbnail) { Theme.panel }
                        .frame(width: 260, height: 146).clipped()
                    Image(systemName: "play.fill")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(tint))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let l = video.length {
                        Text(l).font(.caption2.weight(.bold).monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.black.opacity(0.75)))
                            .foregroundStyle(.white).padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(video.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(width: 260, alignment: .leading)
                if let c = video.channel {
                    Text(c).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(width: 260, alignment: .leading)
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays the video")
    }
}

struct VideoPlayerSheet: View {
    let video: YouTubeVideo
    let tint: Color
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            YouTubePlayer(videoID: video.id)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title).font(.headline).foregroundStyle(Theme.cream)
                if let c = video.channel {
                    Text([c, video.length].compactMap { $0 }.joined(separator: " · ")).font(.subheadline).foregroundStyle(Theme.muted)
                }
            }
            Button { Platform.open(video.watchURL) } label: {
                Label("Open in YouTube", systemImage: "arrow.up.forward.square")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .foregroundStyle(Theme.cream)
            Spacer(minLength: 0)
        }
        .padding(Theme.gutter)
        .padding(.top, 8)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.panel)
        .onAppear { if player.isPlaying { player.togglePlayPause() } }
    }
}

/// YouTube's embedded player in a WKWebView.
struct YouTubePlayer: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        load(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: ()) {
        web.loadHTMLString("", baseURL: nil)
    }

    private func load(_ web: WKWebView) {
        // The embed must be served from an https origin so YouTube receives a referrer.
        let origin = "https://jazzdiscovery.app"
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe src="https://www.youtube.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1&origin=\(origin)"
          referrerpolicy="strict-origin-when-cross-origin"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: origin))
    }
}

// MARK: - Picture archive

/// A photo from the archive, full screen: pinch or double-tap to zoom, swipe down to close.
struct ImageViewer: View {
    let image: WikiImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragDown: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(1 - min(0.6, Double(abs(dragDown)) / 400)).ignoresSafeArea()
            RemoteImage(url: image.url, contentMode: .fit) { ProgressView().tint(.white) }
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height + dragDown)
                .gesture(MagnifyGesture()
                    .onChanged { scale = max(1, min(5, lastScale * $0.magnification)) }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 { withAnimation(.spring) { offset = .zero; lastOffset = .zero } }
                    })
                .simultaneousGesture(DragGesture()
                    .onChanged { v in
                        if scale > 1 {
                            offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height)
                        } else {
                            dragDown = v.translation.height
                        }
                    }
                    .onEnded { v in
                        if scale > 1 { lastOffset = offset; return }
                        if abs(v.predictedEndTranslation.height) > 220 { dismiss() }
                        else { withAnimation(.spring) { dragDown = 0 } }
                    })
                .onTapGesture(count: 2) {
                    withAnimation(.spring) {
                        if scale > 1 { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero }
                        else { scale = 2.5; lastScale = 2.5 }
                    }
                }
                .accessibilityLabel(image.caption ?? "Archive photo")
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(Theme.gutter)
            .accessibilityLabel("Close")
        }
        .overlay(alignment: .bottom) {
            if let c = image.caption, scale <= 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(c).font(.footnote).foregroundStyle(.white.opacity(0.9))
                    Text("Wikimedia Commons").font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.gutter)
                .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                .opacity(dragDown == 0 ? 1 : 0)
            }
        }
        .statusBarHidden()
        .presentationBackground(.clear)
    }
}
