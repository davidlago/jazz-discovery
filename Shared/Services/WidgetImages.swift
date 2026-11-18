import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Fetches the Today widget's picture ahead of drawing: the record's cover, or the artist's portrait, made small.
enum WidgetImages {
    static func picture(for content: TodayWidgetContent, library: JazzLibrary) async -> Data? {
        var url: URL?
        if let id = content.albumID, let album = library.album(id) {
            url = await ITunes.shared.album(for: album)?.artwork(300)
        } else if let id = content.artistID, let artist = library.artist(id) {
            url = await Wikipedia.shared.summary(artist.wikipedia)?.image
        }
        guard let url, let data = try? await HTTP.data(url) else { return nil }
        return small(data)
    }

    /// At most 300 pixels on a side, as JPEG: a widget's whole timeline has to fit in a few megabytes.
    static func small(_ data: Data, maxPixels: Int = 300) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixels,
              ] as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}
