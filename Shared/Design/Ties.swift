import SwiftUI

// Why two artists are connected, and chains of connections: used by the Connections maps and artist pages on both
// apps. Navigation is passed in, since each app has its own router.

extension Tie {
    /// "3 records together", "On Kind of Blue", "Mentor", "Played together".
    var kindText: String {
        switch albums.count {
        case 1: return "On \(albums[0].title)"
        case let n where n > 1: return "\(n) records together"
        default: break
        }
        switch bond?.kind {
        case "mentor": return "Mentor and student"
        case "influence": return "Influence"
        case "duo": return "Duo"
        case "band": return "Played together"
        default: return "Connected"
        }
    }

    /// A caption under a face: "3 records", "1 record", or the bond's kind.
    var shortText: String {
        if !albums.isEmpty { return albums.count == 1 ? "1 record" : "\(albums.count) records" }
        switch bond?.kind {
        case "mentor": return "mentor"
        case "influence": return "influence"
        case "duo": return "duo"
        default: return "played together"
        }
    }
}

/// The two artists, how they're tied, the bond's story and the records they share (tap a cover to open it).
struct TieDetails: View {
    let tie: Tie
    var openArtist: (String) -> Void
    var openAlbum: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let a = library.artist(tie.a), b = library.artist(tie.b)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let a { face(a) }
                Text("×").font(Theme.display(22)).foregroundStyle(Theme.muted)
                if let b { face(b) }
            }
            Text(tie.kindText.uppercased()).font(Theme.label(10)).tracking(1.4).foregroundStyle(Theme.brass)
            if let note = tie.bond?.note {
                Text(note).font(.scaled(size: 13)).foregroundStyle(Theme.cream.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !tie.albums.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tie.albums) { album in
                            Button { openAlbum(album.id) } label: {
                                AlbumCover(album: album, size: 200, cornerRadius: 4)
                                    .frame(width: 64, height: 64)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(album.title), \(String(album.year))")
                        }
                    }
                }
            }
        }
    }

    private func face(_ artist: Artist) -> some View {
        Button { openArtist(artist.id) } label: {
            HStack(spacing: 7) {
                ArtistPortrait(artist: artist, tint: library.color(forEra: artist.primaryEra))
                    .frame(width: 34, height: 34).clipShape(Circle())
                Text(artist.name).font(.scaled(size: 13, weight: .semibold)).foregroundStyle(Theme.cream)
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.plain)
    }
}

/// A chain of artists, top to bottom, with what links each one to the next.
struct PathStepsList: View {
    let steps: [PathStep]
    var openArtist: (String) -> Void
    var openAlbum: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i == 0, let first = library.artist(step.from) { person(first) }
                link(step)
                if let next = library.artist(step.to) { person(next) }
            }
        }
    }

    private func person(_ artist: Artist) -> some View {
        Button { openArtist(artist.id) } label: {
            HStack(spacing: 10) {
                ArtistPortrait(artist: artist, tint: library.color(forEra: artist.primaryEra))
                    .frame(width: 38, height: 38).clipShape(Circle())
                    .overlay(Circle().strokeBorder(library.color(forEra: artist.primaryEra), lineWidth: 1.5))
                VStack(alignment: .leading, spacing: 1) {
                    Text(artist.name).font(.scaled(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
                    Text([artist.instrument, artist.lifespan].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.scaled(size: 11)).foregroundStyle(Theme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func link(_ step: PathStep) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Theme.brass.opacity(0.6)).frame(width: 2).frame(maxHeight: .infinity)
                .padding(.leading, 18)
            VStack(alignment: .leading, spacing: 3) {
                if let album = step.tie.albums.first {
                    Button { openAlbum(album.id) } label: {
                        HStack(spacing: 6) {
                            AlbumCover(album: album, size: 100, cornerRadius: 2).frame(width: 22, height: 22)
                            Text("\(album.title) (\(String(album.year)))").font(.scaled(size: 12, weight: .medium))
                                .foregroundStyle(Theme.brass).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    if step.tie.albums.count > 1 {
                        Text("and \(step.tie.albums.count - 1) more together").font(.scaled(size: 11)).foregroundStyle(Theme.faint)
                    }
                } else if let note = step.tie.bond?.note {
                    Text(note).font(.scaled(size: 12)).italic().foregroundStyle(Theme.cream.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

enum PathMusic {
    /// One track per link in the chain: a record both artists are on (a starred track they both play, if there is
    /// one), or, for a link that's a bond, a signature tune of the next artist. Looked up on Apple Music.
    static func tracks(for steps: [PathStep], library: JazzLibrary) async -> [CatalogTrack] {
        var out: [CatalogTrack] = []
        for step in steps {
            var found: CatalogTrack?
            if let album = step.tie.albums.first {
                let both = album.highlights.first { title in
                    [step.from, step.to].allSatisfy { id in
                        id == album.artist || library.credit(of: id, on: album.id)?.plays(on: title) == true
                    }
                } ?? album.highlights.first
                if let title = both { found = await ITunes.shared.track(title, artist: album.artistName) }
            } else if let next = library.artist(step.to), let title = next.signatureTracks.first {
                found = await ITunes.shared.track(title, artist: next.name)
            }
            if let found, !out.contains(where: { $0.trackId == found.trackId }) { out.append(found) }
        }
        return out
    }
}
