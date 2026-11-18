import SwiftUI

/// The Songbook: every tune as a lead-sheet card.
struct SongbookPage: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "The Songbook",
                           subtitle: "\(library.tunes.count) tunes, \(library.tunes.reduce(0) { $0 + $1.versions.count }) versions. The same song, played differently.")
                SongbookGrid(minimum: 160) { router.go(.tune($0)) }.padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Songbook", after: 60)
    }
}

struct TuneDetailView: View {
    let tune: Tune
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                TuneDetailContent(tune: tune, compact: true,
                                  openArtist: { router.go(.artist($0)) }, openAlbum: { router.go(.album($0)) },
                                  openTune: { router.go(.tune($0)) }, openTerm: { router.go(.term($0)) })
                    .padding(.horizontal, Theme.gutter)
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch & Listen on YouTube")
                    VideoStrip(query: "\(tune.title) jazz live", tint: Theme.brass)
                }
            }
            .padding(.top, 16).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle(tune.title, after: 120)
    }
}
