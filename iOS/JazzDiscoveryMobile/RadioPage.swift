import SwiftUI

/// Every station, as a wall of record labels.
struct RadioPage: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: "Radio", subtitle: "Stations that keep playing, each track with a line on why it's there.")
                RadioWall(labelSize: 104, gutter: Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Radio", after: 60)
    }
}

/// The Blindfold Test, full screen.
struct BlindfoldPage: View {
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Blindfold Test", subtitle: nil)
                BlindfoldView(compact: true) { router.go(.album($0)) }
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Blindfold Test", after: 60)
    }
}
