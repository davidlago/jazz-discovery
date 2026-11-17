import SwiftUI

enum Theme {
    static let ink = Color(hex: "#0F0E0D")
    static let panel = Color(hex: "#1A1816")
    static let panelHi = Color(hex: "#24211E")
    static let cream = Color(hex: "#F3EDE2")
    static let muted = Color(hex: "#A69E91")
    static let faint = Color(hex: "#6B655C")
    static let brass = Color(hex: "#E9B949")

    /// Blue Note–style heavy condensed display type.
    static func display(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .semibold).width(.expanded)
    }
    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        } else { r = 0.5; g = 0.5; b = 0.5 }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
