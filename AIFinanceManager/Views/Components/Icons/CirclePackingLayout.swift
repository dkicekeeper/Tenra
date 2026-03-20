//
//  CirclePackingLayout.swift
//  AIFinanceManager
//
//  Pure geometry: packs circles into a rectangular container.
//  No SwiftUI dependency — input diameters, output (x, y) positions.
//

import Foundation

struct PackedCircle: Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
    let diameter: CGFloat
}

enum CirclePackingLayout {

    /// Min/max circle diameters.
    static let minDiameter: CGFloat = 28
    static let maxDiameter: CGFloat = 56

    // MARK: - Public

    /// Compute diameters from amounts using linear interpolation.
    /// Returns diameters in the same order as input.
    static func diameters(for amounts: [Double]) -> [CGFloat] {
        guard !amounts.isEmpty else { return [] }
        let minAmt = amounts.min()!
        let maxAmt = amounts.max()!
        let range = maxAmt - minAmt
        if range < 0.01 {
            // All amounts equal → uniform middle size
            let mid = (minDiameter + maxDiameter) / 2
            return amounts.map { _ in mid }
        }
        return amounts.map { amt in
            let ratio = CGFloat((amt - minAmt) / range)
            return minDiameter + ratio * (maxDiameter - minDiameter)
        }
    }

    /// Pack circles into a container. Returns positions relative to container center (0,0).
    /// - Parameters:
    ///   - ids: Stable identifiers for each circle.
    ///   - diameters: Pre-computed diameters (sorted largest-first recommended).
    ///   - containerWidth: Available width.
    ///   - containerHeight: Available height.
    /// - Returns: Array of `PackedCircle` with (x, y) offsets from container center.
    static func pack(
        ids: [String],
        diameters: [CGFloat],
        containerWidth: CGFloat,
        containerHeight: CGFloat
    ) -> [PackedCircle] {
        guard !ids.isEmpty else { return [] }

        // Sort by diameter descending (pack large circles first)
        let indexed = zip(ids, diameters)
            .enumerated()
            .sorted { $0.element.1 > $1.element.1 }

        let halfW = containerWidth / 2
        let halfH = containerHeight / 2
        var placed: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []
        var result: [(index: Int, circle: PackedCircle)] = []

        for (originalIndex, (id, diameter)) in indexed {
            let r = diameter / 2
            if placed.isEmpty {
                // First circle at center
                placed.append((0, 0, r))
                result.append((originalIndex, PackedCircle(id: id, x: 0, y: 0, diameter: diameter)))
                continue
            }

            if let pos = findPosition(r: r, placed: placed, halfW: halfW, halfH: halfH) {
                placed.append((pos.x, pos.y, r))
                result.append((originalIndex, PackedCircle(id: id, x: pos.x, y: pos.y, diameter: diameter)))
            } else {
                // Shrink by 10% and retry (up to 3 attempts)
                var shrunkR = r
                var retryPos: (x: CGFloat, y: CGFloat)? = nil
                for _ in 0..<3 {
                    shrunkR *= 0.9
                    retryPos = findPosition(r: shrunkR, placed: placed, halfW: halfW, halfH: halfH)
                    if retryPos != nil { break }
                }
                if let pos = retryPos {
                    let shrunkDiameter = shrunkR * 2
                    placed.append((pos.x, pos.y, shrunkR))
                    result.append((originalIndex, PackedCircle(id: id, x: pos.x, y: pos.y, diameter: shrunkDiameter)))
                }
            }
        }

        // Restore original order
        return result.sorted { $0.index < $1.index }.map(\.circle)
    }

    // MARK: - Private

    /// Find best position for a circle of given radius among placed circles.
    private static func findPosition(
        r: CGFloat,
        placed: [(x: CGFloat, y: CGFloat, r: CGFloat)],
        halfW: CGFloat,
        halfH: CGFloat
    ) -> (x: CGFloat, y: CGFloat)? {
        var bestPos: (x: CGFloat, y: CGFloat)? = nil
        var bestDist: CGFloat = .greatestFiniteMagnitude

        let angleSteps = 24
        for p in placed {
            let touchDist = p.r + r
            for step in 0..<angleSteps {
                let angle = CGFloat(step) * (2 * .pi / CGFloat(angleSteps))
                let cx = p.x + touchDist * cos(angle)
                let cy = p.y + touchDist * sin(angle)
                guard cx - r >= -halfW, cx + r <= halfW,
                      cy - r >= -halfH, cy + r <= halfH else { continue }
                let overlaps = placed.contains { other in
                    let dx = cx - other.x
                    let dy = cy - other.y
                    let minDist = other.r + r
                    return dx * dx + dy * dy < minDist * minDist - 0.01
                }
                guard !overlaps else { continue }
                let dist = cx * cx + cy * cy
                if dist < bestDist {
                    bestDist = dist
                    bestPos = (cx, cy)
                }
            }
        }

        for i in 0..<placed.count {
            for j in (i + 1)..<placed.count {
                let positions = tangentToTwo(
                    c1: placed[i], c2: placed[j], r: r,
                    halfW: halfW, halfH: halfH, placed: placed
                )
                for pos in positions {
                    let dist = pos.x * pos.x + pos.y * pos.y
                    if dist < bestDist {
                        bestDist = dist
                        bestPos = pos
                    }
                }
            }
        }

        return bestPos
    }

    /// Find positions tangent to two existing circles simultaneously.
    private static func tangentToTwo(
        c1: (x: CGFloat, y: CGFloat, r: CGFloat),
        c2: (x: CGFloat, y: CGFloat, r: CGFloat),
        r: CGFloat,
        halfW: CGFloat,
        halfH: CGFloat,
        placed: [(x: CGFloat, y: CGFloat, r: CGFloat)]
    ) -> [(x: CGFloat, y: CGFloat)] {
        let d1 = c1.r + r
        let d2 = c2.r + r
        let dx = c2.x - c1.x
        let dy = c2.y - c1.y
        let d = sqrt(dx * dx + dy * dy)

        guard d > 0.01, d <= d1 + d2 else { return [] }

        let a = (d1 * d1 - d2 * d2 + d * d) / (2 * d)
        let hSq = d1 * d1 - a * a
        guard hSq >= 0 else { return [] }
        let h = sqrt(hSq)

        let mx = c1.x + a * dx / d
        let my = c1.y + a * dy / d
        let px = -dy / d * h
        let py = dx / d * h

        let candidates = [(mx + px, my + py), (mx - px, my - py)]
        return candidates.compactMap { (cx, cy) in
            // Bounds check
            guard cx - r >= -halfW, cx + r <= halfW,
                  cy - r >= -halfH, cy + r <= halfH else { return nil }
            // Overlap check (skip c1, c2 — we know we're tangent to them)
            let overlaps = placed.contains { other in
                let odx = cx - other.x
                let ody = cy - other.y
                let minDist = other.r + r
                return odx * odx + ody * ody < minDist * minDist - 0.01
            }
            return overlaps ? nil : (cx, cy)
        }
    }
}
