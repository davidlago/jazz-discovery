import SwiftUI

struct SearchTab: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        let q = router.query.trimmingCharacters(in: .whitespaces)
        ScrollView {
            if q.isEmpty {
                browse
            } else {
                results(library.search(q), query: q)
            }
        }
        .searchable(text: $router.query, prompt: "Artists, albums, eras, years")
        .scrollDismissesKeyboard(.immediately)
        .background(Theme.ink)
        .navigationTitle("Search")
        .toolbarTitleDisplayMode(.inlineLarge)
        .rootToolbar()
    }

    // MARK: Browse (no query yet)

    private var browse: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Styles")
                FlowLayout(spacing: 8) { ForEach(library.eras) { EraChip(era: $0) } }
                    .padding(.horizontal, Theme.gutter)
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Instruments")
                FlowLayout(spacing: 8) {
                    ForEach(library.instruments, id: \.self) { i in
                        Button { router.query = i } label: { Chip(text: i.capitalized, tint: Theme.cream) }
                            .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Decades")
                FlowLayout(spacing: 8) {
                    ForEach(library.decades, id: \.self) { d in
                        NavigationLink(value: PhoneRoute.decade(d)) { Chip(text: "\(String(d))s", tint: Theme.brass) }
                            .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Try")
                FlowLayout(spacing: 8) {
                    ForEach(["Coltrane", "1959", "Blue Note", "Impulse!", "vocals", "Kind of Blue"], id: \.self) { t in
                        Button { router.query = t } label: { Chip(text: t, tint: Theme.muted, systemImage: "magnifyingglass") }
                            .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
        }
        .padding(.top, 12).padding(.bottom, 32)
    }

    // MARK: Results

    @ViewBuilder
    private func results(_ r: JazzLibrary.SearchResults, query: String) -> some View {
        if r.isEmpty {
            ContentUnavailableView.search(text: query)
                .padding(.top, 60)
        } else {
            LazyVStack(alignment: .leading, spacing: 26) {
                if !r.eras.isEmpty {
                    resultSection("Eras") {
                        ForEach(r.eras) { e in
                            ResultRow(route: .era(e.id), title: e.name, subtitle: "\(e.years) · \(e.tagline)") {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(e.tint)
                                    .overlay(Text(String(e.start)).font(Theme.display(13)).foregroundStyle(Theme.ink))
                            }
                        }
                    }
                }
                if !r.artists.isEmpty {
                    resultSection("Artists") {
                        ForEach(r.artists) { a in
                            ResultRow(route: .artist(a.id), title: a.name,
                                      subtitle: [a.instrument.capitalized, a.lifespan].filter { !$0.isEmpty }.joined(separator: " · ")) {
                                ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra)).clipShape(Circle())
                            }
                        }
                    }
                }
                if !r.albums.isEmpty {
                    resultSection("Albums") {
                        ForEach(r.albums) { a in
                            ResultRow(route: .album(a.id), title: a.title, subtitle: "\(a.artistName) · \(String(a.year)) · \(a.label)") {
                                AlbumCover(album: a, size: 200, cornerRadius: 6)
                            }
                        }
                    }
                }
                if !r.tunes.isEmpty {
                    resultSection("Songbook") {
                        ForEach(r.tunes) { t in
                            ResultRow(route: .tune(t.id), title: t.title,
                                      subtitle: "\(Session.joinedList(t.composers.map(library.composerName))) · \(String(t.year)) · \(t.versions.count) versions") {
                                Image(systemName: "music.quarternote.3").font(.title3).foregroundStyle(Theme.brass)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.panelHi)
                            }
                        }
                    }
                }
                if !r.players.isEmpty {
                    resultSection("On the Records") {
                        ForEach(r.players) { p in
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.body.weight(.semibold)).foregroundStyle(Theme.cream)
                                    Text(p.instruments.joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.muted)
                                }
                                FlowLayout(spacing: 6) {
                                    ForEach(p.albums) { a in
                                        NavigationLink(value: PhoneRoute.album(a.id)) {
                                            Chip(text: a.title, tint: library.color(forEra: a.era))
                                        }
                                        .buttonStyle(.pressable)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        }
                    }
                }
            }
            .padding(.top, 12).padding(.bottom, 32)
        }
    }

    private func resultSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: title)
            VStack(spacing: 0) { content() }
                .padding(.horizontal, Theme.gutter)
        }
    }
}

private struct ResultRow<Thumb: View>: View {
    let route: PhoneRoute
    let title: String
    let subtitle: String
    @ViewBuilder var thumb: () -> Thumb

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 14) {
                thumb().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.faint)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}
