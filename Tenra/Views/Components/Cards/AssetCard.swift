//
//  AssetCard.swift
//  Tenra
//
//  An asset in the assets list: adapter over DesignKit's HoldingCard (8.2.0). The value large,
//  rolling up as the list opens; its change over the purchase price as a trend pill with the
//  gain ("+46 000 000 ₸ since purchase"); the purchase and every valuation as the sparkline;
//  when it was valued under the name ("≈ estimate" when its depreciation counts the value down
//  since), or when it was sold with a "Sold" badge; an "Out of date" badge once the valuation
//  is older than its kind allows (AssetValuationMath.isStale). Without a purchase price there is
//  no change line.
//

import SwiftUI

struct AssetCard: View {
    let asset: Asset
    let summary: AssetValuationMath.Summary

    @Environment(\.amountsHidden) private var amountsHidden

    var body: some View {
        HoldingCard(
            iconSource: asset.displayIcon,
            title: asset.name,
            subtitle: subtitle,
            amount: summary.value,
            currency: asset.currency,
            change: change,
            history: AssetValuationMath.history(of: asset).map(\.value),
            isLive: true
        ) {
            if asset.isSold {
                Badge(String(localized: "asset.soldBadge"), color: AppColors.textSecondary)
            } else if AssetValuationMath.isStale(asset) {
                Badge(String(localized: "asset.staleBadge"), color: AppColors.warning)
            }
        }
    }

    private var subtitle: String? {
        if let soldAt = asset.soldAt {
            return String(format: String(localized: "asset.soldOn"), DateFormatters.displayDateOmittingCurrentYear(soldAt))
        }
        return Self.valuedLine(summary)
    }

    /// "Valued 16 Oct", or "≈ Estimate, valued 16 Oct" once its depreciation counts the value
    /// down since.
    static func valuedLine(_ summary: AssetValuationMath.Summary) -> String? {
        summary.valuedOn.map {
            String(
                format: summary.isEstimate ? String(localized: "asset.estimatedFrom") : String(localized: "asset.valuedOn"),
                DateFormatters.displayDateOmittingCurrentYear($0)
            )
        }
    }

    private var change: HoldingChange? {
        guard let gain = summary.gain, let percent = summary.gainPercent else { return nil }
        return HoldingChange(
            direction: AssetCard.direction(of: gain),
            percent: percent,
            caption: String(format: String(localized: "asset.gainSincePurchase"), AssetCard.signedAmount(gain, currency: asset.currency, hidden: amountsHidden))
        )
    }

    /// Up, down, or flat within half a unit.
    static func direction(of gain: Double) -> TrendBadge.Direction {
        if gain > 0.5 { return .up }
        if gain < -0.5 { return .down }
        return .flat
    }

    /// "+46 000 000 ₸" / "−1 600 000 ₸", or the hidden placeholder.
    static func signedAmount(_ amount: Double, currency: String, hidden: Bool) -> String {
        guard !hidden else { return Formatting.hiddenAmount(currency: currency) }
        let sign = amount > 0.5 ? "+" : amount < -0.5 ? "\u{2212}" : ""
        return sign + Formatting.formatCurrencySmart(abs(amount), currency: currency)
    }
}
