// Renders the app icon: a record-sleeve tile with era-colored stripes and a big condensed "J".
// Usage: swift scripts/make-icon.swift <output-dir>          the Mac icon (icon_1024.png: an inset tile with a shadow)
//        swift scripts/make-icon.swift --ios <output-dir>    the iPhone icon (icon_ios_1024.png: full bleed, opaque;
//                                                            iOS rounds the corners itself)
import AppKit

let args = CommandLine.arguments.dropFirst()
let ios = args.contains("--ios")
let out = args.first { $0 != "--ios" } ?? "."
let size = 1024

// The iPhone icon has no alpha channel at all (App Store Connect refuses icons with one, even when opaque).
let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: ios ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
let ctx = cg

let ink = NSColor(red: 0.06, green: 0.055, blue: 0.05, alpha: 1).cgColor
let full = CGRect(x: 0, y: 0, width: size, height: size)
let rect: CGRect
// The artwork was drawn for the Mac's 824-point tile; the iPhone's fills the whole canvas, so everything scales up.
let s: CGFloat
if ios {
    rect = full
    s = CGFloat(size) / 824
    ctx.setFillColor(ink); ctx.fill(full)
} else {
    let inset: CGFloat = 100
    rect = full.insetBy(dx: inset, dy: inset)
    s = 1
    let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(path); ctx.setFillColor(ink); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(path); ctx.clip()
}

let colors = ["E8833A", "EBC03F", "E2373F", "2D66D6", "7A5BD8", "34B58C", "19D3C5"]
func hex(_ s: String) -> NSColor {
    let v = Int(s, radix: 16)!
    return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let stripeH: CGFloat = 46 * s
for (i, c) in colors.enumerated() {
    ctx.setFillColor(hex(c).cgColor)
    let w = rect.width * (0.35 + 0.09 * CGFloat(i))
    ctx.fill(CGRect(x: rect.maxX - w, y: rect.minY + 70 * s + CGFloat(i) * (stripeH + 12 * s), width: w, height: stripeH))
}
let fontSize = 560 * s
let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
let condensed = NSFontDescriptor(fontAttributes: [.traits: [NSFontDescriptor.TraitKey.width: -0.4, NSFontDescriptor.TraitKey.weight: NSFont.Weight.black]])
let f = NSFont(descriptor: font.fontDescriptor.addingAttributes(condensed.fontAttributes), size: fontSize) ?? font
let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor(red: 0.95, green: 0.93, blue: 0.886, alpha: 1)]
NSAttributedString(string: "J", attributes: attrs).draw(at: NSPoint(x: rect.minX + 70 * s, y: rect.minY + 150 * s))
NSGraphicsContext.restoreGraphicsState()

let name = ios ? "icon_ios_1024.png" : "icon_1024.png"
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out + "/" + name) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, cg.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest), "couldn't write \(name)")
