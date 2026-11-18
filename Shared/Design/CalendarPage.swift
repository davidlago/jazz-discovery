import SwiftUI

/// A tear-off calendar page: the month in the label face, the day huge, a torn top edge.
struct CalendarPage: View {
    let date: Date
    var size: CGFloat = 130
    var tint: Color = Theme.brass

    var body: some View {
        VStack(spacing: 0) {
            ZigzagEdge().fill(tint).frame(height: size * 0.07)
            VStack(spacing: size * 0.02) {
                Text(date.formatted(.dateTime.month(.wide)).uppercased()).font(Theme.label(size * 0.09)).tracking(1.5)
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity).padding(.vertical, size * 0.05).background(tint)
                Text(date.formatted(.dateTime.day())).font(Theme.display(size * 0.5)).foregroundStyle(Theme.ink)
                    .padding(.top, -size * 0.02)
                Text(date.formatted(.dateTime.weekday(.wide)).uppercased()).font(Theme.label(size * 0.07)).tracking(1.2)
                    .foregroundStyle(Theme.ink.opacity(0.6)).padding(.bottom, size * 0.06)
            }
            .background(Theme.cream)
        }
        .frame(width: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        .rotationEffect(.degrees(-2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
    }
}

struct ZigzagEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let teeth = 14, w = rect.width / CGFloat(teeth)
        p.move(to: CGPoint(x: 0, y: rect.maxY))
        for i in 0..<teeth {
            p.addLine(to: CGPoint(x: CGFloat(i) * w + w / 2, y: rect.minY))
            p.addLine(to: CGPoint(x: CGFloat(i + 1) * w, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}
