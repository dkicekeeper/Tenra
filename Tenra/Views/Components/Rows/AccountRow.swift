//
//  AccountRow.swift
//  Tenra
//
//  Account row of the accounts and deposits lists. Adapter over DesignKit's `BalanceRow`:
//  the account, the deposit interest copy, the tap, the swipe-to-delete and the VoiceOver
//  label stay here.
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

    /// Deposit interest line: the next posting date with the interest accrued so far, or
    /// either of them alone.
    private var interestDetail: BalanceRow.Detail? {
        if let interest = interestToday, interest > 0, let posting = nextPostingDate {
            let dateString = DateFormatters.displayDateFormatter.string(from: posting)
            return .init(
                String(format: String(localized: "account.postingWithInterest", defaultValue: "Posting: %@  ·  "), dateString),
                amount: interest
            )
        } else if let interest = interestToday, interest > 0 {
            return .init(
                String(localized: "account.interestTodayPrefix", defaultValue: "Interest today: "),
                amount: interest
            )
        } else if let posting = nextPostingDate {
            let dateString = DateFormatters.displayDateFormatter.string(from: posting)
            return .init(String(format: String(localized: "account.nextPosting"), dateString))
        }
        return nil
    }

    var body: some View {
        Button(action: onEdit) {
            BalanceRow(
                iconSource: account.iconSource,
                title: account.name,
                amount: balance,
                currency: account.currency,
                detail: interestDetail,
                trailingSystemImage: account.isDeposit ? "lock.square.stack.fill" : nil,
                transitionSourceID: transitionSourceID,
                transitionNamespace: transitionNamespace
            )
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
