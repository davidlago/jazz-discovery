import Foundation
import MusicKit

/// `Jazz Discovery --self-test`: exercises every data source from inside the sandboxed app,
/// prints a report and exits. Useful after editing jazz.json or when a source changes.
enum SelfTest {
    static var requested: Bool { CommandLine.arguments.contains("--self-test") }

    @MainActor
    static func run(_ library: JazzLibrary) async {
        func out(_ s: String) { print(s); fflush(stdout) }
        out("Library: \(library.eras.count) eras, \(library.artists.count) artists, \(library.albums.count) albums, \(library.milestones.count) milestones, \(library.edges.count) connections")

        // Wikipedia: every era and artist.
        var noImage: [String] = [], failed: [String] = []
        await withTaskGroup(of: (String, WikiSummary?).self) { group in
            for t in library.eras.map(\.wikipedia) + library.artists.map(\.wikipedia) {
                group.addTask { (t, await Wikipedia.shared.summary(t)) }
            }
            for await (t, s) in group {
                if s == nil { failed.append(t) } else if s?.image == nil { noImage.append(t) }
            }
        }
        out("Wikipedia: \(library.eras.count + library.artists.count - failed.count) ok, failed: \(failed), no image: \(noImage)")
        var eraNoImage: [String] = []
        for e in library.eras where await Wikipedia.shared.leadImage(e.wikipedia) == nil { eraNoImage.append(e.id) }
        out("Eras without any hero image: \(eraNoImage)")
        let media = await Wikipedia.shared.images(library.eras.first!.wikipedia)
        out("Wikimedia gallery (\(library.eras.first!.name)): \(media.count) images")

        // Apple Music catalog (bundled + live).
        var missing: [String] = []
        for a in library.albums where await ITunes.shared.album(for: a) == nil { missing.append(a.id) }
        out("Albums matched: \(library.albums.count - missing.count)/\(library.albums.count), missing: \(missing)")
        if let a = library.albums.first(where: { $0.starter }), let c = await ITunes.shared.album(for: a) {
            let tracks = await ITunes.shared.tracks(collectionId: c.collectionId)
            out("Tracks for \(a.title): \(tracks.count), previews: \(tracks.filter { $0.preview != nil }.count)")
        }
        let top = await ITunes.shared.topSongs(artist: "Miles Davis")
        out("Top songs (Miles Davis): \(top.prefix(5).map(\.name))")
        if let ref = library.eras.first?.essentialTracks.first {
            let t = await ITunes.shared.track(ref.title, artist: ref.artist)
            out("Essential track '\(ref.title)': \(t.map { "\($0.name) — \($0.artistName)" } ?? "NOT FOUND")")
        }

        // YouTube.
        let v = await YouTube.shared.search(library.eras[3].documentaryQuery, limit: 3)
        out("YouTube '\(library.eras[3].documentaryQuery)': \(v.map(\.title))")

        out("MusicKit authorization: \(MusicAuthorization.currentStatus)")
        if MusicAuthorization.currentStatus == .authorized {
            do {
                let sub = try await MusicSubscription.current
                out("Apple Music subscription can play catalog: \(sub.canPlayCatalogContent)")
                let r = try await MusicCatalogResourceRequest<MusicKit.Album>(matching: \.id, equalTo: MusicItemID("268443092")).response()
                out("MusicKit catalog request OK: \(r.items.first?.title ?? "-") → full-track playback available")
            } catch {
                out("MusicKit catalog request FAILED: \(error)")
            }
            for path in ["v1/me/storefront", "v1/catalog/us/albums/268443092"] {
                do {
                    let resp = try await MusicDataRequest(urlRequest: URLRequest(url: URL(string: "https://api.music.apple.com/\(path)")!)).response()
                    out("Raw \(path): HTTP \(resp.urlResponse.statusCode), \(resp.data.count) bytes: \(String(decoding: resp.data.prefix(160), as: UTF8.self))")
                } catch {
                    out("Raw \(path) FAILED: \(error)")
                }
            }
        }
        exit(0)
    }
}
