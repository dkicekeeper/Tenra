//
//  LoansCardView.swift
//  AIFinanceManager
//
//  Summary card for Home screen showing total debt,
//  monthly payment, and active loans count.
//

import SwiftUI

struct LoansCardView: View {
    let loansViewModel: LoansViewModel
    let transactionsViewModel: TransactionsViewModel

    private var loans: [Account] {
        loansViewModel.loans
    }

    private var baseCurrency: String {
        transactionsViewModel.appSettings.baseCurrency
    }

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text(String(localized: "loan.listTitle", defaultValue: "Loans"))
                    .font(AppTypography.h3)
                    .foregroundStyle(.primary)

                if loans.isEmpty {
                    EmptyStateView(
                        title: String(
                            localized: "loan.emptyTitle",
                            defaultValue: "No Loans"
                        ),
                        style: .compact
                    )
                } else {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        FormattedAmountText(
                            amount: totalDebt,
                            currency: baseCurrency,
                            fontSize: AppTypography.h2,
                            fontWeight: .bold,
                            color: AppColors.textPrimary
                        )

                        Text(String(format: String(localized: "loan.activeCount", defaultValue: "%d active loans"), loans.count))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !loans.isEmpty {
                loanIcons
                    .frame(width: AppSize.subscriptionCardWidth, alignment: .top)
            }
        }
        .padding(AppSpacing.lg)
        .cardStyle()
    }

    // MARK: - Computed

    private var totalDebt: Double {
        loans.compactMap { $0.loanInfo?.remainingPrincipal }
            .reduce(Decimal(0), +)
            .toDouble()
    }

    // MARK: - Icons

    private var loanIcons: some View {
        LoanFacepileIconsView(loans: loans)
    }
}

// MARK: - Facepile

private struct LoanFacepileIconsView: View {
    let loans: [Account]
    var maxVisible: Int = 5

    private let iconSize: CGFloat = 48
    private let overlap: CGFloat = 12
    private let borderWidth: CGFloat = 2

    private var visible: [Account] { Array(loans.prefix(maxVisible)) }
    private var overflowCount: Int { max(0, loans.count - maxVisible) }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, loan in
                LoanFacepileIcon(
                    loan: loan,
                    size: iconSize,
                    borderWidth: borderWidth,
                    animationDelay: Double(index) * 0.06
                )
                .zIndex(Double(maxVisible - index))
            }
            if overflowCount > 0 {
                LoanOverflowBadge(
                    count: overflowCount,
                    size: iconSize,
                    borderWidth: borderWidth,
                    animationDelay: Double(visible.count) * 0.06
                )
                .zIndex(0)
            }
        }
    }
}

private struct LoanFacepileIcon: View {
    let loan: Account
    let size: CGFloat
    let borderWidth: CGFloat
    let animationDelay: Double

    @State private var appeared = false

    private var iconStyle: IconStyle {
        switch loan.iconSource {
        case .sfSymbol:
            return .circle(size: size, tint: .accentMonochrome, backgroundColor: AppColors.surface)
        case .brandService, .none:
            return .circle(size: size, tint: .original)
        }
    }

    var body: some View {
        IconView(source: loan.iconSource, style: iconStyle)
            .overlay(Circle().stroke(.background, lineWidth: borderWidth))
            .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .animation(
                AppAnimation.isReduceMotionEnabled
                    ? .linear(duration: 0)
                    : .spring(response: 0.4, dampingFraction: 0.7).delay(animationDelay),
                value: appeared
            )
            .task { appeared = true }
    }
}

private struct LoanOverflowBadge: View {
    let count: Int
    let size: CGFloat
    let borderWidth: CGFloat
    let animationDelay: Double

    @State private var appeared = false

    var body: some View {
        ZStack {
            Circle().fill(.quaternary)
            Text("+\(count)")
                .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(.background, lineWidth: borderWidth))
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .scaleEffect(appeared ? 1 : 0.5)
        .opacity(appeared ? 1 : 0)
        .animation(
            AppAnimation.isReduceMotionEnabled
                ? .linear(duration: 0)
                : .spring(response: 0.4, dampingFraction: 0.7).delay(animationDelay),
            value: appeared
        )
        .task { appeared = true }
    }
}

// MARK: - Decimal Helper

private extension Decimal {
    func toDouble() -> Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

// MARK: - Previews

#Preview("Loans Card") {
    let coordinator = AppCoordinator()

    LoansCardView(
        loansViewModel: coordinator.loansViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .padding()
}

#Preview("Loans Card - Empty") {
    let coordinator = AppCoordinator()

    LoansCardView(
        loansViewModel: coordinator.loansViewModel,
        transactionsViewModel: coordinator.transactionsViewModel
    )
    .padding()
}
