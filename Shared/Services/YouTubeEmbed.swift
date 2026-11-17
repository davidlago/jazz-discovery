import Foundation
import WebKit

/// YouTube's embedded player as both apps show it in a WKWebView: the page, a web view that keeps nothing, and the
/// rules that keep that web view on the player.
enum YouTubeEmbed {
    /// The page the embed sits in needs an https origin, so YouTube receives a referrer. It's the project's own
    /// (GitHub Pages for github.com/davidlago); nothing is loaded from it.
    static let origin = URL(string: "https://davidlago.github.io")!

    /// A configuration whose cookies and site data live in memory and go when the player closes, so YouTube can't
    /// recognize the device from one video to the next.
    @MainActor
    static func configuration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.mediaTypesRequiringUserActionForPlayback = []
        return config
    }

    /// Shows the video, or an empty page for an ID that isn't one. The ID goes into the page's HTML.
    @MainActor
    static func load(_ videoID: String, in web: WKWebView) {
        guard YouTubeVideo.isValidID(videoID) else { web.loadHTMLString("", baseURL: nil); return }
        // youtube-nocookie.com is YouTube's "privacy-enhanced" player.
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?autoplay=1&playsinline=1&rel=0&modestbranding=1&origin=\(origin.absoluteString)"
          referrerpolicy="strict-origin-when-cross-origin"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen></iframe>
        </body></html>
        """
        web.loadHTMLString(html, baseURL: origin)
    }

    /// Whether the player's frames may load this address: YouTube and the Google hosts its player uses.
    static func isPlayerHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host()?.lowercased() else { return false }
        return playerDomains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static let playerDomains = [
        "youtube-nocookie.com", "youtube.com", "google.com", "googleapis.com", "gstatic.com", "googlevideo.com",
        "ytimg.com", "ggpht.com", "doubleclick.net", "googlesyndication.com",
    ]
}

/// Keeps the player's web view from becoming a browser: the page itself never navigates anywhere, the frames inside
/// it only load YouTube's player, and a link the user follows (the YouTube logo, a video's title) opens in the
/// browser or the YouTube app instead.
final class YouTubeEmbedNavigation: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if let frame = action.targetFrame {
            if frame.isMainFrame {
                // Only the app's own page (loadHTMLString's base URL) and the empty page shown on closing.
                let isOwnPage = url.scheme == "https" && url.host() == YouTubeEmbed.origin.host() && url.path().count <= 1
                if action.navigationType == .other, isOwnPage || url.absoluteString == "about:blank" { return .allow }
            } else if url.scheme != "http", url.scheme != "https" {
                return .allow  // about:blank, about:srcdoc and blob: frames the player makes for itself
            } else if YouTubeEmbed.isPlayerHost(url) {
                return .allow
            }
        }
        // Anything else, including links that ask for a new window, leaves the app, and only when the user tapped it.
        if action.navigationType == .linkActivated, url.scheme == "https" { Platform.open(url) }
        return .cancel
    }
}
