import SwiftUI

/// Your listening passport: a stamp per era, where in time you've been, the instruments you've heard most, and what
/// you've heard and saved.
struct PassportView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(Router.self) private var router
    @Environment(PlayerController.self) private var player
    @State private var importing = false

    var body: some View {
        let heard = passport.heardCount
        let recent = passport.recentlyHeard(limit: 20).compactMap { library.album($0.albumID) }
        let savedAlbums = passport.savedAlbums.compactMap { library.album($0) }
        let savedArtists = passport.savedArtists.compactMap { library.artist($0) }
        let instruments = passport.instrumentsHeard(library: library)

        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PASSPORT").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text(heard == 0
                         ? "A stamp for every era, inked as you hear its records. Play a record through, or mark one you know."
                         : "\(heard) of \(library.albums.count) records heard.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                Spacer()
                if case .connected = player.scrobbler.status {
                    Button { importing = true } label: { Label("Import from Last.fm…", systemImage: "square.and.arrow.down") }
                }
                }
                .padding(.top, 30).padding(.horizontal, 40)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 170), spacing: 26)], spacing: 30) {
                    ForEach(library.eras) { era in
                        Button { router.go(.era(era.id)) } label: { EraStamp(era: era, size: 150) }
                            .buttonStyle(.plain)
                            .help("\(era.name): open the era")
                    }
                }
                .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(title: "Where You've Been", subtitle: "Each decade's records, filled in as you hear them.")
                    DecadeStrip()
                }
                .padding(.horizontal, 40)

                if !instruments.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "What You've Heard Most", subtitle: "Instruments on the records you've heard.")
                        FlowLayout(spacing: 8) {
                            ForEach(instruments, id: \.instrument) { i in
                                Chip(text: "\(i.instrument.capitalized) · \(i.records)", tint: Theme.brass)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }

                if !recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Recently Heard").padding(.horizontal, 40)
                        HRow { ForEach(recent) { AlbumCard(album: $0) } }
                    }
                }
                if !savedAlbums.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Saved Records").padding(.horizontal, 40)
                        HRow { ForEach(savedAlbums) { AlbumCard(album: $0) } }
                    }
                }
                if !savedArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "Saved Artists").padding(.horizontal, 40)
                        HRow { ForEach(savedArtists) { ArtistCard(artist: $0) } }
                    }
                }
                PassportFooter().padding(.horizontal, 40)
            }
            .padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Passport")
        .sheet(isPresented: $importing) { LastFMImportView(scrobbler: player.scrobbler) }
    }
}

/// One tile per decade, filled from the bottom by the share of its records heard.
struct DecadeStrip: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 6) {
            ForEach(passport.decadeProgress(library: library), id: \.decade) { d in
                let f = d.total == 0 ? 0 : CGFloat(d.heard) / CGFloat(d.total)
                Button { router.go(.decade(d.decade)) } label: {
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4).fill(Theme.panel)
                            RoundedRectangle(cornerRadius: 4).fill(tint(d.decade).opacity(0.85))
                                .frame(height: 70 * f)
                            RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.panelHi)
                        }
                        .frame(height: 70)
                        Text("’\(String(d.decade).suffix(2))").font(Theme.label(11)).foregroundStyle(Theme.cream)
                        Text("\(d.heard)/\(d.total)").font(.system(size: 10).monospacedDigit()).foregroundStyle(Theme.faint)
                    }
                }
                .buttonStyle(.plain)
                .help("The \(String(d.decade))s: \(d.heard) of \(d.total) records heard")
            }
        }
    }

    /// The first era under way in the middle of the decade.
    private func tint(_ decade: Int) -> Color {
        library.eras.first { $0.start <= decade + 5 && $0.end >= decade + 5 }?.tint ?? Theme.brass
    }
}

/// Where the passport is kept, and how to start over.
struct PassportFooter: View {
    @Environment(Passport.self) private var passport
    @State private var confirmErase = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(passport.syncsWithICloud ? "Your passport syncs with your iPhone through your iCloud." : "Your passport stays on this Mac.") Records count as heard when most of their tracks have played in full; you can unmark any of them.")
                .font(.system(size: 12)).foregroundStyle(Theme.faint)
            Spacer()
            if !passport.isEmpty {
                Button("Erase Passport…", role: .destructive) { confirmErase = true }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .confirmationDialog("Erase your passport?", isPresented: $confirmErase) {
            Button("Erase", role: .destructive) { passport.erase() }
        } message: {
            Text("Every heard, sampled and saved mark is removed. This can't be undone.")
        }
    }
}

/// An era's stamp and "4 of 9 records heard", in the corner of its page; opens the passport.
struct EraProgressBadge: View {
    let era: Era
    @Environment(Passport.self) private var passport
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        let p = passport.progress(inEra: era.id, library: library)
        Button { router.show(.passport) } label: {
            VStack(spacing: 8) {
                EraStamp(era: era, size: 110)
                Text(p.heard == 0 ? "\(p.total) records to hear" : "\(p.heard) of \(p.total) records heard")
                    .font(Theme.label(11)).tracking(1).foregroundStyle(Theme.cream.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
        .help("Your passport")
    }
}
