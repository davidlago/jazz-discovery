import SwiftUI

// Liner-note credits, used by the album pages on the Mac and the iPhone.

/// A dotted line that fills the space between a name and its instruments, as on the back of an LP.
struct DottedLeader: View {
    var color: Color = Theme.faint
    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 0, y: geo.size.height - 3))
                p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height - 3))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.5, 4]))
        }
        .frame(minWidth: 12)
        .accessibilityHidden(true)
    }
}

/// One credit: "JOHN COLTRANE ······ tenor saxophone", with "not on “Blue in Green”" underneath when it applies.
/// Names with a page in the app are tinted and open it.
struct CreditRow: View {
    let credit: Credit
    let trackCount: Int
    var tint: Color = Theme.brass
    var nameSize: CGFloat = 11
    var detailSize: CGFloat = 12
    /// Dimmed while the reader points at a track this player isn't on.
    var dimmed = false
    var openArtist: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                name
                DottedLeader().frame(height: 10)
                Text(credit.instrumentsText)
                    .font(.scaled(size: detailSize))
                    .foregroundStyle(Theme.cream.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .layoutPriority(1)
            }
            if let detail = credit.tracksText(of: trackCount) {
                Text(detail)
                    .font(.scaled(size: detailSize - 1)).italic()
                    .foregroundStyle(Theme.faint)
            }
        }
        .opacity(dimmed ? 0.28 : 1)
        .animation(.easeOut(duration: 0.15), value: dimmed)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var name: some View {
        // Names keep their full size; the instruments wrap instead.
        let label = Text(credit.name.uppercased())
            .font(Theme.label(nameSize)).tracking(1.2)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
        if let id = credit.artist, let openArtist {
            Button { openArtist(id) } label: { label.foregroundStyle(tint) }
                .buttonStyle(.plain)
                .accessibilityHint("Opens \(credit.name)")
        } else {
            label.foregroundStyle(Theme.cream)
        }
    }
}
