// The App Store product page's header: the River of Jazz's ribbons flowing behind the app's name, in the icon's
// colours. Original art only (no photos: the portraits in the app are Wikimedia Commons images with their own credits).
// Writes docs/app-store/header-3840x1646.png and header-5244x2950.png, without transparency.
//
//   swift scripts/app-store-header.swift
import AppKit
import SwiftUI

let ink = Color(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0D / 255)
let cream = Color(red: 0xF3 / 255, green: 0xED / 255, blue: 0xE2 / 255)
let brass = Color(red: 0xE9 / 255, green: 0xB9 / 255, blue: 0x49 / 255)

func color(_ hex: String) -> Color {
    var v: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

// The icon's bands, top to bottom; each joins the river a little later, like the styles do.
let ribbons: [(hex: String, start: Double)] = [
    ("#1BD3C6", 0.00), ("#36B58C", 0.06), ("#7A5CD6", 0.13), ("#2D68D6", 0.21),
    ("#E3383F", 0.30), ("#EAC13F", 0.40), ("#E8873A", 0.50),
]

struct River: View {
    let size: CGSize
    var body: some View {
        Canvas { ctx, s in
            let band = s.height * 0.034, gap = s.height * 0.012
            let mid = s.height * 0.62
            for (i, r) in ribbons.enumerated() {
                let y0 = mid + (Double(i) - 3) * (band + gap)
                var p = Path()
                let x0 = s.width * (0.50 + r.start * 0.45)
                // Enters from below, rises into its lane, then flows to the right edge with a gentle swell.
                p.move(to: CGPoint(x: x0 - s.width * 0.08, y: s.height + band))
                p.addCurve(to: CGPoint(x: x0 + s.width * 0.06, y: y0),
                           control1: CGPoint(x: x0 - s.width * 0.03, y: s.height * 0.95),
                           control2: CGPoint(x: x0, y: y0))
                let swell = s.height * 0.05 * sin(Double(i) * 0.9)
                p.addCurve(to: CGPoint(x: s.width + band, y: y0 - s.height * 0.10),
                           control1: CGPoint(x: x0 + s.width * 0.25, y: y0 + swell),
                           control2: CGPoint(x: s.width * 0.80, y: y0 - s.height * 0.12 - swell))
                ctx.stroke(p, with: .color(color(r.hex)), style: StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .round))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct Header: View {
    let size: CGSize
    var body: some View {
        let u = min(size.width / 3840, size.height / 1646)
        ZStack(alignment: .leading) {
            ink
            RadialGradient(colors: [color("#7A5CD6").opacity(0.22), .clear], center: UnitPoint(x: 0.7, y: 0.55),
                           startRadius: 0, endRadius: size.width * 0.55)
            River(size: size)
            // The words sit in the middle third, clear of the edges where the store crops for smaller screens.
            VStack(alignment: .leading, spacing: 18 * u) {
                Text("A VISUAL HISTORY · 1895 — TODAY")
                    .font(.system(size: 64 * u, weight: .semibold).width(.expanded))
                    .tracking(12 * u)
                    .foregroundStyle(brass)
                Text("JAZZ")
                    .font(.system(size: 620 * u, weight: .black).width(.condensed))
                    .foregroundStyle(cream)
                    .shadow(color: ink.opacity(0.8), radius: 30 * u)
                    .padding(.top, -60 * u)
                Text("14 eras · 152 artists · 130 essential records")
                    .font(.system(size: 76 * u, weight: .regular, design: .serif)).italic()
                    .foregroundStyle(cream.opacity(0.85))
                    .padding(.top, -70 * u)
            }
            .padding(.leading, size.width * 0.17)
            .padding(.bottom, size.height * 0.10)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }
}

func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

@MainActor
func run() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
    for (w, h) in [(3840, 1646), (5244, 2950)] {
        let size = CGSize(width: w, height: h)
        let r = ImageRenderer(content: Header(size: size))
        r.scale = 1
        r.proposedSize = ProposedViewSize(size)
        guard let img = r.cgImage else { print("couldn't draw \(w)×\(h)"); continue }
        let url = root.appendingPathComponent("docs/app-store/header-\(w)x\(h).png")
        try writeOpaquePNG(img, to: url)
        print("\(url.lastPathComponent) \(img.width)×\(img.height)")
    }
}

try MainActor.assumeIsolated { try run() }
