//
//  RecommendationBox.swift
//  Tenra
//
//  Tinted "lightbulb + advice" callout shared by InsightFormulaCard and
//  HealthComponentCard.
//

import SwiftUI

/// A tinted recommendation callout: an icon and a line of advice on a soft
/// `color`-tinted background. Used at the bottom of insight / health cards.
struct RecommendationBox: View {
    let text: String
    let color: Color
    var icon: String = "lightbulb.fill"

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: AppIconSize.sm))
                .foregroundStyle(color)

            Text(text)
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppSpacing.md)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
    }
}

#Preview {
    VStack(spacing: AppSpacing.md) {
        RecommendationBox(
            text: "Aim for 20%. Trim recurring subscriptions to widen the gap.",
            color: AppColors.success
        )
        RecommendationBox(
            text: "Budgets aren't configured. Set them up on your categories.",
            color: AppColors.warning
        )
    }
    .padding()
}
