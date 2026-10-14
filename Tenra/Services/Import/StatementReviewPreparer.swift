//
//  StatementReviewPreparer.swift
//  Tenra
//
//  What the review screen (`ImportTransactionPreviewView`) needs for one recognized statement,
//  prepared once for every place that imports one: the import tab (PDFImportCoordinator) and
//  the assistant's attachments. The rows as transactions, the categories suggested for them,
//  the user's own history of subcategories and transfers, the statement's account, and the rows
//  that start unchecked (docs/domains/import.md).
//

import Foundation

struct StatementReview {
    let outcome: ImportOutcome
    let transactions: [Transaction]
    let suggestedCategories: [String: String]
    let uncheckedMoves: [String: StatementOperationKind]
    let transferEligibleIds: Set<String>
    let statementAccountId: String?
    let subcategoryHistory: CategorySuggestionService.SubcategoryIndex
    let transferHistory: ImportTransferHistory.Index
}

enum StatementReviewPreparer {
    /// The review of a statement with at least one recognized row.
    static func prepare(
        _ outcome: ImportOutcome,
        baseCurrency: String,
        transactionsViewModel: TransactionsViewModel,
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel
    ) async -> StatementReview {
        let mapped = ParsedTransactionMapper.transactions(
            from: outcome.statement,
            defaultCurrency: baseCurrency
        )
        // Recognized rows arrive uncategorized; pre-fill the review screen's category pickers
        // from history, known merchants and the voice keyword dictionary.
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel
        )
        let suggestedCategories = await CategorySuggestionProvider.suggestions(
            for: mapped,
            history: transactionsViewModel.transactionStore?.transactions ?? [],
            categories: categoriesViewModel.customCategories,
            keywordMatcher: { parser.keywordCategory(in: $0) }
        )
        // What the user did before: subcategories per merchant and category, transfers to
        // their other accounts per account and description. Duplicates and transfer matches
        // depend on the statement's account, which the review screen lets the user change, so
        // it runs those.
        let store = transactionsViewModel.transactionStore
        let history = store?.transactions ?? []
        let subcategoryUses: [CategorySuggestionService.SubcategoryUse] = (store?.subcategoryIdsByTransactionId ?? [:])
            .compactMap { transactionId, subcategoryIds in
                guard !subcategoryIds.isEmpty, let tx = store?.transactionById[transactionId] else { return nil }
                return CategorySuggestionService.SubcategoryUse(
                    description: tx.description, type: tx.type, category: tx.category,
                    subcategoryIds: subcategoryIds, date: tx.date
                )
            }
        let (subcategoryHistory, transferHistory) = await Task.detached(priority: .userInitiated) {
            (CategorySuggestionService.buildSubcategoryIndex(from: subcategoryUses),
             ImportTransferHistory.build(from: history))
        }.value
        // The statement's account: the bank whose web domain the pages print.
        let statementAccountId = outcome.bankDomain.flatMap { domain in
            StatementBankDetector.accountId(
                forBankDomain: domain,
                among: accountsViewModel.regularAccounts.map { account in
                    (id: account.id, name: account.name, logoDomain: account.iconSource?.brandDomain)
                }
            )
        }
        // Cash withdrawals and own-account moves start unchecked: the cash is spent (and
        // logged) later, and an own-account move lands in another account the user keeps, so
        // importing either as spending or income would count the money twice. The mapper keeps
        // statement order.
        let kinds = zip(outcome.statement.transactions, mapped).map { parsed, tx in
            (tx.id, StatementOperationKind.classify(operation: parsed.operation,
                                                    details: parsed.descriptionText))
        }
        let uncheckedMoves = Dictionary(
            kinds.filter { $0.1.startsUnchecked },
            uniquingKeysWith: { first, _ in first }
        )
        // Purchases and cash withdrawals are never the other side of a transfer.
        let transferEligibleIds = Set(kinds.filter { $0.1 != .purchase && $0.1 != .cashWithdrawal }.map(\.0))
        return StatementReview(
            outcome: outcome,
            transactions: mapped,
            suggestedCategories: suggestedCategories,
            uncheckedMoves: uncheckedMoves,
            transferEligibleIds: transferEligibleIds,
            statementAccountId: statementAccountId,
            subcategoryHistory: subcategoryHistory,
            transferHistory: transferHistory
        )
    }
}
