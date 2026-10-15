//
//  DebtCard.swift
//  Tenra
//
//  A personal debt in the debts list: adapter over DesignKit's PayoffProgressCard (as LoanCard
//  is for loans). What is left on the leading edge, the amount lent or borrowed on the
//  trailing edge, the share returned as the bar; the footer has the due date, or when it was
//  settled. An open debt past its due date carries a red "Overdue" badge.
//

import SwiftUI

struct DebtCard: View {
    let debt: PersonalDebt
    var today: Date = Date()

    var body: some View {
        let settledCaption = debt.settledAt.map {
            String(format: String(localized: "debt.settledOn"), DateFormatters.displayDateOmittingCurrentYear($0))
        }
        PayoffProgressCard(
            iconSource: debt.iconSource,
            title: debt.person,
            subtitle: oneLine(debt.note),
            remaining: debt.remaining,
            total: debt.amount,
            currency: debt.currency,
            progress: debt.progress,
            phase: settledCaption != nil
                ? .done(caption: settledCaption ?? "")
                : .inProgress(
                    nextDate: debt.dueDate.map { DateFormatters.displayDateOmittingCurrentYear($0) },
                    remainingCaption: nil
                )
        ) {
            if debt.isOverdue(today: today) {
                Badge(String(localized: "debt.overdue"), color: AppColors.destructive)
            }
        }
    }

    /// The note's first line, shortened: PayoffProgressCard's subtitle has no line limit, and a
    /// long note would grow the card.
    private func oneLine(_ note: String?) -> String? {
        guard let line = note?.split(whereSeparator: \.isNewline).first.map(String.init), !line.isEmpty else { return nil }
        return line.count > Self.noteLength ? String(line.prefix(Self.noteLength - 1)) + "…" : line
    }

    private static let noteLength = 48
}
