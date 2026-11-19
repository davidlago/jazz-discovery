// Checks screenshots for blank pages: `swift scripts/screen-check.swift <png>…` (ui-smoke.sh compiles it first) prints
// each one that's blank and exits 1 if any is. A page counts as blank when almost nothing in the middle of the screen (between the status bar and the
// tab bar) differs from its most common colour: a page whose content failed to show is the app's ink background.
import CoreGraphics
import Foundation
import ImageIO

func inkRatio(_ path: String) -> Double? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    // Small is enough, and quick.
    let w = 120, h = Int(Double(image.height) / Double(image.width) * 120)
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let rows = Int(Double(h) * 0.15)..<Int(Double(h) * 0.8)
    var counts: [UInt32: Int] = [:]
    var total = 0
    for y in rows {
        for x in 0..<w {
            let i = (y * w + x) * 4
            // Rounded to 16 levels a channel, so anti-aliasing and noise don't count as content.
            let c = UInt32(pixels[i] >> 4) << 8 | UInt32(pixels[i + 1] >> 4) << 4 | UInt32(pixels[i + 2] >> 4)
            counts[c, default: 0] += 1
            total += 1
        }
    }
    guard let n = counts.values.max(), total > 0 else { return nil }
    return 1 - Double(n) / Double(total)
}

var blank = false
for path in CommandLine.arguments.dropFirst() {
    guard let r = inkRatio(path) else { print("unreadable: \(path)"); blank = true; continue }
    if r < 0.02 {
        print("blank (\(String(format: "%.1f", r * 100))% content): \(path)")
        blank = true
    }
}
exit(blank ? 1 : 0)
