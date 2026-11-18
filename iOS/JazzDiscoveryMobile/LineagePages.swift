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
                HowToListenCard { router.go(.term($0)) }.padding(.horizontal, Theme.gutter)
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
