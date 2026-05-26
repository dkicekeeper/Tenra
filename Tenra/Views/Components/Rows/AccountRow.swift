//
//  AccountRow.swift
//  Tenra
//
//  Reusable account row component for displaying accounts in lists
//

import SwiftUI

struct AccountRow: View {
    let account: Account
    let onEdit: () -> Void
    let onDelete: () -> Void
    let balanceCoordinator: BalanceCoordinator
    /// Pre-computed interest accrued to today (from parent via DepositInterestService)
    var interestToday: Double? = nil
    /// Pre-computed next interest posting date (from parent via DepositInterestService)
    var nextPostingDate: Date? = nil

    /// Optional zoom-transition source. When both id and namespace are non-nil,
    /// the row's logo becomes the matched source for `.navigationTransition(.zoom(...))`
    /// on the destination detail view.
    var transitionSourceID: String? = nil
    var transitionNamespace: Namespace.ID? = nil

    private var balance: Double {
        balanceCoordinator.balances[account.id] ?? 0
    }

    private var accountAccessibilityLabel: String {
        var parts = [account.name]
        // Balance is already formatted by FormattedAmountText but we need a plain string
        let formatter = AmountDisplayConfiguration.formatter
        if let formatted = formatter.string(from: NSNumber(value: balance)) {
            parts.append("\(formatted) \(account.currency)")
        }
        if account.isDeposit {
            parts.append(String(localized: "deposit.title"))
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
            Button(action: onEdit) {
                HStack(spacing: AppSpacing.md) {
                    // Логотип банка
                    IconView(source: account.iconSource, size: AppIconSize.xxl)
                        .matchedTransitionSourceIfPresent(
                            id: transitionSourceID,
                            namespace: transitionNamespace
                        )

                    VStack(alignment: .leading, spacing: AppSpacing.xs) {
                        Text(account.name)
                            .font(AppTypography.h4)

                        FormattedAmountText(
                            amount: balance,
                            currency: account.currency,
                            fontSize: AppTypography.bodySmall,
                            color: .secondary
                        )

                        if let interest = interestToday, interest > 0, let posting = nextPostingDate {
                            HStack(spacing: 0) {
                                let dateString = DateFormatters.displayDateFormatter.string(from: posting)
                                Text(String(format: String(localized: "account.postingWithInterest", defaultValue: "Posting: %@  ·  "), dateString))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)

                                FormattedAmountText(
                                    amount: interest,
                                    currency: account.currency,
                                    fontSize: AppTypography.caption,
                                    color: AppColors.planned
                                )
                            }
                        } else if let interest = interestToday, interest > 0 {
                            HStack(spacing: 0) {
                                Text(String(localized: "account.interestTodayPrefix", defaultValue: "Interest today: "))
                                    .font(AppTypography.caption)
                                    .foregroundStyle(.secondary)

                                FormattedAmountText(
                                    amount: interest,
                                    currency: account.currency,
                                    fontSize: AppTypography.caption,
                                    color: AppColors.planned
                                )
                            }
                        } else if let posting = nextPostingDate {
                            let dateString = DateFormatters.displayDateFormatter.string(from: posting)
                            Text(String(format: String(localized: "account.nextPosting"), dateString))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if account.isDeposit {
                        Image(systemName: "lock.square.stack.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: AppIconSize.sm))
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accountAccessibilityLabel)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    HapticManager.warning()
                    onDelete()
                } label: {
                    Label(String(localized: "button.delete"), systemImage: "trash")
                }
            }
        }
    }

#Preview {
    let sampleAccount = Account(
        id: "test",
        name: "Test Account",
        currency: "USD",
        iconSource: nil,
        initialBalance: 10000
    )
    let coordinator = AppCoordinator()

    List {
        AccountRow(
            account: sampleAccount,
            onEdit: {},
            onDelete: {},
            balanceCoordinator: coordinator.balanceCoordinator
        )
        .padding(.horizontal)
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
