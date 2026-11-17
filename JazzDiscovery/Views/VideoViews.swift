import SwiftUI
import WebKit

/// A horizontal strip of YouTube results for a query; clicking plays the video in-app.
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
                HRow { ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 8).fill(Theme.panel).frame(width: 300, height: 169)
                } }
                .redacted(reason: .placeholder)
            } else if videos.isEmpty {
                HStack {
                    Text("Couldn't load videos right now.").foregroundStyle(Theme.muted)
                    Button("Search on YouTube") { openSearch() }.buttonStyle(.link)
                }
                .padding(.horizontal, 40)
            } else {
                HRow {
                    ForEach(videos) { v in
                        VideoCard(video: v, tint: tint) { playing = v }
                    }
                    Button(action: openSearch) {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").font(.system(size: 22))
                            Text("More on YouTube").font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(Theme.muted)
                        .frame(width: 160, height: 169)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.panelHi, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
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
        if let url = URL(string: "https://www.youtube.com/results?search_query=\(q)") { NSWorkspace.shared.open(url) }
    }
}

struct VideoCard: View {
    let video: YouTubeVideo
    let tint: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RemoteImage(url: video.thumbnail) { Theme.panel }
                        .frame(width: 300, height: 169).clipped()
                    Color.black.opacity(hovering ? 0.25 : 0)
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(tint))
                        .scaleEffect(hovering ? 1.1 : 0.9).opacity(hovering ? 1 : 0.85)
                }
                .overlay(alignment: .bottomTrailing) {
                    if let l = video.length {
                        Text(l).font(.system(size: 11, weight: .bold).monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.75)))
                            .foregroundStyle(.white).padding(8)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .hoverLift(1.02)
                Text(video.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream)
                    .lineLimit(2).multilineTextAlignment(.leading).frame(width: 300, alignment: .leading)
                if let c = video.channel {
                    Text(c).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            .frame(width: 300, alignment: .leading)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct VideoPlayerSheet: View {
    let video: YouTubeVideo
    let tint: Color
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(video.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { NSWorkspace.shared.open(video.watchURL) } label: { Label("Open on YouTube", systemImage: "arrow.up.forward.square") }
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            YouTubePlayer(videoID: video.id)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
        }
        .frame(width: 1024)
        .background(Theme.panel)
        .onAppear { if player.isPlaying { player.togglePlayPause() } }
    }
}

/// YouTube's embedded player in a WKWebView.
struct YouTubePlayer: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        load(web)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}

    static func dismantleNSView(_ web: WKWebView, coordinator: ()) {
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
