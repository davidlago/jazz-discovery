import SwiftUI

/// Finds the Crate's records in your Last.fm history and lets you choose which to mark as heard.
struct LastFMImportView: View {
    let scrobbler: Scrobbler
    @Environment(JazzLibrary.self) private var library
    @Environment(Passport.self) private var passport
    @Environment(\.dismiss) private var dismiss
    @State private var found: [(album: Album, plays: Int)]?
    @State private var chosen: Set<String> = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Last.fm").font(Theme.display(28)).foregroundStyle(Theme.cream)
            if let error {
                Text(error).foregroundStyle(Theme.muted)
            } else if let found {
                if found.isEmpty {
                    Text("None of the Crate's records are among your most played albums on Last.fm.").foregroundStyle(Theme.muted)
                } else {
                    Text("These Crate records are among the albums you've played most. Mark the ones you've heard.")
                        .font(.callout).foregroundStyle(Theme.muted)
                    List(found, id: \.album.id) { row in
                        Toggle(isOn: Binding(get: { chosen.contains(row.album.id) },
                                             set: { if $0 { chosen.insert(row.album.id) } else { chosen.remove(row.album.id) } })) {
                            HStack(spacing: 10) {
                                AlbumCover(album: row.album, size: 100, cornerRadius: 3).frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.album.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.cream)
                                    Text("\(row.album.artistName) · \(row.plays) plays\(passport.isHeard(row.album.id) ? " · already heard" : "")")
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
                    }
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                }
            } else {
                ProgressView("Reading your Last.fm history…").frame(maxWidth: .infinity, minHeight: 120)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Mark \(chosen.count) as Heard") {
                    passport.importHeard(Array(chosen))
                    dismiss()
                }
                .buttonStyle(.borderedProminent).tint(Theme.brass).foregroundStyle(Theme.ink)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 520, height: 520)
        #endif
        .background(Theme.ink)
        .task {
            do {
                let top = try await LastFMImport.topAlbums(scrobbler)
                let m = LastFMImport.matches(top, library: library)
                found = m
                chosen = Set(m.map(\.album.id).filter { !passport.isHeard($0) })
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
