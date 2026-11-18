import SwiftUI
import MapKit

extension JazzLibrary {
    /// A place's colour: its first era's.
    func tint(for place: Place) -> Color { place.eras.first.map { color(forEra: $0) } ?? Theme.brass }
}

/// A place on the map: a disc in its era's colour, bigger for cities. Map annotations don't get the view's
/// environment on the Mac, so the colour is passed in.
struct PlacePin: View {
    let place: Place
    let tint: Color
    var selected = false

    var body: some View {
        let size: CGFloat = place.isCity ? 22 : 14
        ZStack {
            Circle().fill(tint).frame(width: size, height: size)
            Circle().strokeBorder(Theme.ink, lineWidth: 2).frame(width: size, height: size)
            if selected { Circle().strokeBorder(Theme.cream, lineWidth: 2).frame(width: size + 8, height: size + 8) }
        }
        .shadow(color: .black.opacity(0.5), radius: 3)
    }
}

/// Several places in one spot at this zoom: a disc with how many.
struct GroupPin: View {
    let count: Int
    let tint: Color

    var body: some View {
        Text("\(count)").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.ink)
            .frame(width: 28, height: 28)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
            .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 2).padding(-4))
            .shadow(color: .black.opacity(0.5), radius: 3)
    }
}

/// The map of jazz: pins for the places active in the chosen year (or all of them), cities only when zoomed out, and
/// pins that would overlap at the current zoom grouped into one numbered pin (tap it to zoom in).
struct JazzMap: View {
    let places: [Place]
    @Environment(JazzLibrary.self) private var library
    @Binding var selection: String?
    @Binding var position: MapCameraPosition
    @State private var distance: Double = 6_500_000

    var body: some View {
        let zoomedOut = distance > 400_000
        let groups = Self.groups(places.filter { !zoomedOut || $0.isCity || $0.city == nil }, distance: distance)
        Map(position: $position, selection: $selection) {
            ForEach(groups) { g in
                if g.places.count == 1, let p = g.places.first {
                    Annotation(p.name, coordinate: p.coordinate, anchor: .center) {
                        PlacePin(place: p, tint: library.tint(for: p), selected: selection == p.id)
                    }
                    .tag(p.id)
                    .annotationTitles(zoomedOut && !p.isCity ? .hidden : .automatic)
                } else {
                    Annotation("\(g.places.count) places", coordinate: g.center, anchor: .center) {
                        Button {
                            withAnimation { position = Self.camera(g.center, distance: max(1_500, distance / 4)) }
                        } label: {
                            GroupPin(count: g.places.count, tint: library.tint(for: g.places[0]))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(g.places.count) places: \(g.places.map(\.name).joined(separator: ", ")). Zoom in.")
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .preferredColorScheme(.dark)
        .onMapCameraChange(frequency: .onEnd) { ctx in
            distance = ctx.camera.distance
        }
    }

    /// Places whose pins would overlap, at a camera this far away: a grid about a fourteenth of the view wide.
    struct PlaceGroup: Identifiable {
        let id: String
        let places: [Place]
        var center: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: places.map(\.coordinate.latitude).reduce(0, +) / Double(places.count),
                                   longitude: places.map(\.coordinate.longitude).reduce(0, +) / Double(places.count))
        }
    }

    static func groups(_ places: [Place], distance: Double) -> [PlaceGroup] {
        let cell = max(0.0004, distance / 111_000 / 14)   // degrees
        var cells: [String: [Place]] = [:]
        var order: [String] = []
        for p in places {
            let key = "\(Int((p.coordinate.latitude / cell).rounded(.down)))|\(Int((p.coordinate.longitude / cell).rounded(.down)))"
            if cells[key] == nil { order.append(key) }
            cells[key, default: []].append(p)
        }
        return order.map { k in
            let ps = cells[k]!
            return PlaceGroup(id: ps.count == 1 ? ps[0].id : "group-" + ps.map(\.id).sorted().joined(separator: "+"), places: ps)
        }
    }

    static let regions: [(name: String, center: CLLocationCoordinate2D, distance: Double)] = [
        ("New Orleans", .init(latitude: 29.955, longitude: -90.072), 30_000),
        ("Chicago", .init(latitude: 41.84, longitude: -87.63), 40_000),
        ("Kansas City", .init(latitude: 39.10, longitude: -94.58), 40_000),
        ("New York", .init(latitude: 40.77, longitude: -73.97), 45_000),
        ("Los Angeles", .init(latitude: 34.0, longitude: -118.3), 90_000),
        ("Europe", .init(latitude: 48.5, longitude: 3.0), 2_800_000),
        ("The World", .init(latitude: 25, longitude: -40), 22_000_000),
    ]

    static func camera(_ center: CLLocationCoordinate2D, distance: Double) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: center, distance: distance))
    }
    static let start = camera(.init(latitude: 37.5, longitude: -88), distance: 6_500_000)
}

/// A year slider over the River's era bands, with "All years" and a play button that sweeps through time.
struct TimeSlider: View {
    @Binding var year: Int?
    @Environment(JazzLibrary.self) private var library
    @State private var sweeping: Task<Void, Never>?
    static let range = 1895...2025

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(year.map { String($0) } ?? "All years").font(Theme.display(30)).foregroundStyle(Theme.cream)
                    .contentTransition(.numericText())
                Spacer()
                Button { sweep() } label: {
                    Image(systemName: sweeping == nil ? "play.fill" : "pause.fill").frame(width: 28, height: 28)
                }
                .buttonStyle(.plain).foregroundStyle(Theme.brass)
                .accessibilityLabel(sweeping == nil ? "Sweep through the years" : "Stop")
                if year != nil {
                    Button("All years") { stop(); year = nil }.buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted)
                }
            }
            ZStack(alignment: .leading) {
                GeometryReader { geo in
                    let w = geo.size.width
                    let x = { (y: Int) in CGFloat(y - Self.range.lowerBound) / CGFloat(Self.range.count) * w }
                    ForEach(library.eras) { e in
                        Capsule().fill(e.tint.opacity(year.map { e.start <= $0 && e.end >= $0 } ?? true ? 0.85 : 0.25))
                            .frame(width: max(4, x(min(e.end, 2025)) - x(e.start)), height: 5)
                            .offset(x: x(e.start), y: 18)
                    }
                }
                .frame(height: 28)
                Slider(value: Binding(get: { Double(year ?? Self.range.upperBound) },
                                      set: { stop(); year = Int($0) }),
                       in: Double(Self.range.lowerBound)...Double(Self.range.upperBound), step: 1)
                    .tint(.clear)
                    .accessibilityLabel("Year")
                    .accessibilityValue(year.map { String($0) } ?? "All years")
            }
        }
    }

    private func stop() { sweeping?.cancel(); sweeping = nil }

    /// About forty seconds from 1895 to now.
    private func sweep() {
        if sweeping != nil { stop(); return }
        let startYear = (year ?? Self.range.lowerBound) >= Self.range.upperBound ? Self.range.lowerBound : (year ?? Self.range.lowerBound)
        sweeping = Task { @MainActor in
            var y = startYear
            while y <= Self.range.upperBound, !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.25)) { year = y }
                try? await Task.sleep(for: .milliseconds(300))
                y += 1
            }
            sweeping = nil
        }
    }
}

/// A place in a list: icon, name, what it is and its years.
struct PlaceRow: View {
    let place: Place
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: place.symbol).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.ink).frame(width: 30, height: 30)
                .background(Circle().fill(library.tint(for: place)))
            VStack(alignment: .leading, spacing: 1) {
                Text(place.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                Text("\(place.kindLabel) · \(place.years)").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// A place's page: what it is, a small map, its rooms, who was there and what was recorded there.
struct PlaceDetailContent: View {
    let place: Place
    var compact = false
    var openPlace: (String) -> Void
    var openArtist: (String) -> Void
    var openAlbum: (String) -> Void
    var openEra: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let tint = library.tint(for: place)
        let rooms = library.places(in: place.id)
        let made = library.albums(recordedAt: place.id)
        let people = library.artists(at: place.id)
        let city = place.city.flatMap { library.place($0) }
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(place.kindLabel.uppercased(), systemImage: place.symbol).font(Theme.label(11)).tracking(1.4).foregroundStyle(tint)
                    if let city {
                        Button("· \(city.name.uppercased())") { openPlace(city.id) }.buttonStyle(.plain)
                            .font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.muted)
                    }
                }
                Text(place.name.uppercased()).font(Theme.display(compact ? 44 : 64)).foregroundStyle(Theme.cream)
                    .lineLimit(2).minimumScaleFactor(0.5)
                Text(place.years).font(Theme.serif(18)).italic().foregroundStyle(Theme.muted)
            }
            Map(initialPosition: JazzMap.camera(place.coordinate, distance: place.isCity ? 60_000 : 3_000), interactionModes: []) {
                Annotation(place.name, coordinate: place.coordinate) { PlacePin(place: place, tint: tint, selected: true) }
                ForEach(rooms) { r in Annotation(r.name, coordinate: r.coordinate) { PlacePin(place: r, tint: library.tint(for: r)) } }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .preferredColorScheme(.dark)
            .frame(height: compact ? 180 : 240)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomTrailing) {
                Button { openInMaps() } label: {
                    Label("Open in Maps", systemImage: "map").font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain).padding(10)
            }
            Text(place.summary).font(.system(size: compact ? 16 : 17, design: .serif)).lineSpacing(4)
                .foregroundStyle(Theme.cream.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 700, alignment: .leading)
            if let station = Programmer.station(id: "place-\(place.id)", library: library) { PlayRadioButton(station: station) }
            FlowLayout(spacing: 8) {
                ForEach(place.eras.compactMap { library.era($0) }) { e in
                    Button { openEra(e.id) } label: {
                        Text(e.name).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 5)
                            .foregroundStyle(e.tint).background(Capsule().fill(e.tint.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
            if !rooms.isEmpty {
                section("The Rooms") {
                    ForEach(rooms) { r in Button { openPlace(r.id) } label: { PlaceRow(place: r) }.buttonStyle(.plain) }
                }
            }
            if !people.isEmpty {
                section("Who Was Here") {
                    FlowLayout(spacing: 8) {
                        ForEach(people) { a in
                            Button { openArtist(a.id) } label: {
                                HStack(spacing: 7) {
                                    ArtistPortrait(artist: a, tint: library.color(forEra: a.primaryEra))
                                        .frame(width: 28, height: 28).clipShape(Circle())
                                    Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.cream)
                                }
                                .padding(.trailing, 10).padding(3)
                                .background(Capsule().fill(Theme.panel))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !made.isEmpty {
                section(place.isCity ? "Made Here" : "Recorded Here") {
                    FlowLayout(spacing: 10) {
                        ForEach(made) { a in
                            Button { openAlbum(a.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    AlbumCover(album: a, size: 300, cornerRadius: 4).frame(width: 110, height: 110)
                                    Text(a.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.cream).lineLimit(1)
                                    Text("\(a.artistName) · \(String(a.year))").font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                                .frame(width: 110, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let w = place.wikipedia {
                Text("Text by the app; place details from Wikipedia (\(w.replacingOccurrences(of: "_", with: " ").removingPercentEncoding ?? w)).")
                    .font(.system(size: 11)).foregroundStyle(Theme.faint)
            }
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(library.tint(for: place)).frame(width: 22, height: 4)
                Text(title.uppercased()).font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
            }
            content()
        }
    }

    private func openInMaps() {
        let item: MKMapItem
        if #available(macOS 26, iOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: place.lat, longitude: place.lon), address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
        }
        item.name = place.name
        item.openInMaps()
    }
}

/// A label as a card: its name on its colour, records and years.
struct LabelCard: View {
    let label: LabelInfo
    var width: CGFloat? = 220
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let albums = library.albums(onLabel: label.id)
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(Color.black)
                if let url = label.logoURL {
                    // The logo on a cream centre label, like the paper on a record; multiply melts a white backdrop
                    // into the cream.
                    GeometryReader { geo in
                        let side = geo.size.width
                        ZStack {
                            Circle().fill(Theme.cream).padding(side * 0.12)
                            RemoteImage(url: url, contentMode: .fit) {
                                Text(label.name.uppercased()).font(Theme.display(20)).foregroundStyle(Theme.ink)
                                    .lineLimit(1).minimumScaleFactor(0.5)
                            }
                            .blendMode(.multiply)
                            .frame(width: side * 0.5, height: side * 0.5)
                        }
                        .frame(width: side, height: side)
                        .compositingGroup()
                    }
                } else {
                    Circle().fill(label.tint).padding(26)
                    Text(label.name.uppercased()).font(Theme.display(22)).foregroundStyle(Theme.cream)
                        .shadow(color: .black.opacity(0.4), radius: 2).lineLimit(1).minimumScaleFactor(0.5).padding(.horizontal, 34)
                    Circle().fill(Theme.ink).frame(width: 8, height: 8).offset(y: 22)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel(label.name)
            Text(label.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
            Text("Since \(String(label.founded)) · \(albums.count) record\(albums.count == 1 ? "" : "s") in the Crate")
                .font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .frame(width: width)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .contentShape(Rectangle())
    }
}

/// A label's page: its story, sound and look, the people behind it, its wall of covers and its regulars.
struct LabelDetailContent: View {
    let label: LabelInfo
    var compact = false
    var openArtist: (String) -> Void
    var openAlbum: (String) -> Void
    var openPlace: (String) -> Void
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let albums = library.albums(onLabel: label.id)
        let regulars = library.regulars(onLabel: label.id)
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SINCE \(String(label.founded))\(label.city.flatMap { library.place($0)?.name }.map { " · \($0.uppercased())" } ?? "")")
                        .font(Theme.label(11)).tracking(1.4).foregroundStyle(Theme.cream.opacity(0.8))
                    Text(label.name.uppercased()).font(Theme.display(compact ? 54 : 80)).foregroundStyle(Theme.cream)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                Spacer(minLength: 0)
                if let url = label.logoURL {
                    RemoteImage(url: url, contentMode: .fit) { Color.clear }
                        .blendMode(.multiply)
                        .padding(compact ? 10 : 14)
                        .frame(width: compact ? 92 : 150, height: compact ? 92 : 150)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.cream))
                        .compositingGroup()
                        .accessibilityLabel("\(label.name) logo")
                }
            }
            .padding(compact ? 18 : 28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(label.tint.gradient))

            if let station = Programmer.station(id: "label-\(label.id)", library: library) { PlayRadioButton(station: station) }
            ForEach(label.summary.components(separatedBy: "\n\n"), id: \.self) { p in
                Text(p).font(.system(size: compact ? 16 : 17, design: .serif)).lineSpacing(4)
                    .foregroundStyle(Theme.cream.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 700, alignment: .leading)
            }
            let cols = compact ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: 18) {
                note("The Sound", label.sound)
                note("The Look", label.look)
            }
            .frame(maxWidth: 900)
            if !label.people.isEmpty {
                section("The People") {
                    ForEach(label.people, id: \.name) { p in
                        HStack(spacing: 8) {
                            Text(p.name.uppercased()).font(Theme.label(12)).tracking(1.2).foregroundStyle(Theme.cream)
                            DottedLeader().frame(height: 10)
                            if let place = p.place.flatMap({ library.place($0) }) {
                                Button(p.role) { openPlace(place.id) }.buttonStyle(.plain)
                                    .font(.system(size: 13)).foregroundStyle(label.tint)
                            } else {
                                Text(p.role).font(.system(size: 13)).foregroundStyle(Theme.muted)
                            }
                        }
                        .frame(maxWidth: 560)
                    }
                }
            }
            section("The Wall") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 96 : 120), spacing: 6)], spacing: 6) {
                    ForEach(albums) { a in
                        Button { openAlbum(a.id) } label: { AlbumCover(album: a, size: 300, cornerRadius: 2).aspectRatio(1, contentMode: .fit) }
                            .buttonStyle(.plain)
                            .help("\(a.title), \(a.artistName), \(String(a.year))")
                            .accessibilityLabel("\(a.title) by \(a.artistName), \(String(a.year))")
                    }
                }
            }
            if !regulars.isEmpty {
                section("Regulars") {
                    FlowLayout(spacing: 8) {
                        ForEach(regulars, id: \.artist.id) { r in
                            Button { openArtist(r.artist.id) } label: {
                                Text("\(r.artist.name) · \(r.records)").font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .foregroundStyle(Theme.cream).background(Capsule().fill(Theme.panelHi))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func note(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.label(11)).tracking(1.4).foregroundStyle(label.tint)
            Text(text).font(.system(size: 14, design: .serif)).foregroundStyle(Theme.cream.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle().fill(label.tint).frame(width: 22, height: 4)
                Text(title.uppercased()).font(Theme.label(13)).tracking(1.6).foregroundStyle(Theme.cream)
            }
            content()
        }
    }
}
