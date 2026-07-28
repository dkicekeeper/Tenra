//
//  MiniProportionBar.swift
//  Tenra
//
//  Horizontal stacked composition bar for insight feed cards (2026-07 visual
//  refresh): how a total splits into parts — the recurring cost card shows the
//  top subscriptions + "other". Takes the same `[DonutSlice]` as MiniDonut /
//  OrbChart so callers reuse one slice-building path.
//
//  A donut would also say "composition", but at 120×60 a donut next to the
//  wealth card's donut makes two adjacent cards read identically — the flat
//  bar keeps the feed visually diverse while using the same grammar.
//
//  No text inside (localization-free, decorative for VoiceOver).
//

import SwiftUI

struct MiniProportionBar: View {
    let segments: [DonutSlice]

    var barHeight: CGFloat = 10
    var segmentGap: CGFloat = 2
    var height: CGFloat = 60

    var body: some View {
        GeometryReader { geo in
            let total = segments.reduce(0.0) { $0 + $1.amount }
            if total > 0 {
                // Every intermediate is explicitly typed. As one fused expression this
                // mixed CGFloat, Double and literals across max/*/-//, and the constraint
                // solver spent 3.56s type-checking this body on every build (measured with
                // -warn-long-function-bodies). Annotating the steps makes it instant.
                let gapTotal: CGFloat = segmentGap * CGFloat(segments.count - 1)
                let available: CGFloat = geo.size.width - gapTotal
                let minWidth: CGFloat = barHeight / 2 // a sliver stays visible as a nub
                HStack(spacing: segmentGap) {
                    ForEach(segments) { segment in
                        let share: CGFloat = CGFloat(segment.amount / total)
                        Rectangle()
                            .fill(segment.color)
                            .frame(width: max(minWidth, available * share))
                    }
                }
                .frame(height: barHeight)
                .clipShape(Capsule())
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Previews

#Preview("Proportion — three subscriptions + other") {
    MiniProportionBar(segments: [
        DonutSlice(id: "1", amount: 9_500, color: .indigo, label: "Netflix", percentage: 48),
        DonutSlice(id: "2", amount: 5_000, color: .teal, label: "Spotify", percentage: 25),
        DonutSlice(id: "3", amount: 3_200, color: .orange, label: "iCloud", percentage: 16),
        DonutSlice(id: "other", amount: 2_100, color: AppColors.textTertiary, label: "Other", percentage: 11)
    ])
    .frame(width: 120, height: 60)
    .padding()
}

#Preview("Proportion — one dominant") {
    MiniProportionBar(segments: [
        DonutSlice(id: "1", amount: 20_000, color: .indigo, label: "Rent", percentage: 91),
        DonutSlice(id: "2", amount: 2_000, color: .teal, label: "Music", percentage: 9)
    ])
    .frame(width: 120, height: 60)
    .padding()
}
