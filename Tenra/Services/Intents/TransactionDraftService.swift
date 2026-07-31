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
        note: String = "",
        /// Injects the same history-based ranking the in-app add-expense modal
        /// uses (`AccountsViewModel.suggestedAccount(forCategory:transactions:)`,
        /// backed by `AccountRankingService`). Passed in rather than called
        /// directly so this function stays pure and so each caller can supply
        /// the cheapest source of history it has: the loaded store in the app,
        /// a bounded CoreData fetch in an intent process.
        ///
        /// Receives the RESOLVED category name, never the parser's raw guess.
        suggestAccount: ((String) -> String?)? = nil
    ) -> Result<TransactionDraft, DraftIssue> {

        var warnings: [DraftWarning] = []

        // 1. Amount — must be present and positive.
        guard let parsedAmount = operation.amount else { return .failure(.missingAmount) }
        let amount = NSDecimalNumber(decimal: parsedAmount).doubleValue
        guard amount > 0 else { return .failure(.missingAmount) }

        // 2. Category — resolved through a widening chain, and never a reason to
        //    refuse the transaction (TransactionStore.validate deliberately
        //    allows an empty category, meaning "uncategorized").
        //
        //    Resolved BEFORE the account, because the account lookup is keyed on
        //    the category and commit() records that key using the RESOLVED name.
        //    Looking it up under the parser's raw guess instead would mean the
        //    learning store never matches for anyone who renamed a category.
        let resolution = resolveCategory(
            named: operation.categoryName,
            type: operation.type,
            in: categories
        )
        let categoryName = resolution.name
        if !resolution.isExact {
            warnings.append(.categorySubstituted(original: operation.categoryName))
        }

        // 3. Account — named, else learned for this category, else first eligible.
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

            // Priority order, strongest signal first:
            //   1. a choice the user explicitly confirmed in the voice flow at
            //      least twice (VoiceLearningStore's confidence threshold),
            //   2. the history-based ranking the in-app modal uses,
            //   3. the first eligible account.
            // Learning outranks ranking because it is a deliberate correction
            // for this exact flow, not an inference over general history.
            if let learnedId = learned.preferredAccountID(
                forCategory: categoryName,
                where: { eligibleIds.contains($0) }
            ), let match = eligible.first(where: { $0.id == learnedId }) {
                account = match
            } else if let suggestedId = suggestAccount?(categoryName),
                      let match = eligible.first(where: { $0.id == suggestedId }) {
                account = match
            } else {
                account = firstEligible
            }
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

    // MARK: - Category resolution

    struct CategoryResolution {
        /// Empty means "uncategorized", which the store accepts.
        let name: String
        /// True only when the user's category was identified unambiguously, so
        /// the caller knows whether to warn.
        let isExact: Bool
    }

    /// Substring matching is skipped below this length: two-letter fragments
    /// match far too much to be a useful guess.
    private static let minimumSubstringMatchLength = 3

    /// Widening chain: exact name, then case-insensitive, then a substring
    /// relation in either direction, then the localized "Other", then
    /// uncategorized.
    ///
    /// The substring step exists because `VoiceInputParser` maps keywords onto
    /// hardcoded category names ("кофе" -> "Еда") while users rename their
    /// categories freely. Without it, an account whose food category is called
    /// "Еда вне дома" gets nothing at all out of the parser, which is what made
    /// Siri logging fail on device.
    ///
    /// Ties are broken by the user's own category order (the array is already
    /// ordered), so the result is deterministic rather than dictionary-random.
    static func resolveCategory(
        named parsedName: String?,
        type: TransactionType,
        in categories: [CustomCategory]
    ) -> CategoryResolution {

        let candidates = categories.filter { $0.type == type }

        if let parsedName, !parsedName.isEmpty {
            if let exact = candidates.first(where: { $0.name == parsedName }) {
                return CategoryResolution(name: exact.name, isExact: true)
            }

            let needle = parsedName.lowercased()

            // A pure case difference is the same category, not a guess.
            if let insensitive = candidates.first(where: { $0.name.lowercased() == needle }) {
                return CategoryResolution(name: insensitive.name, isExact: true)
            }

            if needle.count >= Self.minimumSubstringMatchLength {
                let related = candidates.first { candidate in
                    let name = candidate.name.lowercased()
                    return name.contains(needle)
                        || (name.count >= Self.minimumSubstringMatchLength && needle.contains(name))
                }
                if let related {
                    return CategoryResolution(name: related.name, isExact: false)
                }
            }
        }

        let other = String(localized: "category.other")
        if let fallback = candidates.first(where: { $0.name == other }) {
            return CategoryResolution(name: fallback.name, isExact: false)
        }

        return CategoryResolution(name: "", isExact: false)
    }

    // MARK: - Commit

    /// Writes the draft through TransactionStore and performs the side effects
    /// the manual add path performs, so an intent-created transaction is
    /// indistinguishable from a hand-entered one.
    @discardableResult
    static func commit(
        _ draft: TransactionDraft,
        store: TransactionStore,
        categoriesViewModel: CategoriesViewModel,
        hooks: CommitHooks = .production
    ) async throws -> Transaction {

        let dateString = DateFormatters.dateFormatter.string(from: draft.date)

        // Legacy `subcategory` field carries the first subcategory NAME, not its
        // id — matching VoiceInputConfirmationView.swift:476-480.
        var legacySubcategoryName: String?
        if !draft.subcategoryIds.isEmpty {
            legacySubcategoryName = categoriesViewModel.subcategories
                .first { draft.subcategoryIds.contains($0.id) }?
                .name
        }

        let transaction = Transaction(
            id: "",
            date: dateString,
            description: draft.note,
            amount: draft.amount,
            currency: draft.currency,
            convertedAmount: draft.convertedAmount,
            type: draft.type,
            category: draft.categoryName,
            subcategory: legacySubcategoryName,
            accountId: draft.accountId,
            targetAccountId: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil
        )

        let saved = try await store.add(transaction)

        if !saved.id.isEmpty, !draft.subcategoryIds.isEmpty {
            categoriesViewModel.linkSubcategoriesToTransaction(
                transactionId: saved.id,
                subcategoryIds: draft.subcategoryIds
            )
        }

        // Only an account the user actually chose counts as a preference.
        //
        // Recording an inferred one creates a self-reinforcing loop: the guess
        // gets confirmed, two confirmations cross VoiceLearningStore's
        // confidence threshold, and from then on the learned guess outranks the
        // history-based ranking. Every later transaction lands on whatever
        // account happened to be picked first, which is exactly what "the same
        // old account every time" looks like from the outside.
        if !draft.warnings.contains(.accountInferred) {
            hooks.recordLearning(saved.category, saved.accountId)
        }

        // Records the success moment only. The native prompt is never presented
        // from here: this path can run in a background, UI-less process.
        hooks.recordRating()

        return saved
    }
}
