import SwiftUI

struct LineagesView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LINEAGES").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("Follow one instrument through the century: who learned from whom, and what changed each time.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(library.lineages) { l in
                        Button { router.go(.lineage(l.id)) } label: { LineageCard(lineage: l, width: nil) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Lineages")
    }
}

struct LineageDetailView: View {
    let lineage: Lineage
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            LineageDetailContent(lineage: lineage) { router.go(.artist($0)) }
                .padding(.top, 40).padding(.horizontal, 40).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle(lineage.title)
    }
}

struct GlossaryView: View {
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("GLOSSARY").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("The words jazz uses, each with a recording to hear it in.").font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                HowToListenCard { router.go(.term($0)) }
                GlossaryList { router.go(.term($0)) }
            }
            .padding(.horizontal, 40).padding(.bottom, 50)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle("Glossary")
    }
}

struct TermDetailView: View {
    let term: GlossaryTerm
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            TermDetailContent(term: term, openTerm: { router.go(.term($0)) }, openEra: { router.go(.era($0)) })
                .padding(.top, 40).padding(.horizontal, 40).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle(term.term)
    }
}

struct PathsView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PATHS").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("Journeys with a point of view: a handful of stops, each with something to listen for. Your place is kept.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 300), spacing: 18)], alignment: .leading, spacing: 18) {
                    PathsRow(cardWidth: 260) { router.go(.journey($0)) }
                }
            }
            .padding(.horizontal, 40).padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Paths")
    }
}

struct PathDetailView: View {
    let path: JourneyPath
    @Environment(Router.self) private var router
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        ScrollView {
            PathDetailContent(path: path, open: { stop in if let r = Route(stop: stop, library: library) { router.go(r) } },
                              openPath: { router.go(.journey($0)) })
                .padding(.top, 40).padding(.horizontal, 40).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle(path.title)
    }
}
