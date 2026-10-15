//
//  SavingsRateHeroCard.swift
//  Tenra
//
//  The top of the savings-rate insight detail, edge to edge: DesignKit's
//  `ScoreGaugeCard(value:unit:)` in the `.hero` style (4.3.0). The rate of the last completed
//  month on a 0–40% scale (wider when the rate is above it), the 10% and 20% bands marked,
//  "12.4%" decoding itself as the screen opens, the band in a capsule and the saved amount
//  under it, on a gradient of the severity colour that reaches under the navigation bar.
//  Replaces the detail's header and its half gauge for this insight.
//

import SwiftUI

struct SavingsRateHeroCard: View {
    /// Percent of income saved; below 0 when spending exceeded income.
    let rate: Double
    /// The insight's severity colour.
    let color: Color
    /// The saved amount and the month (the insight's subtitle).
    let subtitle: String
    /// Holds the entrance until the zoom transition into the detail has finished.
    var entranceDelay: Double = 0

    var body: some View {
        ScoreGaugeCard(
            value: rate,
            fractionDigits: 1,
            unit: "%",
            maxScore: Self.scale(for: rate),
            zoneTicks: [10, 20],
            grade: Self.band(for: rate),
            color: color,
            subtitle: subtitle,
            // The rate decodes itself as the screen opens.
            decodesScore: true,
            style: .hero,
            entranceDelay: entranceDelay
        )
    }

    /// 0–40%, or a little past the rate when it is higher, so the knob never sits at the end.
    static func scale(for rate: Double) -> Double {
        max(40, rate * 1.15)
    }

    /// The band the rate falls in, on the 10% and 20% marks (the same bounds as the
    /// insight's recommendation).
    static func band(for rate: Double) -> String {
        if rate >= 20 { return String(localized: "insights.savingsRate.band.onTarget") }
        if rate >= 10 { return String(localized: "insights.savingsRate.band.belowTarget") }
        if rate >= 0 { return String(localized: "insights.savingsRate.band.low") }
        return String(localized: "insights.savingsRate.band.deficit")
    }
}

// MARK: - Previews

#Preview("Below target") {
    ScrollView {
        SavingsRateHeroCard(rate: 12.4, color: AppColors.warning, subtitle: "66 000 ₸, September 2026")
    }
}

#Preview("On target") {
    ScrollView {
        SavingsRateHeroCard(rate: 27.8, color: AppColors.success, subtitle: "148 000 ₸, September 2026")
    }
}

#Preview("Deficit") {
    ScrollView {
        SavingsRateHeroCard(rate: -6.2, color: AppColors.destructive, subtitle: "0 ₸, September 2026")
    }
}
