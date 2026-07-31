//
//  TransactionDraft.swift
//  Tenra
//
//  Value types for the single transaction-write path shared by the voice
//  confirmation screen and every App Intent. No logic lives here.
//

import Foundation

/// A fully resolved transaction, ready to commit.
struct TransactionDraft: Equatable {
    var type: TransactionType
    var amount: Double
    var currency: String
    /// Amount expressed in the destination account's currency, or nil when
    /// `currency` already equals the account currency.
    var convertedAmount: Double?
    var categoryName: String
    var subcategoryIds: [String]
    var accountId: String
    var date: Date
    var note: String
    var warnings: [DraftWarning]
}

/// A value the resolver had to guess. Non-blocking: the caller must surface it
/// (a marked field in an intent snippet, or the existing warning labels on the
/// voice confirmation screen) so the user sees the guess before confirming.
enum DraftWarning: Equatable {
    case categorySubstituted(original: String?)
    case accountInferred
}

/// A condition the resolver cannot resolve on its own. Intents treat these as
/// "open the app with the operation prefilled".
enum DraftIssue: Error, Equatable {
    case missingAmount
    case noEligibleAccount
    case noFallbackCategory
    case needsFXConversion(amount: Double, from: String, to: String)
}

/// How to obtain a cross-currency amount. `makeDraft` is synchronous and pure,
/// so it can only read the FX cache; callers that may perform a network
/// conversion pass the result back in via `.provided`.
enum ConversionPolicy: Equatable {
    case cachedOnly
    case provided(Double?)
}

/// Side effects `commit` performs, injectable so they can be asserted in tests
/// without protocol ceremony around two singletons.
struct CommitHooks {
    var recordLearning: (String?, String?) -> Void
    var recordRating: () -> Void

    static let production = CommitHooks(
        recordLearning: { category, accountId in
            VoiceLearningStore.shared.recordSave(category: category, accountId: accountId)
        },
        recordRating: {
            RatingPromptService.shared.recordTransactionAdded()
        }
    )
}
