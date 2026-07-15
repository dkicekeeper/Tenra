//
//  PeriodBreakdownRow.swift
//  Tenra
//
//  Single period row showing net flow + income/expenses breakdown.
//  Extracted from InsightDetailView and InsightsSummaryDetailView (Phase 26).
//

import SwiftUI

/// Selects which value a period breakdown row surfaces. `.cashFlow` keeps the
/// income/expenses/net triple; the others show one metric matching the insight.
enum PeriodListMetric {
    case cashFlow
    case expenses
    case income
    case avgDailyExpenses
    case cumulativeBalance

    /// Single value to display, or nil for the cash-flow triple.
    func value(for point: PeriodDataPoint) -> Double? {
        switch self {
        case .cashFlow: return nil
        case .expenses: return point.expenses
        case .income:   return point.income
        case .avgDailyExpenses:
            let days = max(1, Calendar.current.dateComponents([.day], from: point.periodStart, to: point.periodEnd).day ?? 1)
            return point.expenses / Double(days)
        case .cumulativeBalance:
            // Running wealth at the end of the period; fall back to net flow if unset.
            return point.cumulativeBalance ?? point.netFlow
        }
    }

    var color: Color {
        switch self {
        case .income: return AppColors.success
        default:      return AppColors.textPrimary
        }
    }
}

/// One row in a period breakdown list (week / month / quarter / year).
/// Line 1: label on the left, netFlow (or `singleValue`) on the right.
/// Line 2 (cash-flow triple only): income/expenses pair, trailing-aligned,
/// spanning the full row width so large amounts never wrap.
/// - Parameter showDivider: adds a `Divider` at the bottom (InsightsSummaryDetailView)
/// - Parameter singleValue: when non-nil, render only this value instead of the triple
struct PeriodBreakdownRow: View {
    let label: String
    let income: Double
    let expenses: Double
    let netFlow: Double
    let currency: String
    var showDivider: Bool = false
    var singleValue: Double? = nil
    var singleColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    if let singleValue {
                        FormattedAmountText(
                            amount: singleValue,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .semibold,
                            color: singleColor
                        )
                    } else {
                        FormattedAmountText(
                            amount: netFlow,
                            currency: currency,
                            fontSize: AppTypography.body,
                            fontWeight: .semibold,
                            color: netFlow >= 0 ? AppColors.textPrimary : AppColors.destructive
                        )
                    }
                }

                if singleValue == nil {
                    HStack(spacing: AppSpacing.md) {
                        FormattedAmountText(
                            amount: income,
                            currency: currency,
                            prefix: "+",
                            fontSize: AppTypography.bodySmall,
                            fontWeight: .regular,
                            color: AppColors.success
                        )
                        FormattedAmountText(
                            amount: expenses,
                            currency: currency,
                            prefix: "-",
                            fontSize: AppTypography.bodySmall,
                            fontWeight: .regular,
                            color: AppColors.destructive
                        )
                    }
                }
            }
            .padding(.vertical, AppSpacing.md)

            if showDivider {
                Divider()
                    .screenPadding()
            }
        }
    }
}

// MARK: - Previews

#Preview("Without divider") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Jan 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT")
        PeriodBreakdownRow(label: "Dec 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT")
        PeriodBreakdownRow(label: "Nov 2025", income: 510_000, expenses: 540_000, netFlow: -30_000, currency: "KZT")
    }
}

#Preview("With divider") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Январь 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT", showDivider: true)
        PeriodBreakdownRow(label: "Декабрь 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT", showDivider: true)
    }
}

#Preview("Single metric") {
    VStack(spacing: 0) {
        PeriodBreakdownRow(label: "Январь 2026", income: 530_000, expenses: 320_000, netFlow: 210_000, currency: "KZT", singleValue: 320_000, singleColor: AppColors.textPrimary)
        PeriodBreakdownRow(label: "Декабрь 2025", income: 480_000, expenses: 390_000, netFlow: 90_000, currency: "KZT", singleValue: 390_000, singleColor: AppColors.textPrimary)
    }
}
