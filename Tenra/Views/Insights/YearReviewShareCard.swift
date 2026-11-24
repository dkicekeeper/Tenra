//
//  YearReviewShareCard.swift
//  Tenra
//
//  The year in review as a picture to share (docs/plan-release-1.9.md §3): DesignKit's
//  ShareCardFrame in the Stories format, rendered by its ShareCardSheet. Ten, "My 2026 in
//  Tenra", the habit's counters and the top categories by their shares. Without amounts by
//  default: shares and counts only, so the picture says nothing about the person's money; the
//  "With amounts" switch on the review's last page adds what was spent and kept and each
//  category's amount.
//
//  An image, not a screen: fixed sizes (ShareCardFrame renders 360 points at 3×), the type at
//  the default Dynamic Type size, the same dark colours in light and dark mode. Behind it the
//  cover's aurora (YearReviewPalette.cover), drawn once into the frame's photo, under its dark
//  gradient.
//

import SwiftUI
import UIKit

struct YearReviewShareCard: View {
    /// The "With amounts" switch, kept between years.
    static let amountsKey = "yearReview.shareAmounts"
    /// The App Store page, sent with the picture.
    static let appURL = "https://apps.apple.com/app/id6761530361"

    let review: YearReview
    let showsAmounts: Bool
    var categories: [CustomCategory] = []
    var accessory: CreatureAccessory? = nil
    var format: ShareCard.Format = .story

    /// The text sent with the picture: "My 2026 in Tenra" and the App Store link.
    static func message(for review: YearReview) -> String {
        String(format: String(localized: "yearReview.share.message"), String(review.year)) + " " + appURL
    }

    var body: some View {
        ShareCardFrame(format: format, brand: "Tenra", photo: Self.aurora(for: format)) {
            ParticleCreature(mood: .happy, accessory: accessory)
                .frame(width: YearReviewShareMetrics.creatureSize, height: YearReviewShareMetrics.creatureSize)
                .designKitMotion(false)

            Text(String(format: String(localized: "yearReview.share.title"), String(review.year)))
                .font(AppTypography.h1)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, AppSpacing.md)

            Grid(alignment: .leading, horizontalSpacing: AppSpacing.lg, verticalSpacing: AppSpacing.md) {
                ForEach(Array(stride(from: 0, to: stats.count, by: 2)), id: \.self) { index in
                    GridRow {
                        ShareCardStat(value: stats[index].value, title: stats[index].title)
                        if index + 1 < stats.count {
                            ShareCardStat(value: stats[index + 1].value, title: stats[index + 1].title)
                        } else {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        }
                    }
                }
            }
            .padding(.top, AppSpacing.xl)

            if !review.topCategories.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text(String(localized: "yearReview.share.categories"))
                        .font(AppTypography.caption)
                        .fontWeight(.semibold)
                        .opacity(YearReviewShareMetrics.captionOpacity)
                    ForEach(review.topCategories.prefix(YearReviewShareMetrics.categoryCount)) { category in
                        categoryRow(category)
                    }
                }
                .padding(.top, AppSpacing.xl)
            }

            Spacer(minLength: 0)
        }
        .dynamicTypeSize(.large)
    }

    /// The cover's aurora at the card's size, still and without grain, on the dark page.
    static func aurora(for format: ShareCard.Format) -> UIImage? {
        let renderer = ImageRenderer(content:
            AuroraBackground(YearReviewPalette.spots(YearReviewPalette.cover, from: 1), intensity: 1, grain: 0)
                .frame(width: format.width, height: format.height)
                .environment(\.colorScheme, .dark)
        )
        renderer.scale = ShareCard.Format.scale
        return renderer.uiImage
    }

    // MARK: - Pieces

    private func categoryRow(_ category: YearReview.CategoryTotal) -> some View {
        let color = YearReviewView.categoryStyle(category.key, in: categories).color
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(CategoryDisplay.displayName(for: category.key, type: .expense))
                    .font(AppTypography.bodySmall)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: AppSpacing.sm)
                Text(showsAmounts
                     ? Formatting.formatCurrencySmart(category.amount, currency: review.currency)
                     : NumberDisplay.percent(category.share * 100))
                    .font(AppTypography.bodySmall)
                    .monospacedDigit()
                    .opacity(YearReviewShareMetrics.captionOpacity)
            }
            ProportionBar(
                ratio: category.share,
                leftColor: color,
                rightColor: color.opacity(YearReviewShareMetrics.trackOpacity),
                height: YearReviewShareMetrics.barHeight,
                animatesOnAppear: false
            )
        }
    }

    /// The counters, two to a row: the amounts first when they are on, then the share of income
    /// kept (with income), the records, the days with one and the longest run.
    private var stats: [(value: String, title: String)] {
        var items: [(value: String, title: String)] = []
        if showsAmounts {
            items.append((Formatting.formatCurrencySmart(review.expenses, currency: review.currency),
                          String(localized: "yearReview.share.spent")))
            if review.income > 0 {
                items.append((Formatting.formatCurrencySmart(abs(review.saved), currency: review.currency),
                              review.saved >= 0
                                ? String(localized: "yearReview.share.kept")
                                : String(localized: "yearReview.share.over")))
            }
        }
        if let rate = review.savingsRate, rate > 0 {
            items.append((NumberDisplay.percent(rate * 100), String(localized: "yearReview.share.rate")))
        }
        let counters = YearReviewText.habitStats(review.habit)
        items += counters.map { ($0.value, $0.title) }
        return items
    }
}

enum YearReviewShareMetrics {
    static let creatureSize: CGFloat = 112
    static let categoryCount = 3
    static let barHeight: CGFloat = 6
    static let captionOpacity: Double = 0.7
    static let trackOpacity: Double = 0.25
}
