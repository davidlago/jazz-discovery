import SwiftUI

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#else
import AppKit
typealias PlatformImage = NSImage
#endif

/// The few things the Mac and iPhone apps do differently below the views.
enum Platform {
    /// Opens a URL in the app that handles it (the browser, Music, YouTube…).
    @MainActor
    static func open(_ url: URL) {
        #if WIDGET_EXTENSION
        // Widgets open links with widgetURL/Link; extensions can't reach UIApplication.
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }

    static var name: String {
        #if os(iOS)
        "iOS"
        #else
        "macOS"
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}
