import SwiftUI

/// Your listening passport: a stamp per era, where in time you've been, the instruments you've heard most, and what
/// you've heard and saved.
struct PassportView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @State private var confirmErase = false
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        let heard = passport.heardCount
        let recent = passport.recentlyHeard(limit: 20).compactMap { library.album($0.albumID) }
        let savedAlbums = passport.savedAlbums.compactMap { library.album($0) }
        let savedArtists = passport.savedArtists.compactMap { library.artist($0) }
        let instruments = passport.instrumentsHeard(library: library)

        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader(title: "Passport",
                           subtitle: heard == 0
                           ? "A stamp for every era, inked as you hear its records. Play a record through, or mark one you know."
                           : "\(heard) of \(library.albums.count) records heard.")

                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(library.eras) { era in
                        NavigationLink(value: PhoneRoute.era(era.id)) { EraStamp(era: era, size: 104) }
                            .buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Where You've Been", subtitle: "Each decade's records, filled in as you hear them.")
                    PhoneDecadeStrip().padding(.horizontal, Theme.gutter)
                }

                if !instruments.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(title: "What You've Heard Most")
                        FlowLayout(spacing: 8) {
                            ForEach(instruments, id: \.instrument) { Chip(text: "\($0.instrument.capitalized) · \($0.records)") }
                        }
                        .padding(.horizontal, Theme.gutter)
                    }
                }
                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Recently Heard")
                        HRow { ForEach(recent) { AlbumCard(album: $0) } }
                    }
                }
                if !savedAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Saved Records")
                        HRow { ForEach(savedAlbums) { AlbumCard(album: $0) } }
                    }
                }
                if !savedArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Saved Artists")
                        HRow { ForEach(savedArtists) { ArtistCard(artist: $0) } }
                    }
                }
                Text("Your passport stays on this iPhone. Records count as heard when most of their tracks have played in full; you can unmark any of them from the record's page.")
                    .font(.footnote).foregroundStyle(Theme.faint)
                    .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Passport", after: 60)
        .toolbar {
            if !passport.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Erase Passport…", systemImage: "trash", role: .destructive) { confirmErase = true }
                    } label: { Image(systemName: "ellipsis") }
                }
            }
        }
        .confirmationDialog("Erase your passport?", isPresented: $confirmErase, titleVisibility: .visible) {
            Button("Erase", role: .destructive) { passport.erase() }
        } message: {
            Text("Every heard, sampled and saved mark is removed. This can't be undone.")
        }
    }
}

/// One tile per decade, filled from the bottom by the share of its records heard.
struct PhoneDecadeStrip: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport

    var body: some View {
        HStack(spacing: 4) {
            ForEach(passport.decadeProgress(library: library), id: \.decade) { d in
                let f = d.total == 0 ? 0 : CGFloat(d.heard) / CGFloat(d.total)
                NavigationLink(value: PhoneRoute.decade(d.decade)) {
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.panel)
                            RoundedRectangle(cornerRadius: 3).fill(tint(d.decade).opacity(0.85)).frame(height: 56 * f)
                            RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.panelHi)
                        }
                        .frame(height: 56)
                        Text("’\(String(d.decade).suffix(2))").font(Theme.label(9)).foregroundStyle(Theme.cream)
                    }
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("The \(String(d.decade))s: \(d.heard) of \(d.total) records heard")
            }
        }
    }

    private func tint(_ decade: Int) -> Color {
        library.eras.first { $0.start <= decade + 5 && $0.end >= decade + 5 }?.tint ?? Theme.brass
    }
}

/// An era's stamp and "4 of 9 records heard", under its hero; opens the passport.
struct EraProgressRow: View {
    let era: Era
    @Environment(Passport.self) private var passport
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let p = passport.progress(inEra: era.id, library: library)
        NavigationLink(value: PhoneRoute.passport) {
            HStack(spacing: 14) {
                EraStamp(era: era, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p.heard == 0 ? "\(p.total) records to hear" : "\(p.heard) of \(p.total) records heard")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cream)
                    Text("Your passport").font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.faint)
            }
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, -14)
    }
}
