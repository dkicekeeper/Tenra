//
//  AssistantAttachmentCard.swift
//  Tenra
//
//  A receipt or a statement attached in the chat (docs/plan-ai-assistant.md §3.8): what the
//  phone read, without the model (a receipt's shop, total and date; a statement's rows, period,
//  expenses and income, the rows that need a category or could not be read), and "Review",
//  which opens the app's own review screen (ReceiptConfirmationView, ImportTransactionPreviewView)
//  where it is saved. The first review of an attachment spends one free answer; with none left
//  it offers Pro and opens once Pro is on.
//

import SwiftUI

struct AssistantAttachmentCard: View {
    @Environment(AppCoordinator.self) private var coordinator

    let model: AssistantViewModel
    let entryId: UUID
    let summary: AgentAttachmentSummary

    @State private var reviewing = false
    @State private var showingPaywall = false

    var body: some View {
        AssistantCard(title) {
            switch summary.kind {
            case .receipt:
                if let total = summary.expenses {
                    UniversalRow(
                        [summary.title, Self.day(summary.firstDate)].compactMap { $0 }.joined(separator: " · "),
                        icon: "receipt",
                        config: .info,
                        accessory: .amount(total.amount, currency: total.currency)
                    )
                }
            case .statement:
                MetaLine(statementItems)
                if let expenses = summary.expenses {
                    UniversalRow(
                        String(localized: "insights.expenses"),
                        config: .info,
                        accessory: .amount(expenses.amount, currency: expenses.currency)
                    )
                }
                if let income = summary.income {
                    UniversalRow(
                        String(localized: "insights.income"),
                        config: .info,
                        accessory: .amount(income.amount, currency: income.currency)
                    )
                }
                if summary.uncategorized > 0 {
                    InlineStatusText(message: String(format: String(localized: "assistant.attachment.uncategorized"), summary.uncategorized), type: .info)
                }
                if summary.skipped > 0 {
                    InlineStatusText(message: String(format: String(localized: "assistant.attachment.skipped"), summary.skipped), type: .warning)
                }
            }
            DSButton(String(localized: "assistant.attachment.review"), systemImage: "checklist", fullWidth: true) {
                if model.payForReview(of: entryId) {
                    reviewing = true
                } else {
                    showingPaywall = true
                }
            }
        }
        .paywallSheet(isPresented: $showingPaywall) {
            model.refreshAllowance()
            reviewing = true
        }
        .sheet(isPresented: $reviewing) {
            review
                .environment(coordinator.transactionStore)
        }
    }

    @ViewBuilder
    private var review: some View {
        switch model.attachment(for: entryId) {
        case .receipt(let draft)?:
            ReceiptConfirmationView(
                draft: draft,
                baseCurrency: coordinator.transactionStore.baseCurrency,
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                categoriesViewModel: coordinator.categoriesViewModel
            )
        case .statement(let statement)?:
            ImportTransactionPreviewView(
                transactionsViewModel: coordinator.transactionsViewModel,
                accountsViewModel: coordinator.accountsViewModel,
                transactions: statement.transactions,
                customCategories: coordinator.categoriesViewModel.customCategories,
                categoriesViewModel: coordinator.categoriesViewModel,
                suggestedCategories: statement.suggestedCategories,
                subcategoryHistory: statement.subcategoryHistory,
                transferHistory: statement.transferHistory,
                uncheckedMoves: statement.uncheckedMoves,
                transferEligibleIds: statement.transferEligibleIds,
                defaultStatementAccountId: statement.statementAccountId,
                closingBalances: statement.outcome.closingBalances
            )
        case nil:
            EmptyView()
        }
    }

    private var title: String {
        switch summary.kind {
        case .receipt:
            return String(localized: "assistant.attachment.receipt")
        case .statement:
            let name = String(localized: "assistant.attachment.statement")
            return summary.title.map { "\(name) · \($0)" } ?? name
        }
    }

    /// "78 operations · 1 Oct – 31 Oct".
    /// "64 transactions · 1 Oct – 31 Oct": MetaLine draws the dots and stacks the items at the
    /// largest text sizes.
    private var statementItems: [MetaItem] {
        let count = String(format: NSLocalizedString("history.count", comment: "Transaction count"), summary.count)
        guard let first = Self.day(summary.firstDate), let last = Self.day(summary.lastDate) else { return [.text(count)] }
        return [.text(count), .text(first == last ? first : "\(first) – \(last)")]
    }

    private static func day(_ date: String?) -> String? {
        date.flatMap { FastDateParser.date(from: $0) }?.formatted(.dateTime.day().month(.abbreviated))
    }
}
