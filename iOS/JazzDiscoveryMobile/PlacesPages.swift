import SwiftUI
import MapKit

/// The map of jazz, with a time slider and the places as a list under it.
struct PlacesPage: View {
    @Environment(JazzLibrary.self) private var library
    @Environment(PhoneRouter.self) private var router
    @State private var year: Int?
    @State private var selection: String?
    @State private var position = JazzMap.start

    var body: some View {
        let shown = library.places.filter { p in year.map { p.active(in: $0) } ?? true }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                JazzMap(places: shown, selection: $selection, position: $position)
                    .frame(height: 380)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, Theme.gutter)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(JazzMap.regions, id: \.name) { r in
                            Button(r.name) { withAnimation(.easeInOut(duration: 1)) { position = JazzMap.camera(r.center, distance: r.distance) } }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Theme.gutter, for: .scrollContent)
                TimeSlider(year: $year).padding(.horizontal, Theme.gutter)
                if let id = selection, let p = library.place(id) {
                    NavigationLink(value: PhoneRoute.place(p.id)) {
                        HStack { PlaceRow(place: p); Image(systemName: "chevron.right").foregroundStyle(Theme.faint) }
                            .padding(12).background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelHi))
                    }
                    .buttonStyle(.pressable)
                    .padding(.horizontal, Theme.gutter)
                }
                let cities = shown.filter { $0.isCity || $0.city == nil }.sorted { ($0.from, $0.name) < ($1.from, $1.name) }
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(cities) { c in
                        NavigationLink(value: PhoneRoute.place(c.id)) { PlaceRow(place: c) }.buttonStyle(.pressable)
                        ForEach(shown.filter { $0.city == c.id }) { r in
                            NavigationLink(value: PhoneRoute.place(r.id)) { PlaceRow(place: r) }.buttonStyle(.pressable).padding(.leading, 20)
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .navigationTitle("Places")
        .onChange(of: selection) { _, id in
            guard let id, let p = library.place(id) else { return }
            withAnimation(.easeInOut(duration: 1)) { position = JazzMap.camera(p.coordinate, distance: p.isCity ? 50_000 : 4_000) }
        }
    }
}

struct PlaceDetailView: View {
    let place: Place
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            PlaceDetailContent(place: place, compact: true, openPlace: { router.go(.place($0)) }, openArtist: { router.go(.artist($0)) },
                               openAlbum: { router.go(.album($0)) }, openEra: { router.go(.era($0)) })
                .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle(place.name, after: 100)
    }
}

struct LabelsPage: View {
    @Environment(JazzLibrary.self) private var library
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Labels", subtitle: "The companies that put the music out, and the sound and look each one gave it.")
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(library.labels.sorted { library.albums(onLabel: $0.id).count > library.albums(onLabel: $1.id).count }) { l in
                        NavigationLink(value: PhoneRoute.label(l.id)) { LabelCard(label: l, width: nil) }.buttonStyle(.pressable)
                    }
                }
                .padding(.horizontal, Theme.gutter)
            }
            .padding(.top, 8).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle("Labels", after: 60)
    }
}

struct LabelDetailView: View {
    let label: LabelInfo
    @Environment(PhoneRouter.self) private var router

    var body: some View {
        ScrollView {
            LabelDetailContent(label: label, compact: true, openArtist: { router.go(.artist($0)) }, openAlbum: { router.go(.album($0)) },
                               openPlace: { router.go(.place($0)) })
                .padding(.horizontal, Theme.gutter).padding(.top, 16).padding(.bottom, 32)
        }
        .background(Theme.ink)
        .revealedTitle(label.name, after: 100)
    }
}
