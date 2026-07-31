//
//  AddExpenseIntent.swift
//  Tenra
//
//  Typed-parameter sibling of LogTransactionIntent, for the Shortcuts app:
//  automations, the Action Button, and the Shortcuts widget.
//
//  Confirmation rule: confirm only when a field was defaulted. A fully
//  specified call from an automation must not stop and ask, or automations
//  become unusable.
//

import AppIntents
import SwiftUI

struct AddExpenseIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.addExpense.title"
    static var description = IntentDescription("intent.addExpense.description")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.addExpense.parameter.amount")
    var amount: Double

    @Parameter(title: "intent.addExpense.parameter.category")
    var category: CategoryAppEntity?

    @Parameter(title: "intent.addExpense.parameter.account")
    var account: AccountAppEntity?

    @Parameter(title: "intent.addExpense.parameter.note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {

        let services = await IntentEnvironment.shared.services()

        let operation = ParsedOperation(
            type: .expense,
            amount: Decimal(amount),
            currencyCode: account?.currency,
            date: Date(),
            accountId: account?.id,
            categoryName: category?.name,
            subcategoryNames: [],
            note: note ?? ""
        )

        let result = TransactionDraftService.makeDraft(
            from: operation,
            accounts: services.accounts.accounts,
            categories: services.categories.customCategories,
            learned: .shared,
            conversion: .cachedOnly,
            note: note ?? ""
        )

        switch result {
        case .failure:
            IntentHandoff.shared.request(operation)
            try await continueInForeground(
                IntentDialog(stringLiteral: String(localized: "intent.addExpense.openingApp"))
            )
            return .result(dialog: "intent.addExpense.openingApp")

        case .success(let draft):
            if !draft.warnings.isEmpty {
                let accountName = services.accounts.accounts
                    .first { $0.id == draft.accountId }?.name ?? ""
                try await requestConfirmation(
                    result: .result(dialog: "intent.addExpense.confirm") {
                        TransactionConfirmationSnippet(draft: draft, accountName: accountName)
                    }
                )
            }

            _ = try await TransactionDraftService.commit(
                draft,
                store: services.store,
                categoriesViewModel: services.categories
            )
            IntentUsageCounters.shared.record(.intentAdd)

            let amountText = Formatting.formatCurrencySmart(
                draft.amount,
                currency: draft.currency
            )
            let text = String(
                format: String(localized: "intent.addExpense.saved"),
                amountText,
                draft.categoryName
            )
            return .result(dialog: IntentDialog(stringLiteral: text))
        }
    }
}
