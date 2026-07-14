//
//  DominantColorExtractor.swift
//  Tenra
//
//  Extracts a brand-accent colour from a logo image for ambient glow tints
//  (see AccentGlow.swift). Histogram-based, NOT an area average — averaging
//  a multicolour logo produces muddy brown; instead pixels are quantized
//  into buckets and the most frequent *saturated* bucket wins.
//
//  Pixels that can't carry a brand accent are filtered out first:
//  near-white (logo backgrounds/paper), near-black, low-saturation grays
//  and transparent pixels. If nothing survives (pure black/white marks)
//  the extractor returns nil and the caller falls back to AppColors.accent.
//
//  Extraction runs off MainActor (Task.detached) on a 24×24 downsample —
//  one-shot per domain, results cached in-memory (logos are immutable per
//  domain; LogoDiskCache.cacheVersion is the escape hatch).
//

import UIKit
import SwiftUI

enum DominantColorExtractor {

    /// Dominant colours keyed by resolved logo domain.
    private static let cache = NSCache<NSString, UIColor>()

    /// Resolves the accent colour for a brand logo via `LogoService`.
    /// Returns `nil` when no logo is available or the logo has no usable
    /// saturated pixels — callers keep their fallback tint in that case.
    static func accentColor(forBrand brandName: String) async -> Color? {
        let normalized = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let domain = ServiceLogoRegistry.resolveDomain(from: normalized)
        let key = domain as NSString
        if let cached = cache.object(forKey: key) {
            return Color(uiColor: cached)
        }

        guard let image = await LogoService.shared.logoImage(brandName: normalized),
              let cgImage = image.cgImage else { return nil }

        let extracted = await Task.detached(priority: .userInitiated) {
            dominantColor(in: cgImage)
        }.value

        guard let extracted else { return nil }
        cache.setObject(extracted, forKey: key)
        return Color(uiColor: extracted)
    }

    // MARK: - Extraction (off-MainActor)

    /// Downsample side — 576 pixels is plenty for a dominant-bucket vote.
    private static let sampleSide = 24
    /// Minimum pixels the winning bucket must hold (~2% of the sample) so a
    /// stray antialiased edge can't dictate the glow colour.
    private static let minBucketCount = 12

    nonisolated static func dominantColor(in image: CGImage) -> UIColor? {
        let side = sampleSide
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        // Accumulate per 4-bit-per-channel bucket so the winner can be
        // averaged back into a smooth colour instead of a quantized step.
        struct Bucket {
            var count = 0
            var r = 0.0, g = 0.0, b = 0.0
        }
        var buckets: [Int: Bucket] = [:]

        for i in 0..<(side * side) {
            let o = i * 4
            let alpha = Double(pixels[o + 3]) / 255
            guard alpha > 0.5 else { continue }

            // Un-premultiply; clamp — rounding can push components past 1.
            let r = min(Double(pixels[o]) / 255 / alpha, 1)
            let g = min(Double(pixels[o + 1]) / 255 / alpha, 1)
            let b = min(Double(pixels[o + 2]) / 255 / alpha, 1)

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let brightness = maxC
            let saturation = maxC == 0 ? 0 : (maxC - minC) / maxC

            // Filter pixels that can't carry a brand accent.
            if brightness > 0.92 && saturation < 0.25 { continue }  // near-white
            if brightness < 0.15 { continue }                        // near-black
            if saturation < 0.15 { continue }                        // grays

            let bucketKey = (Int(r * 15) << 8) | (Int(g * 15) << 4) | Int(b * 15)
            var bucket = buckets[bucketKey, default: Bucket()]
            bucket.count += 1
            bucket.r += r
            bucket.g += g
            bucket.b += b
            buckets[bucketKey] = bucket
        }

        guard let best = buckets.values.max(by: { $0.count < $1.count }),
              best.count >= minBucketCount else { return nil }

        let averaged = UIColor(
            red: best.r / Double(best.count),
            green: best.g / Double(best.count),
            blue: best.b / Double(best.count),
            alpha: 1
        )
        return normalized(averaged)
    }

    /// Normalizes the winner through HSB so glows stay vivid and readable:
    /// lift washed-out saturation, keep brightness out of both extremes.
    private nonisolated static func normalized(_ color: UIColor) -> UIColor {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return color
        }
        return UIColor(
            hue: hue,
            saturation: max(saturation, 0.5),
            brightness: min(max(brightness, 0.5), 0.85),
            alpha: 1
        )
    }
}
