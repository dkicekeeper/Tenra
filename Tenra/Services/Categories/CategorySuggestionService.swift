//
//  CategorySuggestionService.swift
//  Tenra
//
//  Merchant → category suggestion core for imported statement rows and scanned
//  receipts, which otherwise land uncategorized and drop out of every category
//  aggregate and budget.
//
//  Pure and `nonisolated` so the history sweep can run in `Task.detached`
//  (CLAUDE.md Red Flag 9). The MainActor side (resolving a candidate against
//  the user's own categories) lives in `CategorySuggestionProvider`.
//

import Foundation

nonisolated enum CategorySuggestionService {

    // MARK: - Normalization

    /// Lowercase, `ё`→`е`, every non-letter (digits, punctuation, symbols)
    /// becomes a space, whitespace collapsed, trimmed.
    /// "YANDEX.GO" → "yandex go"; "MAGNUM CASH&CARRY 123" → "magnum cash carry";
    /// "APPLE.COM/BILL" → "apple com bill"; "12345" → "".
    static func normalizedMerchant(_ text: String) -> String {
        let lowered = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        var scalars = String.UnicodeScalarView()
        for scalar in lowered.unicodeScalars {
            scalars.append(CharacterSet.letters.contains(scalar) ? scalar : " ")
        }
        return String(scalars)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Word-aware keyword test on an already-normalized merchant string.
    /// Keywords of <= 4 characters must equal a whole word ("abo" must not match
    /// "about", "cine" must not match "medicine"); longer keywords must start at
    /// a word boundary ("yandex" matches "yandex go").
    static func matches(keyword: String, inNormalized merchant: String) -> Bool {
        let key = normalizedMerchant(keyword)
        guard !key.isEmpty, !merchant.isEmpty else { return false }
        let padded = " " + merchant + " "
        if key.count <= shortKeywordLength {
            return padded.contains(" " + key + " ")
        }
        return padded.contains(" " + key)
    }

    private static let shortKeywordLength = 4

    // MARK: - History tier

    struct HistoryIndex: Sendable, Equatable {
        /// "\(type.rawValue)|\(normalizedMerchant)" → category → stats
        var stats: [String: [String: Stat]] = [:]

        struct Stat: Sendable, Equatable {
            var count: Int
            var latestDate: String
        }
    }

    /// Merchant strings shorter than this carry too little signal to learn from.
    static let minimumMerchantLength = 3

    /// Counts, per (type, normalized description), how often each non-empty
    /// category was used. Only `.expense` and `.income` rows count.
    static func buildHistoryIndex(from transactions: [Transaction]) -> HistoryIndex {
        var index = HistoryIndex()
        for tx in transactions {
            guard tx.type == .expense || tx.type == .income, !tx.category.isEmpty else { continue }
            let merchant = normalizedMerchant(tx.description)
            guard merchant.count >= minimumMerchantLength else { continue }
            let key = historyKey(type: tx.type, merchant: merchant)
            var byCategory = index.stats[key, default: [:]]
            var stat = byCategory[tx.category] ?? HistoryIndex.Stat(count: 0, latestDate: "")
            stat.count += 1
            if tx.date > stat.latestDate { stat.latestDate = tx.date }
            byCategory[tx.category] = stat
            index.stats[key] = byCategory
        }
        return index
    }

    /// Most-used category for this merchant and type. Ties go to the category
    /// used most recently ("yyyy-MM-dd" compares as a string), then to the
    /// alphabetically first name. nil when the merchant is unknown.
    static func historyCategory(
        for description: String,
        type: TransactionType,
        in index: HistoryIndex
    ) -> String? {
        let merchant = normalizedMerchant(description)
        guard merchant.count >= minimumMerchantLength,
              let byCategory = index.stats[historyKey(type: type, merchant: merchant)] else {
            return nil
        }
        return byCategory.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.latestDate != rhs.value.latestDate { return lhs.value.latestDate < rhs.value.latestDate }
            return lhs.key > rhs.key
        }?.key
    }

    private static func historyKey(type: TransactionType, merchant: String) -> String {
        "\(type.rawValue)|\(merchant)"
    }

    // MARK: - Subcategory history tier

    /// One saved transaction with subcategory links, as the sweep needs it. Built on
    /// the main actor from `TransactionStore.subcategoryIdsByTransactionId` (only
    /// linked transactions, so it stays small) and swept off it.
    struct SubcategoryUse: Sendable, Equatable {
        let description: String
        let type: TransactionType
        let category: String
        let subcategoryIds: [String]
        let date: String
    }

    struct SubcategoryIndex: Sendable, Equatable {
        /// "\(type.rawValue)|\(normalizedMerchant)|\(category)" → subcategory id → stats
        var stats: [String: [String: HistoryIndex.Stat]] = [:]
    }

    /// Counts, per (type, merchant, category), how often each subcategory was linked.
    /// Keyed by category too: "Любимая" under "Семья" says nothing about the same
    /// merchant filed under another category.
    static func buildSubcategoryIndex(from uses: [SubcategoryUse]) -> SubcategoryIndex {
        var index = SubcategoryIndex()
        for use in uses where !use.category.isEmpty {
            let merchant = normalizedMerchant(use.description)
            guard merchant.count >= minimumMerchantLength else { continue }
            let key = subcategoryKey(type: use.type, merchant: merchant, category: use.category)
            var bySubcategory = index.stats[key, default: [:]]
            for id in Set(use.subcategoryIds) {
                var stat = bySubcategory[id] ?? HistoryIndex.Stat(count: 0, latestDate: "")
                stat.count += 1
                if use.date > stat.latestDate { stat.latestDate = use.date }
                bySubcategory[id] = stat
            }
            index.stats[key] = bySubcategory
        }
        return index
    }

    /// Most-used subcategory for this merchant, type and category, with the same
    /// tie-breaks as `historyCategory`. nil when nothing was learned.
    static func historySubcategory(
        for description: String,
        type: TransactionType,
        category: String,
        in index: SubcategoryIndex
    ) -> String? {
        let merchant = normalizedMerchant(description)
        guard merchant.count >= minimumMerchantLength, !category.isEmpty,
              let bySubcategory = index.stats[subcategoryKey(type: type, merchant: merchant, category: category)]
        else { return nil }
        return bySubcategory.max { lhs, rhs in
            if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
            if lhs.value.latestDate != rhs.value.latestDate { return lhs.value.latestDate < rhs.value.latestDate }
            return lhs.key > rhs.key
        }?.key
    }

    private static func subcategoryKey(type: TransactionType, merchant: String, category: String) -> String {
        "\(type.rawValue)|\(merchant)|\(category)"
    }

    // MARK: - Similar saved transactions

    /// Saved transactions that look like `edited` and still carry
    /// `previousCategory`, for the "apply to similar" prompt after an edit.
    /// A candidate must have the same income/expense type, the same normalized
    /// merchant (at least `minimumMerchantLength` characters), the previous
    /// category, no recurring series (series edits go through the subscription
    /// screen) and no subcategory links (they belong to the old category).
    /// Sorted by date descending, then id, for determinism.
    static func similarTransactionIds(
        to edited: Transaction,
        previousCategory: String,
        in transactions: [Transaction],
        subcategoryLinks: [String: [String]]
    ) -> [String] {
        guard edited.type == .expense || edited.type == .income else { return [] }
        let merchant = normalizedMerchant(edited.description)
        guard merchant.count >= minimumMerchantLength else { return [] }

        return transactions
            .filter { candidate in
                candidate.id != edited.id
                    && candidate.type == edited.type
                    && candidate.category == previousCategory
                    && candidate.recurringSeriesId == nil
                    && (subcategoryLinks[candidate.id]?.isEmpty ?? true)
                    && normalizedMerchant(candidate.description) == merchant
            }
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date > rhs.date : lhs.id < rhs.id
            }
            .map(\.id)
    }

    // MARK: - Brand tier

    /// Well-known merchants → `CategoryPreset` id. An ARRAY of pairs, not a
    /// dictionary literal: a duplicate key in a dictionary literal compiles but
    /// crashes at runtime (CLAUDE.md Red Flag 16). Lowercase plain words; the
    /// matcher normalizes punctuation. Prefer keywords of 5+ characters, since
    /// shorter ones only match a whole word.
    static let brandPresets: [(keyword: String, presetId: String)] = [
        // Groceries
        ("magnum", "groceries"), ("galmart", "groceries"), ("anvar", "groceries"),
        ("arbuz", "groceries"), ("metro cash", "groceries"), ("carrefour", "groceries"),
        ("lidl", "groceries"), ("aldi", "groceries"), ("walmart", "groceries"),
        ("costco", "groceries"), ("kroger", "groceries"), ("whole foods", "groceries"),
        ("trader joe", "groceries"), ("auchan", "groceries"), ("ашан", "groceries"),
        ("пятерочка", "groceries"), ("перекресток", "groceries"), ("магнум", "groceries"),
        // Dining and food delivery
        ("starbucks", "dining"), ("mcdonald", "dining"), ("kfc", "dining"),
        ("burger king", "dining"), ("dodo pizza", "dining"), ("додо пицца", "dining"),
        ("domino", "dining"), ("papa john", "dining"), ("coffee boom", "dining"),
        ("glovo", "dining"), ("wolt", "dining"), ("yandex eda", "dining"),
        ("yandex eats", "dining"),
        // Transport and fuel
        ("yandex go", "transport"), ("yandex taxi", "transport"), ("uber", "transport"),
        ("bolt", "transport"), ("indrive", "transport"), ("onay", "transport"),
        ("shell", "transport"), ("helios", "transport"), ("qazaq oil", "transport"),
        ("sinooil", "transport"),
        // Subscriptions
        ("netflix", "subscriptions"), ("spotify", "subscriptions"),
        ("apple com bill", "subscriptions"), ("icloud", "subscriptions"),
        ("youtube premium", "subscriptions"), ("google one", "subscriptions"),
        ("yandex plus", "subscriptions"), ("kinopoisk", "subscriptions"),
        ("openai", "subscriptions"), ("chatgpt", "subscriptions"),
        // Utilities and telecom
        ("kazakhtelecom", "utilities"), ("beeline", "utilities"), ("kcell", "utilities"),
        ("tele2", "utilities"), ("altel", "utilities"), ("alseco", "utilities"),
        // Health
        ("europharma", "health"), ("invitro", "health"), ("аптека", "health"),
        // Entertainment
        ("kinopark", "entertainment"), ("chaplin", "entertainment"),
        ("steam", "entertainment"), ("playstation", "entertainment"),
        // Travel
        ("air astana", "travel"), ("fly arystan", "travel"), ("airbnb", "travel"),
        ("booking com", "travel"), ("aviasales", "travel"),
        // Clothing
        ("zara", "clothing"), ("lc waikiki", "clothing"), ("defacto", "clothing"),
        ("uniqlo", "clothing"), ("bershka", "clothing")
    ]

    /// Longest keyword first, so "yandex eda" wins over any shorter overlap.
    private static let brandPresetsByLength: [(keyword: String, presetId: String)] =
        brandPresets.sorted { $0.keyword.count > $1.keyword.count }

    /// The preset id of the longest brand keyword found in `description`, or nil.
    static func brandPresetId(for description: String) -> String? {
        let merchant = normalizedMerchant(description)
        guard !merchant.isEmpty else { return nil }
        return brandPresetsByLength.first { matches(keyword: $0.keyword, inNormalized: merchant) }?.presetId
    }
}
