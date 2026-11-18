import SwiftUI

/// A guided recording's form as one bar: a block per section, as wide as it lasts. Heads in cream, solos in the
/// soloist's era colour with their initials, trading in stripes of the players' colours; a playhead line glides across
/// while it plays, and clicking a block jumps there.
struct FormBar: View {
    let guide: Guide
    /// Draw the playhead (the recording playing is the one the times were taken from).
    var synced = false
    var height: CGFloat = 34
    var showLabels = true
    var onJump: ((Int) -> Void)? = nil
    @Environment(JazzLibrary.self) private var library
    @Environment(PlayerController.self) private var player
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if guide.isTimed, let duration = guide.duration {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .topLeading) {
                    ForEach(Array(guide.sections.indices), id: \.self) { i in
                        if let span = guide.span(of: i) {
                            block(i, width: max(1, (span.upperBound - span.lowerBound) / duration * w - 2))
                                .offset(x: span.lowerBound / duration * w)
                        }
                    }
                    ForEach(Array(guide.sections.enumerated()), id: \.offset) { _, s in
                        ForEach(Array(s.marks.enumerated()), id: \.offset) { _, m in
                            if let at = m.at {
                                Rectangle().fill(Theme.ink.opacity(0.7)).frame(width: 2, height: height * 0.35)
                                    .offset(x: at / duration * w - 1, y: height * 0.65)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    if synced {
                        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30, paused: !player.isPlaying)) { ctx in
                            let x = min(w, max(0, player.position(at: ctx.date) / duration * w))
                            Capsule().fill(Theme.cream).frame(width: 3, height: height + 8)
                                .shadow(color: .black.opacity(0.6), radius: 2)
                                .offset(x: x - 1.5, y: -4)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: height)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("The form of \(guide.form)")
        }
    }

    private func block(_ i: Int, width: CGFloat) -> some View {
        let s = guide.sections[i]
        return Button { onJump?(i) } label: {
            ZStack {
                fill(s).clipShape(RoundedRectangle(cornerRadius: 4))
                if showLabels, width > 26 {
                    Text(shortLabel(s, width: width))
                        .font(.system(size: 10, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(textColor(s))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(onJump != nil)
        .help("\(s.label) · \(GuideTime.text(s.at ?? 0))")
        .accessibilityLabel("\(s.label), at \(GuideTime.spoken(s.at ?? 0))")
    }

    @ViewBuilder
    private func fill(_ s: GuideSection) -> some View {
        switch s.kind {
        case .head, .headOut: Theme.cream
        case .ensemble: Theme.cream.opacity(0.6)
        case .solo: tint(s.who.first)
        case .trading:
            let a = tint(s.who.first), b = tint(s.who.dropFirst().first)
            HStack(spacing: 0) { ForEach(0..<8, id: \.self) { k in (k.isMultiple(of: 2) ? a : b) } }
        case .vamp: Theme.brass.opacity(0.55)
        case .intro, .interlude, .coda: Theme.muted.opacity(0.35)
        }
    }

    private func tint(_ who: String?) -> Color {
        guard let who, let a = library.artist(who) else { return Theme.brass.opacity(0.8) }
        return library.color(forEra: a.primaryEra)
    }

    private func textColor(_ s: GuideSection) -> Color {
        switch s.kind {
        case .head, .headOut, .ensemble: return Theme.ink
        case .intro, .interlude, .coda: return Theme.cream.opacity(0.75)
        default: return Theme.ink.opacity(0.85)
        }
    }

    private func shortLabel(_ s: GuideSection, width: CGFloat) -> String {
        switch s.kind {
        case .solo, .trading:
            let names = s.who.map { library.guideName($0) }
            if width > 90, let first = names.first { return first.split(separator: " ").last.map(String.init)?.uppercased() ?? first }
            return names.map { n in n.split(separator: " ").compactMap(\.first).map(String.init).joined() }.joined(separator: "/")
        default:
            return width > 70 ? s.kind.label.uppercased() : String(s.kind.label.prefix(1))
        }
    }
}

enum GuideTime {
    /// "1:32".
    static func text(_ t: Double) -> String {
        let s = max(0, Int(t.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "1 minute 32 seconds", for VoiceOver.
    static func spoken(_ t: Double) -> String {
        let s = max(0, Int(t)), m = s / 60, r = s % 60
        let sec = "\(r) second\(r == 1 ? "" : "s")"
        return m == 0 ? sec : "\(m) minute\(m == 1 ? "" : "s") \(sec)"
    }
}
