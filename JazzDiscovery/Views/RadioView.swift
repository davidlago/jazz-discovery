import SwiftUI

/// Every station, as a wall of record labels.
struct RadioView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RADIO").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("Stations that keep playing, each track with a line on why it's there. Pick one and let it run.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30).padding(.horizontal, 40)
                RadioWall(labelSize: 140, gutter: 40)
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Radio")
    }
}

/// The Blindfold Test, as a page.
struct BlindfoldPage: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("BLINDFOLD TEST").font(Theme.display(64)).foregroundStyle(Theme.cream)
                BlindfoldView { router.go(.album($0)) }
            }
            .padding(.top, 30).padding(.horizontal, 40).padding(.bottom, 50)
            // The game and, beside it on a wide window, your ear (`SideColumnLayout`).
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle("Blindfold Test")
    }
}
