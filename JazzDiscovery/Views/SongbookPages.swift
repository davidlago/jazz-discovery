import SwiftUI

/// The Songbook: every tune as a lead-sheet card.
struct SongbookView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("THE SONGBOOK").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("\(library.tunes.count) tunes, \(library.tunes.reduce(0) { $0 + $1.versions.count }) versions. Jazz is the art of playing the same song differently.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                SongbookGrid(minimum: 210) { router.go(.tune($0)) }
            }
            .padding(.horizontal, 40).padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Songbook")
    }
}

struct TuneDetailView: View {
    let tune: Tune
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                TuneDetailContent(tune: tune, openArtist: { router.go(.artist($0)) }, openAlbum: { router.go(.album($0)) },
                                  openTune: { router.go(.tune($0)) }, openTerm: { router.go(.term($0)) })
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch & Listen on YouTube")
                    VideoStrip(query: "\(tune.title) jazz live", tint: Theme.brass).padding(.horizontal, -40)
                }
            }
            .padding(.top, 40).padding(.horizontal, 40).padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle(tune.title)
    }
}
