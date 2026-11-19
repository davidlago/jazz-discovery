import SwiftUI

// The passport's marks where you browse: a stamp on heard covers, Save and Heard buttons on album pages, and the same
// two in a cover's menu. Used by both apps.

/// A small stamp in a cover's corner: inked when the record is heard, a dashed ring when only a preview played.
struct HeardBadge: View {
    let albumID: String
    var tint: Color
    var size: CGFloat = 26
    @Environment(Passport.self) private var passport

    var body: some View {
        if passport.isHeard(albumID) {
            ZStack {
                Circle().fill(Theme.ink.opacity(0.78))
                Circle().strokeBorder(tint, lineWidth: max(1.5, size * 0.07))
                Circle().strokeBorder(tint.opacity(0.7), lineWidth: 0.8).padding(size * 0.16)
                Image(systemName: "checkmark").font(.system(size: size * 0.38, weight: .black)).foregroundStyle(tint)
            }
            .frame(width: size, height: size)
            .rotationEffect(.degrees(-12))
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
            .accessibilityLabel("Heard")
        } else if passport.isSampled(albumID) {
            Circle()
                .strokeBorder(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.5]))
                .background(Circle().fill(Theme.ink.opacity(0.55)))
                .frame(width: size, height: size)
                .accessibilityLabel("Sampled")
        }
    }
}

extension View {
    /// The heard stamp in the cover's top-right corner.
    func heardBadge(_ albumID: String, tint: Color, size: CGFloat = 26) -> some View {
        overlay(alignment: .topTrailing) {
            HeardBadge(albumID: albumID, tint: tint, size: size).padding(size * 0.25)
        }
    }
}

/// *Mark as Heard* and *Save*, for a cover's menu.
struct PassportMenuItems: View {
    let albumID: String
    @Environment(Passport.self) private var passport

    var body: some View {
        Button { passport.toggleHeard(albumID) } label: {
            passport.isHeard(albumID) ? Label("Mark as Not Heard", systemImage: "checkmark.seal.fill")
                                      : Label("Mark as Heard", systemImage: "checkmark.seal")
        }
        Button { passport.toggleSaved(albumID) } label: {
            passport.isSaved(albumID) ? Label("Remove from Saved", systemImage: "bookmark.fill")
                                      : Label("Save", systemImage: "bookmark")
        }
    }
}

/// The two buttons on an album page, beside the play controls.
struct AlbumPassportButtons: View {
    let albumID: String
    var tint: Color
    @Environment(Passport.self) private var passport
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let heard = passport.isHeard(albumID), saved = passport.isSaved(albumID)
        // One above the other at the iPhone's accessibility text sizes, where two don't fit across.
        let stack = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
        stack {
            toggle(heard ? "Heard" : "Mark as Heard", symbol: heard ? "checkmark.seal.fill" : "checkmark.seal", on: heard,
                   help: heard ? (heardHelp ?? "Heard") : "Mark this record as one you've heard") {
                passport.toggleHeard(albumID)
            }
            toggle(saved ? "Saved" : "Save", symbol: saved ? "bookmark.fill" : "bookmark", on: saved,
                   help: saved ? "Remove from your saved records" : "Save this record to your passport") {
                passport.toggleSaved(albumID)
            }
        }
    }

    private var heardHelp: String? {
        guard let flag = passport.mark(albumID)?.heard, flag.on else { return nil }
        let date = flag.at.formatted(date: .abbreviated, time: .omitted)
        switch flag.how {
        case .listening: return "Heard in the app, \(date). Click to unmark."
        case .lastFM: return "Heard on Last.fm. Click to unmark."
        default: return "Marked as heard, \(date). Click to unmark."
        }
    }

    private func toggle(_ title: String, symbol: String, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .contentTransition(.symbolEffect(.replace))
                #if os(macOS)
                .font(.scaled(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 9)
                #else
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                #endif
                .foregroundStyle(on ? tint : Theme.cream)
                .background(Capsule().fill(on ? tint.opacity(0.16) : .clear))
                .background(Capsule().strokeBorder(on ? tint.opacity(0.7) : Theme.cream.opacity(0.3)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The Crate's passport filter.
enum HeardFilter: String, CaseIterable, Identifiable {
    case all = "All", unheard = "Unheard", heard = "Heard", saved = "Saved"
    var id: String { rawValue }

    @MainActor
    func includes(_ album: Album, _ passport: Passport) -> Bool {
        switch self {
        case .all: return true
        case .unheard: return !passport.isHeard(album.id)
        case .heard: return passport.isHeard(album.id)
        case .saved: return passport.isSaved(album.id)
        }
    }
}
