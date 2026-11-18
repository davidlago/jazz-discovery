import SwiftUI

/// One way out of a record: what kind of door it is, the record, and why.
struct DoorCard: View {
    let door: Door
    var compact = false
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let tint = library.color(forEra: door.album.era)
        Button { open(door.album.id) } label: {
            HStack(alignment: .top, spacing: 14) {
                AlbumCover(album: door.album, size: 300, cornerRadius: 4)
                    .frame(width: compact ? 72 : 96, height: compact ? 72 : 96)
                    .heardBadge(door.album.id, tint: tint, size: 20)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(door.kind.title.uppercased()).font(Theme.label(10)).tracking(1.4).foregroundStyle(tint)
                    Text(door.album.title).font(.system(size: compact ? 15 : 16, weight: .bold)).foregroundStyle(Theme.cream)
                        .lineLimit(2)
                    Text("\(door.album.artistName) · \(String(door.album.year))")
                        .font(.system(size: compact ? 12 : 13)).foregroundStyle(Theme.muted).lineLimit(1)
                    Text(door.because).font(.system(size: compact ? 12 : 13, design: .serif)).italic()
                        .foregroundStyle(Theme.cream.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(compact ? 12 : 14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.25)))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the record")
    }
}

/// The three doors out of a record, side by side (Mac) or stacked (iPhone).
struct DoorsList: View {
    let album: Album
    var stacked = false
    var compact = false
    var open: (String) -> Void
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        let doors = Recommender.doors(after: album, library: library, isHeard: passport.isHeard)
        if stacked {
            VStack(spacing: 10) { ForEach(doors) { DoorCard(door: $0, compact: compact, open: open) } }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ForEach(doors) { DoorCard(door: $0, compact: compact, open: open).frame(maxWidth: 380) }
            }
        }
    }
}

/// After an album has played to its end: the three doors, small, for the player.
struct FinishedAlbumDoors: View {
    var open: (String) -> Void
    @Environment(PlayerController.self) private var player
    @Environment(Passport.self) private var passport
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        if let c = player.finishedCollectionId, let id = passport.albumID(forCollection: c), let album = library.album(id) {
            let doors = Recommender.doors(after: album, library: library, isHeard: passport.isHeard)
            VStack(alignment: .leading, spacing: 8) {
                Text("FINISHED \(album.title.uppercased()) · WHERE NEXT?").font(Theme.label(10)).tracking(1.2)
                    .foregroundStyle(Theme.brass).lineLimit(1)
                HStack(spacing: 10) {
                    ForEach(doors) { d in
                        Button { open(d.album.id) } label: {
                            HStack(spacing: 8) {
                                AlbumCover(album: d.album, size: 200, cornerRadius: 3).frame(width: 40, height: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(d.kind.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                                        .lineLimit(1)
                                    Text(d.album.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cream)
                                        .lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(d.because)
                        .accessibilityLabel("\(d.kind.title): \(d.album.title) by \(d.album.artistName)")
                    }
                }
            }
            .transition(.opacity)
        }
    }
}

extension Passport {
    /// The first Start Here record not yet heard, and its place on the path.
    func nextStop(library: JazzLibrary) -> (number: Int, album: Album)? {
        library.starterPath.enumerated().first { !isHeard($0.element.id) }.map { ($0.offset + 1, $0.element) }
    }

    /// The record heard most recently.
    func lastHeard(library: JazzLibrary) -> Album? {
        recentlyHeard(limit: 1).first.flatMap { library.album($0.albumID) }
    }
}
