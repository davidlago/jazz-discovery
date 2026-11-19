// The App Store screenshots, framed: a kicker and a headline over each screen, in the app's own type and colours
// (the style of 10-widgets.png, which the Mac app draws). Reads the plain screens that scripts/app-store-screenshots.sh
// takes (docs/app-store/screens/iphone-<size>/) and writes the ones to upload (docs/app-store/iphone-<size>/), at the
// same pixel size, without transparency. The Mac's come from captures of the Mac app's window
// (docs/app-store/screens/mac/, named as in `macShots`) and go to docs/app-store/mac/, at 2880 × 1800.
//
//   swift scripts/app-store-art.swift
import AppKit
import SwiftUI

struct Shot {
    let name: String
    let kicker: String
    let headline: String
    let tint: String
}

// The river's colours, from the app icon.
let shots = [
    Shot(name: "01-timeline", kicker: "FROM RAGTIME TO TODAY", headline: "130 years of jazz,\nat a glance", tint: "#E8873A"),
    Shot(name: "02-era", kicker: "ERAS & STYLES", headline: "Every style, its sound\nand its people", tint: "#E3383F"),
    Shot(name: "03-artist", kicker: "183 ARTISTS", headline: "Meet the people\nwho made it", tint: "#7A5CD6"),
    Shot(name: "04-album", kicker: "176 ESSENTIAL RECORDS", headline: "Who played on\nevery record", tint: "#2D68D6"),
    Shot(name: "05-connections", kicker: "CONNECTIONS", headline: "The path between\nany two players", tint: "#36B58C"),
    Shot(name: "06-guide", kicker: "LISTENING GUIDES", headline: "Follow a recording\nas it plays", tint: "#1BD3C6"),
    Shot(name: "07-places", kicker: "PLACES & LABELS", headline: "From New Orleans\nto South London", tint: "#EAC13F"),
    Shot(name: "08-songbook", kicker: "THE SONGBOOK", headline: "One tune,\nmany versions", tint: "#E8873A"),
    Shot(name: "09-passport", kicker: "YOUR PASSPORT", headline: "Collect every era\nas you listen", tint: "#7A5CD6"),
]

// The Mac set: the iPhone's headlines over the Mac app's window (docs/app-store/screens/mac/<source>.png, captured from
// the running app, docs/app-store.md), with Radio in place of the passport (a fresh copy's passport is empty).
let macShots: [(shot: Shot, source: String)] = [
    (shots[0], "01-timeline"), (shots[1], "03-era-detail"), (shots[2], "07-artist-detail"), (shots[3], "09-album-detail"),
    (shots[4], "10-connections"), (shots[5], "25-guide"), (shots[6], "16-places"), (shots[7], "15-tune"),
    (Shot(name: "09-radio", kicker: "RADIO", headline: "Stations that tell you\nwhy each track is there", tint: "#7A5CD6"), "12-radio"),
]
let macCanvas = CGSize(width: 2880, height: 1800)

let ink = Color(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0D / 255)
let cream = Color(red: 0xF3 / 255, green: 0xED / 255, blue: 0xE2 / 255)
let brass = Color(red: 0xE9 / 255, green: 0xB9 / 255, blue: 0x49 / 255)

func color(_ hex: String) -> Color {
    var v: UInt64 = 0
    Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
    return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
}

struct Frame: View {
    let shot: Shot
    let screen: NSImage
    let size: CGSize

    var body: some View {
        let u = size.width / 1320   // sizes below are for the 6.9-inch canvas
        let shotWidth = size.width * 0.84
        ZStack(alignment: .top) {
            LinearGradient(colors: [color(shot.tint).opacity(0.38), ink.opacity(0)], startPoint: .top, endPoint: .center)
                .background(ink)
            VStack(spacing: 0) {
                Text(shot.kicker)
                    .font(.system(size: 50 * u, weight: .semibold).width(.expanded))
                    .tracking(9 * u)
                    .foregroundStyle(brass)
                    .padding(.top, 205 * u)
                Text(shot.headline)
                    .font(.system(size: 124 * u, weight: .black).width(.condensed))
                    .multilineTextAlignment(.center)
                    .lineSpacing(-6 * u)
                    .foregroundStyle(cream)
                    .padding(.top, 34 * u)
                Image(nsImage: screen)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: shotWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 74 * u, style: .continuous))
                    .padding(14 * u)
                    .background(RoundedRectangle(cornerRadius: 88 * u, style: .continuous).fill(Color.black))
                    .shadow(color: .black.opacity(0.6), radius: 50 * u, y: 24 * u)
                    .padding(.top, 70 * u)
                Spacer(minLength: 0)
            }
            .frame(width: size.width)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }
}

/// A Mac screenshot: the kicker and a one-line headline over the page, drawn as a window.
struct MacFrame: View {
    let shot: Shot
    let screen: NSImage
    let size: CGSize

    var body: some View {
        let u = size.width / 2880
        let shotWidth = size.width * 0.74
        ZStack(alignment: .top) {
            LinearGradient(colors: [color(shot.tint).opacity(0.38), ink.opacity(0)], startPoint: .top, endPoint: .center)
                .background(ink)
            VStack(spacing: 0) {
                Text(shot.kicker)
                    .font(.system(size: 44 * u, weight: .semibold).width(.expanded))
                    .tracking(8 * u)
                    .foregroundStyle(brass)
                    .padding(.top, 92 * u)
                Text(shot.headline.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 112 * u, weight: .black).width(.condensed))
                    .foregroundStyle(cream)
                    .padding(.top, 22 * u)
                Image(nsImage: screen)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: shotWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 26 * u, style: .continuous))
                    .padding(6 * u)
                    .background(RoundedRectangle(cornerRadius: 32 * u, style: .continuous).fill(Color.black))
                    .shadow(color: .black.opacity(0.6), radius: 50 * u, y: 24 * u)
                    .padding(.top, 56 * u)
                Spacer(minLength: 0)
            }
            .frame(width: size.width)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }
}

/// Writes a PNG with no alpha channel (App Store Connect wants screenshots flattened).
func writeOpaquePNG(_ image: CGImage, to url: URL) throws {
    let w = image.width, h = image.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { throw CocoaError(.fileWriteUnknown) }
    ctx.setFillColor(CGColor(red: 0x0F / 255, green: 0x0E / 255, blue: 0x0D / 255, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let flat = ctx.makeImage() else { throw CocoaError(.fileWriteUnknown) }
    let rep = NSBitmapImageRep(cgImage: flat)
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: url)
}

@MainActor
func run() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
    for size in ["6.9", "6.3"] {
        let input = root.appendingPathComponent("docs/app-store/screens/iphone-\(size)")
        let output = root.appendingPathComponent("docs/app-store/iphone-\(size)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for shot in shots {
            let src = input.appendingPathComponent("\(shot.name).png")
            guard let screen = NSImage(contentsOf: src), let rep = screen.representations.first else {
                print("missing \(src.path)"); continue
            }
            let px = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            let renderer = ImageRenderer(content: Frame(shot: shot, screen: screen, size: px))
            renderer.scale = 1
            renderer.proposedSize = ProposedViewSize(px)
            guard let image = renderer.cgImage else { print("couldn't draw \(shot.name)"); continue }
            try writeOpaquePNG(image, to: output.appendingPathComponent("\(shot.name).png"))
            print("iphone-\(size)/\(shot.name).png \(image.width)×\(image.height)")
        }
        // The widgets' shot comes from the Mac app with an alpha channel; flatten it in place.
        let widgets = output.appendingPathComponent("10-widgets.png")
        if let img = NSImage(contentsOf: widgets)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
           img.alphaInfo != .none, img.alphaInfo != .noneSkipLast, img.alphaInfo != .noneSkipFirst {
            try writeOpaquePNG(img, to: widgets)
            print("iphone-\(size)/10-widgets.png flattened")
        }
    }
    let macInput = root.appendingPathComponent("docs/app-store/screens/mac")
    let macOutput = root.appendingPathComponent("docs/app-store/mac")
    try FileManager.default.createDirectory(at: macOutput, withIntermediateDirectories: true)
    for (shot, source) in macShots {
        let src = macInput.appendingPathComponent("\(source).png")
        guard let screen = NSImage(contentsOf: src) else { print("missing \(src.path)"); continue }
        let renderer = ImageRenderer(content: MacFrame(shot: shot, screen: screen, size: macCanvas))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(macCanvas)
        guard let image = renderer.cgImage else { print("couldn't draw \(shot.name)"); continue }
        try writeOpaquePNG(image, to: macOutput.appendingPathComponent("\(shot.name).png"))
        print("mac/\(shot.name).png \(image.width)×\(image.height)")
    }
}

try MainActor.assumeIsolated { try run() }
