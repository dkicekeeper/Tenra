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
//  Category memory: with no category but a merchant in the note (the Wallet
//  automation), the category comes from MerchantCategoryMemory; an unknown
//  merchant is asked about once, and the answer is remembered.
//

import AppIntents
import CoreData
import SwiftUI

struct AddExpenseIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.addExpense.title"
    static var description = IntentDescription("intent.addExpense.description")

    /// Runs headlessly and escalates to the app only when `makeDraft` cannot
    /// resolve the operation. `.foreground(.dynamic)` is what allows the
    /// `continueInForeground()` call below; the deprecated `openAppWhenRun = false`
    /// it replaces could not express a per-invocation decision.
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

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

        // Category: the one passed in, else the one the user chose for this
        // merchant before, else ask once and remember the answer. The Wallet
        // automation passes the merchant as the note; without a usable note the
        // old behavior stands ("Other", marked as a guess in the confirmation).
        var chosenCategory = category
        if chosenCategory == nil, let note, MerchantCategoryMemory.key(forMerchant: note) != nil {
            if let remembered = MerchantCategoryMemory.shared.category(
                forMerchant: note,
                in: services.categories.customCategories
            ) {
                chosenCategory = CategoryAppEntity(id: remembered.id, name: remembered.name)
            } else {
                let question = String(
                    format: String(localized: "intent.addExpense.askCategory"),
                    note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let picked: CategoryAppEntity? = try await $category.requestValue(
                    IntentDialog(stringLiteral: question)
                )
                chosenCategory = picked
            }
        }

        let operation = ParsedOperation(
            type: .expense,
            amount: Decimal(amount),
            currencyCode: account?.currency,
            date: Date(),
            accountId: account?.id,
            categoryName: chosenCategory?.name,
            subcategoryNames: [],
            note: note ?? ""
        )

        let result = TransactionDraftService.makeDraft(
            from: operation,
            accounts: services.accounts.accounts,
            categories: services.categories.customCategories,
            learned: .shared,
            conversion: .cachedOnly,
            note: note ?? "",
            suggestAccount: { category in
                IntentAccountSuggester.suggestedAccountId(
                    forCategory: category,
                    accounts: services.accounts.accounts,
                    amount: amount,
                    context: CoreDataStack.shared.persistentContainer.viewContext
                )
            }
        )

        switch result {
        case .failure:
            IntentHandoff.shared.request(operation)
            // Voice-only surfaces (HomePod, AirPods) cannot bring the app forward, and
            // calling continueInForeground there throws. Ask the system to prompt instead.
            guard systemContext.currentMode.canContinueInForeground else {
                throw needsToContinueInForegroundError(
                    IntentDialog(stringLiteral: String(localized: "intent.addExpense.openingApp"))
                )
            }
            try await continueInForeground(
                IntentDialog(stringLiteral: String(localized: "intent.addExpense.openingApp"))
            )
            return .result(dialog: "intent.addExpense.openingApp")

        case .success(let draft):
            if !draft.warnings.isEmpty {
                let accountName = services.accounts.accounts
                    .first { $0.id == draft.accountId }?.name ?? ""
                try await requestConfirmation(
                    dialog: IntentDialog("intent.addExpense.confirm"),
                    snippetIntent: TransactionConfirmationSnippetIntent(
                        draft: draft,
                        accountName: accountName
                    )
                )
            }

            _ = try await TransactionDraftService.commit(
                draft,
                store: services.store,
                categoriesViewModel: services.categories
            )
            IntentUsageCounters.shared.record(.intentAdd)

            // Remembered only once the expense is saved with exactly that
            // category, so a cancelled run or a substituted name teaches nothing.
            if let chosenCategory, let note, draft.categoryName == chosenCategory.name {
                MerchantCategoryMemory.shared.remember(categoryId: chosenCategory.id, forMerchant: note)
            }

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
