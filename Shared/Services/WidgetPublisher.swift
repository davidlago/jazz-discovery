import Foundation
import WidgetKit

/// Keeps the widgets' snapshot (WidgetSnapshot) current: at launch, and a moment after the passport changes. Does
/// nothing in a build without the app group, where the widgets show only what needs no passport.
@MainActor
final class WidgetPublisher {
    private let passport: Passport
    private let library: JazzLibrary
    private var pending: Task<Void, Never>?

    init?(passport: Passport, library: JazzLibrary) {
        guard AppGroup.identifier != nil else { return nil }
        self.passport = passport
        self.library = library
        passport.onChange { [weak self] in self?.schedule() }
        publish()
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.publish()
        }
    }

    func publish() {
        if AppGroup.write(WidgetSnapshot(passport: passport, library: library)) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension WidgetSnapshot {
    @MainActor
    init(passport: Passport, library: JazzLibrary) {
        if let path = passport.currentPath(library: library) {
            let p = passport.progress(on: path, library: library)
            let next = p.next.map { library.title(of: path.stops[$0]) }
            self.path = PathState(id: path.id, title: path.title, tint: path.tint, done: p.done, total: p.total,
                                  nextTitle: next?.title ?? "", nextSubtitle: next?.subtitle ?? "")
        }
        // The stamp nearest to inking in: the unfinished era with the most heard, the earliest among equals. None
        // before anything's heard: the widget then invites you to Start Here.
        let eras = library.eras.map { ($0, passport.progress(inEra: $0.id, library: library)) }
            .filter { $0.1.total > 0 && $0.1.heard > 0 && $0.1.heard < $0.1.total }
        if let (era, p) = eras.enumerated().max(by: { a, b in
            a.element.1.heard != b.element.1.heard ? a.element.1.heard < b.element.1.heard : a.offset > b.offset
        })?.element {
            self.era = EraState(id: era.id, name: era.stampName, tint: era.color, heard: p.heard, total: p.total)
        }
        heardCount = passport.heardCount
        albumCount = library.albums.count
        heard = library.albums.map(\.id).filter { passport.isHeard($0) }
        saved = passport.savedAlbums
        savedArtists = passport.savedArtists
    }
}
