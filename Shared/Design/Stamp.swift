import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// An era's passport stamp: a double ring in the era's ink with its name on the curve and its years below, tilted a
/// little (always the same way for the same era). Empty, it's a faint outline; once a preview from the era has played,
/// a dashed one; as its records are heard the ink darkens; with all of them heard it's fully inked and dated.
struct StampView: View {
    let era: Era
    let heard: Int
    let sampled: Int
    let total: Int
    /// When the last record was heard, for a complete stamp.
    var completed: Date?
    var size: CGFloat = 150
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { total == 0 ? 0 : Double(heard) / Double(total) }
    private var complete: Bool { total > 0 && heard >= total }
    private var ink: Double {
        if complete { return 1 }
        if heard > 0 { return 0.45 + 0.4 * fraction }
        return sampled > 0 ? 0.4 : 0.18
    }
    /// -9° to 9°, from the era's ID.
    private var tilt: Double { Double(era.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 1000 } % 19) - 9 }

    var body: some View {
        let tint = era.tint.opacity(ink)
        ZStack {
            if complete { Circle().fill(era.tint.opacity(0.14)) }
            if heard == 0 && sampled > 0 {
                Circle().strokeBorder(tint, style: StrokeStyle(lineWidth: size * 0.022, dash: [size * 0.04, size * 0.03]))
            } else {
                Circle().strokeBorder(tint, lineWidth: size * 0.03)
            }
            Circle().strokeBorder(tint, lineWidth: size * 0.01).padding(size * 0.075)
            // A fill that rises with the share heard: the ink soaking in.
            if heard > 0 && !complete {
                Circle().fill(era.tint.opacity(0.10)).padding(size * 0.085)
                    .mask(alignment: .bottom) {
                        Rectangle().frame(height: size * CGFloat(fraction))
                    }
            }
            ArcText(text: era.stampName.uppercased(), radius: size * 0.335, fontSize: size * 0.085, tint: tint)
            VStack(spacing: size * 0.01) {
                if complete {
                    Image(systemName: "star.fill").font(.system(size: size * 0.13)).foregroundStyle(tint)
                    if let completed {
                        Text(completed.formatted(.dateTime.month(.abbreviated).day().year()).uppercased())
                            .font(Theme.label(size * 0.06, fixed: true)).foregroundStyle(tint)
                    }
                } else {
                    Text("\(heard)").font(Theme.display(size * 0.24, fixed: true)).foregroundStyle(tint)
                    Text("OF \(total)").font(Theme.label(size * 0.065, fixed: true)).tracking(1).foregroundStyle(tint)
                }
            }
            .offset(y: -size * 0.02)
            Text("\(String(era.start))–\(era.end >= 2020 ? "" : String(era.end))")
                .font(Theme.label(size * 0.065, fixed: true)).tracking(1).foregroundStyle(tint)
                .offset(y: size * 0.3)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(tilt))
        .scaleEffect(complete && !reduceMotion ? 1 : 0.98)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.5), value: complete)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(era.name): \(heard) of \(total) records heard")
    }
}

/// Text set along the top of a circle, letter by letter.
struct ArcText: View {
    let text: String
    let radius: CGFloat
    let fontSize: CGFloat
    let tint: Color

    var body: some View {
        let letters = Array(text)
        let widths = letters.map { Self.width(of: $0, size: fontSize) }
        let total = widths.reduce(0, +)
        // Long names squeeze to fit the top 150° of the ring.
        let maxArc = radius * .pi * 150 / 180
        let scale = min(1, maxArc / max(total, 1))
        // Each letter's centre, as an angle from the top.
        let angles = widths.indices.map { i in (widths[..<i].reduce(0, +) + widths[i] / 2 - total / 2) * scale / radius }
        return ZStack {
            ForEach(Array(letters.enumerated()), id: \.offset) { i, ch in
                Text(String(ch))
                    .font(Theme.label(fontSize * scale, fixed: true))
                    .foregroundStyle(tint)
                    .offset(y: -radius)
                    .rotationEffect(.radians(Double(angles[i])))
            }
        }
    }

    /// A letter's advance in the label font (semibold, expanded), plus a little tracking.
    static func width(of ch: Character, size: CGFloat) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: size, weight: .semibold, width: .expanded)
        #else
        let font = UIFont.systemFont(ofSize: size, weight: .semibold, width: .expanded)
        #endif
        return (String(ch) as NSString).size(withAttributes: [.font: font]).width + size * 0.06
    }
}

extension Passport {
    /// When an era's last record was heard, if all of them are.
    func completed(era id: String, library: JazzLibrary) -> Date? {
        let albums = library.albums(inEra: id)
        guard !albums.isEmpty, albums.allSatisfy({ isHeard($0.id) }) else { return nil }
        return albums.compactMap { mark($0.id)?.heard?.at }.max()
    }

    /// The share of each decade's records heard.
    func decadeProgress(library: JazzLibrary) -> [(decade: Int, heard: Int, total: Int)] {
        Dictionary(grouping: library.albums, by: \.decade).keys.sorted().map { d in
            let albums = library.albums.filter { $0.decade == d }
            return (d, albums.filter { isHeard($0.id) }.count, albums.count)
        }
    }

    /// The instruments heard most, from who played on the records you've heard.
    func instrumentsHeard(library: JazzLibrary, limit: Int = 8) -> [(instrument: String, records: Int)] {
        var counts: [String: Int] = [:]
        for album in library.albums where isHeard(album.id) {
            guard let session = library.session(for: album.id) else { continue }
            let instruments = Set(session.personnel.flatMap(\.instruments).map(Self.family))
            for i in instruments { counts[i, default: 0] += 1 }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map { ($0.key, $0.value) }
    }

    /// "tenor saxophone" and "alto saxophone" both count as saxophone; "piano" stays piano.
    nonisolated static func family(_ instrument: String) -> String {
        let i = instrument.lowercased()
        for f in ["saxophone", "trumpet", "trombone", "clarinet", "flute", "guitar", "piano", "organ", "bass", "drums",
                  "vibraphone", "vocal", "percussion", "cornet", "violin", "harp"] where i.contains(f) {
            return f == "vocal" ? "vocals" : f
        }
        return i
    }
}

/// An era's stamp with its progress read from the passport.
struct EraStamp: View {
    let era: Era
    var size: CGFloat = 150
    @Environment(Passport.self) private var passport
    @Environment(JazzLibrary.self) private var library

    var body: some View {
        let p = passport.progress(inEra: era.id, library: library)
        StampView(era: era, heard: p.heard, sampled: p.sampled, total: p.total,
                  completed: passport.completed(era: era.id, library: library), size: size)
    }
}
