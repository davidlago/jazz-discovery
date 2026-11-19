import SwiftUI

enum Theme {
    static let ink = Color(hex: "#0F0E0D")
    static let panel = Color(hex: "#1A1816")
    static let panelHi = Color(hex: "#24211E")
    static let cream = Color(hex: "#F3EDE2")
    static let muted = Color(hex: "#A69E91")
    static let faint = Color(hex: "#6B655C")
    static let brass = Color(hex: "#E9B949")

    /// How much larger than its designed size text is drawn: the iPhone's text size setting (Settings ▸ Display &
    /// Brightness ▸ Text Size, or Accessibility's Larger Text), as a factor of the default size. The iPhone app's root
    /// view sets it from the environment and rebuilds its pages when it changes; on the Mac, and in the widgets, it
    /// stays 1. The app's own fonts are sized in points, so they read it here rather than from a text style.
    nonisolated(unsafe) static var textScale: CGFloat = 1

    /// A designed point size at the current text size. Display type grows less than reading type: a 132-point
    /// headline that doubled would no longer fit the screen, and it's already big enough to read.
    static func scaled(_ size: CGFloat) -> CGFloat {
        guard textScale != 1 else { return size }
        let damping: CGFloat = size <= 20 ? 1 : max(0.2, 1 - (size - 20) / 50)
        return (size * (1 + (textScale - 1) * damping)).rounded()
    }

    /// Blue Note–style heavy condensed display type. `fixed` keeps the designed size whatever the text size (type
    /// drawn inside a graphic of fixed size: a stamp, a record label, a calendar page).
    static func display(_ size: CGFloat, weight: Font.Weight = .black, fixed: Bool = false) -> Font {
        .system(size: fixed ? size : scaled(size), weight: weight).width(.condensed)
    }
    static func label(_ size: CGFloat = 11, fixed: Bool = false) -> Font {
        .system(size: fixed ? size : scaled(size), weight: .semibold).width(.expanded)
    }
    static func serif(_ size: CGFloat, fixed: Bool = false) -> Font {
        .system(size: fixed ? size : scaled(size), weight: .regular, design: .serif)
    }
}

extension Font {
    /// `Font.system(size:weight:design:)` at the current text size (see `Theme.textScale`). Use `.system(size:)` itself
    /// for type that has to keep its size, inside a graphic of fixed size.
    static func scaled(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: Theme.scaled(size), weight: weight, design: design)
    }
}

extension DynamicTypeSize {
    /// The body text size at this setting, as a factor of the default (17 points at Large), capped at twice the
    /// default: past that, the app's pages, which have a lot of display type, stop fitting a phone.
    var textScale: CGFloat {
        let body: CGFloat
        switch self {
        case .xSmall: body = 14
        case .small: body = 15
        case .medium: body = 16
        case .large: body = 17
        case .xLarge: body = 19
        case .xxLarge: body = 21
        case .xxxLarge: body = 23
        case .accessibility1: body = 28
        case .accessibility2: body = 33
        case .accessibility3: body = 40
        case .accessibility4: body = 47
        case .accessibility5: body = 53
        @unknown default: body = 17
        }
        return min(body / 17, 2)
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
