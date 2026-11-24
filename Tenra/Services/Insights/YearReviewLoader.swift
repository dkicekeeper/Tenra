//
//  YearReviewLoader.swift
//  Tenra
//
//  The year in review for the screens that show it (Analytics' card, Ten's message, the screen
//  itself): `YearReviewBuilder.build` off the main actor on a snapshot of the store (CLAUDE.md,
//  red flag 9), kept until something it depends on changes. The key holds every dimension the
//  review reads (red flag 12): the year, the history (`mutationVersion`), the series (which are
//  subscriptions), the categories (their names label the top five), the rates and the base
//  currency, the person's brands and linked operations (the top merchants), and the day (only
//  realized rows count, and the current month is never final).
//

import Foundation

@MainActor
enum YearReviewLoader {
    struct Key: Equatable {
        let year: Int
        let transactionsVersion: Int
        let series: [RecurringSeries]
        let categoriesVersion: Int
        let ratesVersion: Int
        let baseCurrency: String
        let brands: MerchantBrands
        /// "yyyy-MM-dd".
        let day: String
    }

    private static var cached: (key: Key, review: YearReview?)?

    static func key(
        year: Int,
        store: TransactionStore,
        baseCurrency: String,
        brands: MerchantBrands,
        now: Date
    ) -> Key {
        Key(
            year: year,
            transactionsVersion: store.mutationVersion,
            series: store.recurringSeries,
            categoriesVersion: store.categoriesMutationVersion,
            ratesVersion: store.currencyRatesVersion,
            baseCurrency: baseCurrency,
            brands: brands,
            day: FastDateParser.string(from: now)
        )
    }

    /// The review of `year`, or nil when there is too little to review. Computed once per key.
    static func review(
        year: Int,
        store: TransactionStore,
        baseCurrency: String,
        brands: MerchantBrands,
        now: Date = Date()
    ) async -> YearReview? {
        let key = key(year: year, store: store, baseCurrency: baseCurrency, brands: brands, now: now)
        if let cached, cached.key == key { return cached.review }
        let transactions = store.transactions
        let series = store.recurringSeries
        // One rate table for the whole walk (RateSnapshot).
        let rates = RateSnapshot()
        let review = await Task.detached(priority: .userInitiated) {
            YearReviewBuilder.build(
                year: year,
                transactions: transactions,
                recurringSeries: series,
                baseCurrency: baseCurrency,
                rates: rates,
                brands: brands,
                now: now
            )
        }.value
        cached = (key, review)
        return review
    }
}
