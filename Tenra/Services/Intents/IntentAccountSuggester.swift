//
//  IntentAccountSuggester.swift
//  Tenra
//
//  Gives an intent the same account suggestion the in-app add-expense modal
//  gets, without paying for a full transaction load.
//
//  TransactionAddModal reaches this ranking through
//  AccountsViewModel.suggestedAccount(forCategory:transactions:), which needs
//  the whole in-memory transactions array. An intent process deliberately does
//  not have one: initializeFastPath() loads accounts and settings only, and
//  loading 19k rows is exactly the cost it exists to avoid.
//
//  So the history is fetched with a bounded predicate for the one category in
//  question, the same trick SpendingQueryService uses, and handed to the shared
//  AccountRankingService. The scoring stays in one place.
//

import Foundation
import CoreData

enum IntentAccountSuggester {

    /// Recency decay in AccountRankingService makes old rows contribute almost
    /// nothing, so the newest slice is enough and keeps the fetch bounded even
    /// for a category with thousands of transactions.
    private static let historyLimit = 200

    static func suggestedAccountId(
        forCategory category: String,
        accounts: [Account],
        amount: Double?,
        context: NSManagedObjectContext
    ) -> String? {

        guard !category.isEmpty else { return nil }

        let request = NSFetchRequest<TransactionEntity>(entityName: "TransactionEntity")
        request.predicate = NSPredicate(
            format: "category == %@ AND type == %@",
            category,
            TransactionType.expense.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        request.fetchLimit = historyLimit

        guard let rows = try? context.fetch(request), !rows.isEmpty else { return nil }

        let transactions = rows.map { $0.toTransaction() }

        return AccountRankingService.suggestedAccount(
            forCategory: category,
            accounts: accounts,
            transactions: transactions,
            amount: amount
        )?.id
    }
}
