import SwiftUI

struct CrateTab: View {
    @Environment(JazzLibrary.self) private var library
    @State private var era: String? = nil
    @State private var startersOnly = false
    @State private var heard = HeardFilter.all
    @Environment(Passport.self) private var passport
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        let list = library.albums
            .filter { era == nil || $0.era == era }
            .filter { !startersOnly || $0.starter }
            .filter { heard.includes($0, passport) }
        let decades = Array(Set(list.map(\.decade))).sorted()

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                PageHeader(title: "The Crate", subtitle: "\(list.count) records that changed the music. Flip through by decade.")

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        FilterChip(text: "Start Here", tint: Theme.brass, selected: startersOnly, systemImage: "star.fill") {
                            startersOnly.toggle()
                        }
                        ForEach([HeardFilter.unheard, .heard, .saved]) { f in
                            FilterChip(text: f.rawValue, tint: Theme.brass, selected: heard == f) { heard = heard == f ? .all : f }
                        }
                        Rectangle().fill(Theme.panelHi).frame(width: 1, height: 22)
                        FilterChip(text: "All Styles", selected: era == nil) { era = nil }
                        ForEach(library.eras) { e in
                            FilterChip(text: e.name, tint: e.tint, selected: era == e.id) { era = (era == e.id ? nil : e.id) }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)

                if list.isEmpty {
                    ContentUnavailableView("No Records", systemImage: "opticaldisc",
                                           description: Text(heard == .all ? "None of the Start Here picks are from this style."
                                                             : "No \(heard.rawValue.lowercased()) records here yet."))
                        .padding(.top, 30)
                }

                ForEach(decades, id: \.self) { d in
                    Section {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                            ForEach(list.filter { $0.decade == d }) { AlbumCard(album: $0, width: nil) }
                        }
                        .padding(.horizontal, Theme.gutter)
                        .padding(.bottom, 10)
                    } header: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(String(d))s").font(Theme.display(34)).foregroundStyle(Theme.cream)
                            Rectangle().fill(Theme.panelHi).frame(height: 1)
                            Text("\(list.filter { $0.decade == d }.count)").font(Theme.label(11)).foregroundStyle(Theme.faint)
                        }
                        .padding(.horizontal, Theme.gutter).padding(.vertical, 6)
                        .background(Theme.ink.opacity(0.94))
                        .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .padding(.top, 8).padding(.bottom, 32)
            .animation(.easeInOut(duration: 0.25), value: list.map(\.id))
        }
        .background(Theme.ink)
        .revealedTitle("The Crate", after: 60)
        .rootToolbar()
    }
}

// MARK: - Album page

struct AlbumDetailView: View {
    let album: Album
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router
    @State private var catalog: CatalogAlbum?
    @State private var tracks: [CatalogTrack] = []
    @State private var loaded = false

    var body: some View {
        let tint = library.color(forEra: album.era)
        let era = library.era(album.era)
        let artist = library.artist(album.artist)
        let session = library.session(for: album.id)
        let more = library.albums(by: album.artist).filter { $0.id != album.id }

        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(spacing: 14) {
                    AlbumCover(album: album, size: 1000, cornerRadius: 10)
                        .frame(width: 270, height: 270)
                        .shadow(color: .black.opacity(0.65), radius: 30, y: 16)
                        .padding(.bottom, 8)
                    HStack(spacing: 8) {
                        if let era { EraChip(era: era) }
                        Text(String(album.year)).font(Theme.label(11)).foregroundStyle(Theme.muted)
                        if let label = library.label(for: album) {
                            NavigationLink(value: PhoneRoute.label(label.id)) {
                                Text("· \(album.label)").font(Theme.label(11)).foregroundStyle(label.tint).underline(color: label.tint.opacity(0.5))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("· \(album.label)").font(Theme.label(11)).foregroundStyle(Theme.muted)
                        }
                    }
                    Text(album.title.uppercased()).font(Theme.display(40)).foregroundStyle(Theme.cream)
                        .multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                    if let artist {
                        NavigationLink(value: PhoneRoute.artist(artist.id)) {
                            Text(album.artistName).font(.system(.title2, design: .serif)).italic().foregroundStyle(tint)
                        }
                        .buttonStyle(.pressable)
                    } else {
                        Text(album.artistName).font(.system(.title2, design: .serif)).italic().foregroundStyle(tint)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 110)
                .frame(maxWidth: .infinity)
                .background {
                    // The cover's own colors, blurred into a backdrop that fades into the page.
                    RemoteImage(url: catalog?.artwork(300)) { tint.opacity(0.25) }
                        .blur(radius: 50, opaque: true)
                        .opacity(0.75)
                        .overlay(LinearGradient(stops: [.init(color: Theme.ink.opacity(0.15), location: 0),
                                                        .init(color: Theme.ink.opacity(0.35), location: 0.55),
                                                        .init(color: Theme.ink, location: 1)],
                                                startPoint: .top, endPoint: .bottom))
                        .padding(.bottom, -40)
                        .clipped()
                }

                VStack(spacing: 10) {
                    AlbumPlayControls(catalog: catalog, tracks: tracks, tint: tint)
                    AlbumPassportButtons(albumID: album.id, tint: tint)
                    ShareCardButton(card: .record(album))
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.top, -12)

                TermText(text: album.why, font: .system(.body, design: .serif)) { router.go(.term($0)) }.lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Theme.gutter)

                if let session {
                    PersonnelSection(session: session, trackCount: tracks.isEmpty ? nil : tracks.count, tint: tint)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Tracklist", subtitle: album.highlights.isEmpty ? nil : "★ marks the tracks to start with.", tint: tint)
                    Group {
                        if tracks.isEmpty {
                            if loaded {
                                Text("This record isn't in the Apple Music catalog lookup. Try opening it in Music.")
                                    .font(.subheadline).foregroundStyle(Theme.muted)
                            } else {
                                ProgressView().frame(maxWidth: .infinity).padding()
                            }
                        } else {
                            TrackList(tracks: tracks, tint: tint, highlight: album.highlights)
                        }
                    }
                    .padding(.horizontal, Theme.gutter)
                }

                VStack(alignment: .leading, spacing: 4) {
                    SectionHeader(title: "Watch & Listen on YouTube", tint: tint)
                    VideoStrip(query: "\(album.artistName) \(album.title) \(album.highlights.first ?? "")", tint: tint)
                }

                if !more.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader(title: "More from \(album.artistName)", tint: tint)
                        HRow { ForEach(more) { AlbumCard(album: $0, width: 150, showArtist: false) } }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: "Where Next", subtitle: "Three doors out of this record.", tint: tint) {
                        if let era { SeeAllLink(route: .era(era.id), tint: tint) }
                    }
                    DoorsList(album: album, stacked: true, compact: true) { router.go(.album($0)) }
                        .padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .background(Theme.ink)
        .revealedTitle(album.title, after: 480)
        .task(id: album.id) {
            catalog = await ITunes.shared.album(for: album)
            if let c = catalog { tracks = await ITunes.shared.tracks(collectionId: c.collectionId) }
            loaded = true
        }
    }
}

/// Who played on the record, as liner credits, with when and where it was recorded and who was behind the glass.
/// Big bands show the first eight players and a button for the rest.
struct PersonnelSection: View {
    let session: Session
    var trackCount: Int?
    var tint: Color
    @Environment(PhoneRouter.self) private var router
    @State private var showAll = false
    private let collapsed = 8

    var body: some View {
        // Counts in the credits refer to the session's own track list; Apple Music's is the fallback.
        let count = session.tracks?.count ?? trackCount ?? 0
        let people = session.personnel
        let shown = showAll || people.count <= collapsed + 2 ? people : Array(people.prefix(collapsed))
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Personnel", subtitle: session.recordedText.map { "Recorded \($0)" }, tint: tint)
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, credit in
                    CreditRow(credit: credit, trackCount: count, tint: tint, nameSize: 11, detailSize: 14,
                              openArtist: { router.go(.artist($0)) })
                }
                if shown.count < people.count {
                    Button("Show all \(people.count)") { withAnimation(.easeInOut(duration: 0.25)) { showAll = true } }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                        .padding(.top, 2)
                }
                if let crew = session.crewText {
                    Text(crew).font(.footnote).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}
