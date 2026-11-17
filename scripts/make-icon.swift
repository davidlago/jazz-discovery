// Renders the app icon: a record-sleeve tile with era-colored stripes and a big condensed "J".
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "."
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: NSColor.black.withAlphaComponent(0.45).cgColor)
ctx.addPath(path); ctx.setFillColor(NSColor(red: 0.06, green: 0.055, blue: 0.05, alpha: 1).cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(path); ctx.clip()
let colors = ["E8833A", "EBC03F", "E2373F", "2D66D6", "7A5BD8", "34B58C", "19D3C5"]
func hex(_ s: String) -> NSColor {
    let v = Int(s, radix: 16)!
    return NSColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
let stripeH: CGFloat = 46
for (i, c) in colors.enumerated() {
    ctx.setFillColor(hex(c).cgColor)
    let w = rect.width * (0.35 + 0.09 * CGFloat(i))
    ctx.fill(CGRect(x: rect.maxX - w, y: rect.minY + 70 + CGFloat(i) * (stripeH + 12), width: w, height: stripeH))
}
let font = NSFont.systemFont(ofSize: 560, weight: .black)
let condensed = NSFontDescriptor(fontAttributes: [.traits: [NSFontDescriptor.TraitKey.width: -0.4, NSFontDescriptor.TraitKey.weight: NSFont.Weight.black]])
let f = NSFont(descriptor: font.fontDescriptor.addingAttributes(condensed.fontAttributes), size: 560) ?? font
let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: NSColor(red: 0.95, green: 0.93, blue: 0.886, alpha: 1)]
NSAttributedString(string: "J", attributes: attrs).draw(at: NSPoint(x: rect.minX + 70, y: rect.minY + 150))
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out + "/icon_1024.png"))
