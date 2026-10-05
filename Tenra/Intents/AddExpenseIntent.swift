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
//  automation), the category and subcategory come from MerchantCategoryMemory;
//  an unknown merchant is asked about once (category, then subcategory when the
//  category has any), and the answers are remembered.
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

    @Parameter(title: "intent.addExpense.parameter.subcategory")
    var subcategory: SubcategoryAppEntity?

    @Parameter(title: "intent.addExpense.parameter.account")
    var account: AccountAppEntity?

    @Parameter(title: "intent.addExpense.parameter.note")
    var note: String?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {

        let services = await IntentEnvironment.shared.services()
        let memory = MerchantCategoryMemory.shared

        // Category: the one passed in, else the one the user chose for this
        // merchant before, else ask once and remember the answer. The Wallet
        // automation passes the merchant as the note; without a usable note the
        // old behavior stands ("Other", marked as a guess in the confirmation).
        //
        // Subcategory follows the same order: passed in, remembered, or asked
        // right after the category. nil means "no decision", empty means the
        // user chose "no subcategory".
        var chosenCategory = category
        var chosenSubcategoryIds: [String]? = subcategory.map { $0.isNone ? [] : [$0.id] }
        if chosenCategory == nil, let note, MerchantCategoryMemory.key(forMerchant: note) != nil {
            if let remembered = memory.category(
                forMerchant: note,
                in: services.categories.customCategories
            ) {
                chosenCategory = CategoryAppEntity(id: remembered.id, name: remembered.name)
                if chosenSubcategoryIds == nil {
                    chosenSubcategoryIds = memory.subcategoryIds(forMerchant: note)
                }
            } else {
                let merchant = note.trimmingCharacters(in: .whitespacesAndNewlines)
                let question = String(
                    format: String(localized: "intent.addExpense.askCategory"),
                    merchant
                )
                let picked: CategoryAppEntity? = try await $category.requestValue(
                    IntentDialog(stringLiteral: question)
                )
                chosenCategory = picked
                if let picked, chosenSubcategoryIds == nil {
                    chosenSubcategoryIds = try await askSubcategory(of: picked, merchant: merchant)
                }
            }
        }

        // Only subcategories still linked to the chosen category are applied.
        // Read from CoreData: a cold intent process has none in memory.
        var subcategoryIdsToLink: [String] = []
        if let chosenCategory, let ids = chosenSubcategoryIds, !ids.isEmpty {
            let current = Set(
                IntentSubcategoryStore
                    .subcategories(ofCategoryIds: [chosenCategory.id], context: CoreDataStack.shared.viewContext)
                    .map(\.id)
            )
            subcategoryIdsToLink = ids.filter { current.contains($0) }
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

        case .success(var draft):
            // A substituted category ("Other") is not the one the user chose:
            // its subcategories do not apply and nothing is remembered.
            let keepsChosenCategory = chosenCategory.map { draft.categoryName == $0.name } ?? false
            if keepsChosenCategory {
                draft.subcategoryIds = subcategoryIdsToLink
            }

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
            if keepsChosenCategory, let chosenCategory, let note {
                memory.remember(
                    categoryId: chosenCategory.id,
                    subcategoryIds: chosenSubcategoryIds,
                    forMerchant: note
                )
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

    /// The one-time subcategory question for a new merchant, asked right after
    /// its category. nil when the category has no subcategories (nothing to
    /// decide); empty when the user chose "no subcategory".
    @MainActor
    private func askSubcategory(of category: CategoryAppEntity, merchant: String) async throws -> [String]? {
        let options = IntentSubcategoryStore.subcategories(
            ofCategoryIds: [category.id],
            context: CoreDataStack.shared.viewContext
        )
        guard !options.isEmpty else { return nil }

        let choices = [SubcategoryAppEntity.none]
            + options.map { SubcategoryAppEntity(id: $0.id, name: $0.name) }
        let question = String(
            format: String(localized: "intent.addExpense.askSubcategory"),
            merchant
        )
        let picked: SubcategoryAppEntity? = try await $subcategory.requestDisambiguation(
            among: choices,
            dialog: IntentDialog(stringLiteral: question)
        )
        guard let picked, !picked.isNone else { return [] }
        return [picked.id]
    }
}
