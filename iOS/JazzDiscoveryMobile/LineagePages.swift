import SwiftUI

struct LineagesPage: View {
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Lineages", subtitle: "Follow one instrument through the century: who learned from whom, and what changed each time.")
                VStack(spacing: 12) {
                    ForEach(library.lineages) { l in
                        NavigationLink(value: PhoneRoute.lineage(l.id)) { LineageCard(lineage: l, width: nil) }.buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Lineages", after: 60)
    }
}

struct LineageDetailView: View {
    let lineage: Lineage
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            LineageDetailContent(lineage: lineage, compact: true) { router.go(.artist($0)) }
                .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle(lineage.title, after: 100)
    }
}

struct GlossaryPage: View {
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Glossary", subtitle: "The words jazz uses, each with a recording to hear it in.")
                HowToListenCard(openTerm: { router.go(.term($0)) }, openGuide: { router.go(.guide($0)) }).padding(.horizontal, Theme.gutter)
                GlossaryList { router.go(.term($0)) }.padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Glossary", after: 60)
    }
}

struct TermDetailView: View {
    let term: GlossaryTerm
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            TermDetailContent(term: term, compact: true, openTerm: { router.go(.term($0)) }, openEra: { router.go(.era($0)) })
                .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle(term.term, after: 100)
    }
}

struct PathsPage: View {
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Paths", subtitle: "Journeys with a point of view: a handful of stops, each with something to listen for.")
                VStack(spacing: 12) { PathsRow(cardWidth: nil) { router.go(.journey($0)) } }
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Paths", after: 60)
    }
}

struct PathDetailView: View {
    let path: JourneyPath
    @Environment(PhoneRouter.self) private var router
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        ScrollView {
            PathDetailContent(path: path, compact: true,
                              open: { stop in if let r = Route(stop: stop, library: library) { router.go(.page(r)) } },
                              openPath: { router.go(.journey($0)) }, openGuide: { router.go(.guide($0)) })
                .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle(path.title, after: 100)
    }
}

/// The year at a glance, and what happened on any day.
struct AlmanacPage: View {
    var month: Int?
    var day: Int?
    @Environment(PhoneRouter.self) private var router
    @State private var selected = Calendar.current.dateComponents([.month, .day], from: Today.date)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "On This Day", subtitle: "Birthdays and recording sessions, every day of the year.")
                AlmanacDayList(month: selected.month ?? 1, day: selected.day ?? 1) { router.go(.page($0)) }
                    .padding(.horizontal, Theme.gutter)
                AlmanacGrid(selected: $selected, columns: 2).padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("On This Day", after: 60)
        .onAppear { if let month, let day { selected = DateComponents(month: month, day: day) } }
    }
}

struct GuidesPage: View {
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Listening Guides", subtitle: "One recording at a time, section by section, following the music. They follow the full track, with Apple Music.")
                VStack(spacing: 12) { GuidesRow(cardWidth: nil) { router.go(.guide($0)) } }
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Listening Guides", after: 60)
    }
}

struct GuideDetailView: View {
    let guide: Guide
    @Environment(PhoneRouter.self) private var router
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        GuideView(guide: guide, compact: true, openArtist: { router.go(.artist($0)) }, openTerm: { router.go(.term($0)) },
                  openAlbum: { router.go(.album($0)) })
            .navigationTitle(library.tracks[guide.track]?.title ?? "Guide")
            .navigationBarTitleDisplayMode(.inline)
    }
}
