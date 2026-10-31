//
//  MerchantChoiceRow.swift
//  Tenra
//
//  A merchant to pick: its logo (a shop on a pale plate without one), its name and how many
//  payments, and whether it is picked. The row of the Wallet merchants list, used by
//  "Combine points" (MerchantMergeView, several) and the transaction form's merchant
//  (MerchantPickerView, one).
//

import SwiftUI

struct MerchantChoiceRow: View {
    /// The merchant as the bank wrote it (or as typed): its logo is looked up by this text.
    let merchant: String
    let title: String
    /// Payments under the name; nil hides the line.
    let count: Int?
    let isSelected: Bool
    let action: () -> Void

    /// Settings → "Merchant logos" (on by default), as on the merchant's transaction rows.
    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    var body: some View {
        Button(action: action) {
            UniversalRow(leadingIcon: Self.icon(for: merchant, showsLogos: showsMerchantLogos)) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    if let count {
                        Text(String(format: String(localized: "merchant.merge.operations"), count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            } trailing: {
                SelectionIndicator(isSelected: isSelected)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // The button keeps the row's divider inset to itself: the 44 pt tile and its space.
        .rowDividerInset(AppIconSize.Tile.sm + AppSpacing.md)
    }

    /// The merchant's logo when it has one (and logos are on), else a shop on a pale plate.
    static func icon(for merchant: String, showsLogos: Bool) -> IconConfig {
        if showsLogos, let logo = MerchantLogoStore.shared.iconSource(forDescription: merchant) {
            return .custom(
                source: logo,
                style: .circle(size: AppIconSize.Tile.sm, tint: .original, backgroundColor: AppColors.Status.neutralPale)
            )
        }
        return .custom(
            source: .sfSymbol("storefront"),
            style: .circle(
                size: AppIconSize.Tile.sm,
                tint: .monochrome(AppColors.textSecondary),
                backgroundColor: AppColors.Status.neutralPale
            )
        )
    }
}
