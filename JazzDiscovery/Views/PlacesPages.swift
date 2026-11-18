import SwiftUI
import MapKit

/// The map of jazz: pins by era, a time slider, a list of places grouped by city.
struct PlacesView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router
    @State private var year: Int?
    @State private var selection: String?
    @State private var position = JazzMap.start

    var body: some View {
        let shown = library.places.filter { p in year.map { p.active(in: $0) } ?? true }
        HStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                JazzMap(places: shown, selection: $selection, position: $position)
                VStack(spacing: 10) {
                    HStack(spacing: 6) {
                        ForEach(JazzMap.regions, id: \.name) { r in
                            Button(r.name) { withAnimation(.easeInOut(duration: 1)) { position = JazzMap.camera(r.center, distance: r.distance) } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                    TimeSlider(year: $year)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial))
                }
                .padding(20)
                .frame(maxWidth: 760)
            }
            List(selection: $selection) {
                let cities = shown.filter { $0.isCity || $0.city == nil }.sorted { ($0.from, $0.name) < ($1.from, $1.name) }
                ForEach(cities) { c in
                    Section {
                        PlaceRow(place: c).tag(c.id)
                        ForEach(shown.filter { $0.city == c.id }) { PlaceRow(place: $0).tag($0.id).padding(.leading, 14) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .frame(width: 300)
        }
        .background(Theme.ink)
        .navigationTitle("Places")
        .onChange(of: selection) { _, id in
            guard let id, let p = library.place(id) else { return }
            withAnimation(.easeInOut(duration: 1)) { position = JazzMap.camera(p.coordinate, distance: p.isCity ? 50_000 : 4_000) }
        }
        .toolbar {
            if let id = selection, library.place(id) != nil {
                Button("Open \(library.place(id)!.name)") { router.go(.place(id)) }
            }
        }
    }
}

struct PlaceDetailView: View {
    let place: Place
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            PlaceDetailContent(place: place, openPlace: { router.go(.place($0)) }, openArtist: { router.go(.artist($0)) },
                               openAlbum: { router.go(.album($0)) }, openEra: { router.go(.era($0)) })
                .padding(.top, 40).padding(.horizontal, 40).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle(place.name)
    }
}

/// Labels as record centre labels.
struct LabelsView: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LABELS").font(Theme.display(64)).foregroundStyle(Theme.cream)
                    Text("The companies that put the music out, and the sound and look each one gave it.")
                        .font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
                }
                .padding(.top, 30)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 24)], alignment: .leading, spacing: 28) {
                    ForEach(library.labels.sorted { library.albums(onLabel: $0.id).count > library.albums(onLabel: $1.id).count }) { l in
                        Button { router.go(.label(l.id)) } label: { LabelCard(label: l, width: nil) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 40).padding(.bottom, 50)
        }
        .background(Theme.ink)
        .navigationTitle("Labels")
    }
}

struct LabelDetailView: View {
    let label: LabelInfo
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            LabelDetailContent(label: label, openArtist: { router.go(.artist($0)) }, openAlbum: { router.go(.album($0)) },
                               openPlace: { router.go(.place($0)) })
                .padding(.top, 40).padding(.horizontal, 40).padding(.bottom, 50)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.ink)
        .navigationTitle(label.name)
    }
}
