import SwiftUI

// Shared by the Mac and iPhone apps.

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW, x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// A chronological network: x = when each artist came of age, y = settled by a force
/// simulation so collaborators cluster together.
struct GraphLayout: Sendable {
    var positions: [String: CGPoint]
    var edges: [(String, String)]
    var size: CGSize
    var firstYear: Int
    var pxPerYear: CGFloat
    var leftPad: CGFloat

    var decades: [Int] { Array(stride(from: firstYear / 10 * 10 + 10, through: 2020, by: 10)) }
    func x(forYear y: Int) -> CGFloat { leftPad + CGFloat(y - firstYear) * pxPerYear }

    /// `weights` (one per edge, default 1) pull strongly tied artists closer: more records together, shorter springs.
    static func compute(artists: [Artist], edges: [(String, String)], weights: [Int]? = nil,
                        eraStarts: [String: Int]) -> GraphLayout {
        func comingOfAge(_ a: Artist) -> Double {
            if let b = a.born { return Double(b + 22) }
            return Double(eraStarts[a.primaryEra] ?? 1950)
        }
        let years = artists.map(comingOfAge)
        let first = Int((years.min() ?? 1890) - 4)
        let last = Int((years.max() ?? 2020) + 4)
        let pxPerYear: CGFloat = 26
        let leftPad: CGFloat = 80
        let top: CGFloat = 260, height: CGFloat = 820
        let width = leftPad * 2 + CGFloat(last - first) * pxPerYear

        let ids = artists.map(\.id)
        let index = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        let n = ids.count
        let targetX = artists.map { leftPad + CGFloat(comingOfAge($0) - Double(first)) * pxPerYear }
        var px = targetX
        // Deterministic pseudo-random starting heights.
        var py: [CGFloat] = ids.map { id in
            var h: UInt64 = 1469598103934665603
            for c in id.utf8 { h = (h ^ UInt64(c)) &* 1099511628211 }
            return top + CGFloat(h % 1000) / 1000 * height
        }
        let links = edges.enumerated().compactMap { i, e -> (Int, Int, CGFloat)? in
            guard let a = index[e.0], let b = index[e.1] else { return nil }
            let w = CGFloat(weights.map { $0.indices.contains(i) ? max(1, $0[i]) : 1 } ?? 1)
            return (a, b, min(1 + 0.35 * (w - 1), 2.2))
        }
        let centerY = top + height / 2
        for iter in 0..<500 {
            let cool = 1 - CGFloat(iter) / 500
            var fx = [CGFloat](repeating: 0, count: n), fy = [CGFloat](repeating: 0, count: n)
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let dx = px[i] - px[j], dy = py[i] - py[j]
                    let d2 = max(dx * dx + dy * dy, 25)
                    let d = d2.squareRoot()
                    guard d < 260 else { continue }
                    let f = 9000 / d2
                    fx[i] += f * dx / d; fy[i] += f * dy / d
                    fx[j] -= f * dx / d; fy[j] -= f * dy / d
                }
            }
            for (a, b, strength) in links {
                let dx = px[b] - px[a], dy = py[b] - py[a]
                let d = max((dx * dx + dy * dy).squareRoot(), 1)
                let f = (d - 110 / strength) * 0.03 * strength
                fx[a] += f * dx / d; fy[a] += f * dy / d
                fx[b] -= f * dx / d; fy[b] -= f * dy / d
            }
            for i in 0..<n {
                fx[i] += (targetX[i] - px[i]) * 0.25      // stay true to chronology
                fy[i] += (centerY - py[i]) * 0.008        // gentle gravity
                px[i] += max(-12, min(12, fx[i])) * cool
                py[i] += max(-12, min(12, fy[i])) * cool
                py[i] = min(max(py[i], top), top + height)
            }
        }
        var pos: [String: CGPoint] = [:]
        for i in 0..<n { pos[ids[i]] = CGPoint(x: px[i], y: py[i]) }
        return GraphLayout(positions: pos, edges: edges, size: CGSize(width: width, height: top + height + 80),
                           firstYear: first, pxPerYear: pxPerYear, leftPad: leftPad)
    }
}
