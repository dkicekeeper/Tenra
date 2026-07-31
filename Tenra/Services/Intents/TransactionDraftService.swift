//
//  TransactionDraftService.swift
//  Tenra
//
//  The single write path for transactions created from a ParsedOperation.
//  Extracted from VoiceInputConfirmationView.saveTransaction so that the voice
//  confirmation screen and the App Intents cannot drift apart.
//
//  makeDraft is pure and synchronous: everything it decides is testable without
//  a store, a container or a network.
//

import Foundation

@MainActor
enum TransactionDraftService {

    // MARK: - Resolve

    static func makeDraft(
        from operation: ParsedOperation,
        accounts: [Account],
        categories: [CustomCategory],
        learned: VoiceLearningStore,
        conversion: ConversionPolicy = .cachedOnly,
        note: String = ""
    ) -> Result<TransactionDraft, DraftIssue> {

        var warnings: [DraftWarning] = []

        // 1. Amount — must be present and positive.
        guard let parsedAmount = operation.amount else { return .failure(.missingAmount) }
        let amount = NSDecimalNumber(decimal: parsedAmount).doubleValue
        guard amount > 0 else { return .failure(.missingAmount) }

        // 2. Account — named, else learned for this category, else first eligible.
        //    Loan and deposit accounts are never eligible for a plain expense/income.
        let eligible = accounts.filter { !$0.isLoan && !$0.isDeposit }
        guard let firstEligible = eligible.first else { return .failure(.noEligibleAccount) }

        let account: Account
        if let namedId = operation.accountId,
           let named = eligible.first(where: { $0.id == namedId }) {
            account = named
        } else {
            warnings.append(.accountInferred)
            let eligibleIds = Set(eligible.map(\.id))
            if let learnedId = learned.preferredAccountID(
                forCategory: operation.categoryName,
                where: { eligibleIds.contains($0) }
            ), let match = eligible.first(where: { $0.id == learnedId }) {
                account = match
            } else {
                account = firstEligible
            }
        }

        // 3. Category — must exist AND match the operation type, else fall back
        //    to the localized "Other" of the same type.
        let categoryName: String
        if let parsedName = operation.categoryName,
           categories.contains(where: { $0.name == parsedName && $0.type == operation.type }) {
            categoryName = parsedName
        } else {
            let fallback = String(localized: "category.other")
            guard categories.contains(where: { $0.name == fallback && $0.type == operation.type }) else {
                return .failure(.noFallbackCategory)
            }
            warnings.append(.categorySubstituted(original: operation.categoryName))
            categoryName = fallback
        }

        // 4. Currency — convert only when it differs from the account currency.
        let currency = operation.currencyCode ?? account.currency
        var convertedAmount: Double?
        if currency != account.currency {
            switch conversion {
            case .provided(let value):
                convertedAmount = value
            case .cachedOnly:
                guard let cached = CurrencyConverter.convertSync(
                    amount: amount,
                    from: currency,
                    to: account.currency
                ) else {
                    return .failure(.needsFXConversion(
                        amount: amount,
                        from: currency,
                        to: account.currency
                    ))
                }
                convertedAmount = cached
            }
        }

        return .success(TransactionDraft(
            type: operation.type,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            categoryName: categoryName,
            subcategoryIds: [],
            accountId: account.id,
            date: operation.date,
            note: note.isEmpty ? operation.note : note,
            warnings: warnings
        ))
    }
}
