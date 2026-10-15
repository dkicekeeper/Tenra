//
//  GoalCard.swift
//  Tenra
//
//  A savings goal in the goals list: adapter over DesignKit's PayoffProgressCard (as LoanCard
//  is for loans). The saved amount on the leading edge, the target on the trailing edge, the
//  bar between; the footer has the deadline and what to put aside each month, or when the
//  goal was reached. A goal past its deadline carries a red badge (as DebtCard) and its
//  footer says what is left.
//

import SwiftUI

struct GoalCard: View {
    let goal: SavingsGoal
    let status: GoalProgress.Status
    /// The linked account's name, when the goal follows one that still exists.
    var accountName: String? = nil

    @Environment(\.amountsHidden) private var amountsHidden

    var body: some View {
        PayoffProgressCard(
            iconSource: goal.iconSource ?? SavingsGoal.defaultIcon,
            title: goal.name,
            subtitle: accountName,
            remaining: status.saved,
            total: goal.targetAmount,
            currency: goal.currency,
            progress: status.fraction,
            phase: phase
        ) {
            overdueBadge
        }
    }

    /// Past the deadline and not reached (GoalProgress.Status.isOverdue).
    private var overdueBadge: Badge? {
        status.isOverdue ? Badge(String(localized: "goal.overdue"), color: AppColors.destructive) : nil
    }

    private var phase: PayoffProgressCard<Badge?>.Phase {
        if status.isReached {
            let caption = goal.reachedAt.map {
                String(format: String(localized: "goal.reachedOn"), DateFormatters.displayDateOmittingCurrentYear($0))
            } ?? String(localized: "goal.reached")
            return .done(caption: caption)
        }
        return .inProgress(
            nextDate: goal.deadline.map { DateFormatters.displayDateOmittingCurrentYear($0) },
            remainingCaption: footerCaption
        )
    }

    private var footerCaption: String {
        if !status.isOverdue, let monthly = status.monthly {
            return String(format: String(localized: "goal.perMonth"), amountText(monthly))
        }
        return String(format: String(localized: "goal.leftAmount"), amountText(status.left))
    }

    private func amountText(_ amount: Double) -> String {
        amountsHidden
            ? Formatting.hiddenAmount(currency: goal.currency)
            : Formatting.formatCurrencySmart(amount, currency: goal.currency)
    }
}
