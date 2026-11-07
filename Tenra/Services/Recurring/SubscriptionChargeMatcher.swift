//
//  SubscriptionChargeMatcher.swift
//  Tenra
//
//  A subscription records its charge ahead (the series' planned occurrence), and the bank
//  reports the real one: an Apple Pay payment, a bank's notification, an expense the person
//  entered. One charge must stay one transaction, so the real charge is merged into the
//  planned one: the occurrence keeps its id, series, category, name and subcategories, and
//  takes the real amount, currency, conversion, date and account.
//
//  Which planned charge a real one stands for, strongest first:
//  1. the subscription remembered for the merchant (SubscriptionMerchantMemory, taught by a
//     link by hand), within 30 % (a price change, the bank's rate);
//  2. a brand word the merchant shares with the subscription ("NETFLIX.COM" and "Netflix",
//     or the billing company: "APPLE.COM/BILL" and "iCloud+"), within 5 % in the same
//     currency, 10 % across currencies;
//  3. otherwise the same amount (5 %, 10 % across currencies) is only a suggestion the
//     person answers in To review: a coffee priced like a subscription must not vanish.
//  Always within three days of the planned date; on the payment's own account first (two
//  subscriptions of one brand and price on two cards), then the closest. Pure: the memory, the
//  rates and the accounts' currencies are passed in. docs/domains/recurring.md §Real charges.
//

import Foundation

nonisolated enum SubscriptionChargeMatcher {

    /// A real charge, as an automation or a bank reported it.
    struct Charge: Equatable, Sendable {
        let amount: Double
        /// ISO 4217.
        let currency: String
        /// `ImportDuplicateDetector.dayNumber` of the charge's date.
        let day: Int
        /// The merchant as the bank wrote it; "" when there is none.
        let merchant: String
    }

    struct Match: Equatable, Sendable {
        /// The planned charge the real one stands for.
        let occurrence: Transaction
        /// Remembered for the merchant or a shared brand word: merged on its own. Otherwise a
        /// suggestion the person confirms in To review.
        let isConfident: Bool
    }

    /// Same currency: the statement import's tolerance.
    static let sameCurrencyTolerance = ImportDuplicateDetector.subscriptionAmountTolerance
    /// Across currencies the bank's rate differs from the cached one.
    static let convertedTolerance = 0.10
    /// A merchant the person linked to the subscription: its price may change.
    static let rememberedTolerance = 0.30
    static let dayWindow = ImportDuplicateDetector.subscriptionDayWindow

    /// The planned charge a real one stands for, or nil.
    /// - Parameters:
    ///   - occurrences: the series' planned charges around the date (others are skipped).
    ///   - suggests: false for a transfer to a person: never a subscription suggestion.
    ///   - accountId: the account the payment came from, when known: its planned charges first.
    ///   - accountCurrency: an occurrence's account → its currency.
    ///   - convert: amount, from, to → the amount at the cached rate.
    static func match(
        _ charge: Charge,
        occurrences: [Transaction],
        rememberedSeriesId: String?,
        dismissedSeriesIds: Set<String>,
        suggests: Bool,
        accountId: String? = nil,
        accountCurrency: (String) -> String?,
        convert: (Double, String, String) -> Double?
    ) -> Match? {
        let merchantWords = WalletPaymentResolver.brandWords(charge.merchant)
        // Tier (0 remembered, 1 brand word, 2 suggestion), then another account (1) after the
        // payment's own (0), then the distance in days.
        var best: (match: Match, tier: Int, otherAccount: Int, distance: Int)?
        for occurrence in occurrences {
            guard occurrence.type == .expense,
                  let seriesId = occurrence.recurringSeriesId, !seriesId.isEmpty,
                  let occurrenceDay = ImportDuplicateDetector.dayNumber(occurrence.date)
            else { continue }
            let distance = abs(occurrenceDay - charge.day)
            guard distance <= dayWindow,
                  let gap = relativeGap(charge, occurrence, accountCurrency: accountCurrency, convert: convert)
            else { continue }
            let tolerance = gap.isConverted ? convertedTolerance : sameCurrencyTolerance

            let tier: Int
            if seriesId == rememberedSeriesId {
                guard gap.value <= rememberedTolerance else { continue }
                tier = 0
            } else if !merchantWords.isEmpty,
                      !WalletPaymentResolver.billedWords(occurrence.description).isDisjoint(with: merchantWords) {
                guard gap.value <= tolerance else { continue }
                tier = 1
            } else {
                guard suggests, rememberedSeriesId == nil, !merchantWords.isEmpty,
                      !dismissedSeriesIds.contains(seriesId), gap.value <= tolerance else { continue }
                tier = 2
            }
            let otherAccount = accountId == nil || occurrence.accountId == accountId ? 0 : 1
            let candidate = (Match(occurrence: occurrence, isConfident: tier < 2), tier, otherAccount, distance)
            if let current = best {
                let isBetter = tier != current.tier ? tier < current.tier
                    : otherAccount != current.otherAccount ? otherAccount < current.otherAccount
                    : distance != current.distance ? distance < current.distance
                    : occurrence.id < current.match.occurrence.id
                if isBetter { best = candidate }
            } else {
                best = candidate
            }
        }
        return best?.match
    }

    /// How far the charge is from the planned amount, as a share of the charge: in the same
    /// currency, else against the planned account-currency amount when the charge is in the
    /// account's currency (a dollar subscription the bank charged in tenge), else at the
    /// cached rate. nil when the two cannot be compared.
    static func relativeGap(
        _ charge: Charge,
        _ occurrence: Transaction,
        accountCurrency: (String) -> String?,
        convert: (Double, String, String) -> Double?
    ) -> (value: Double, isConverted: Bool)? {
        guard charge.amount > 0 else { return nil }
        if occurrence.currency == charge.currency {
            return (abs(occurrence.amount - charge.amount) / charge.amount, false)
        }
        if let accountId = occurrence.accountId,
           accountCurrency(accountId) == charge.currency,
           let planned = occurrence.convertedAmount, planned > 0 {
            return (abs(planned - charge.amount) / charge.amount, true)
        }
        if let converted = convert(charge.amount, charge.currency, occurrence.currency), converted > 0 {
            return (abs(occurrence.amount - converted) / converted, true)
        }
        return nil
    }

    /// The planned charge as the real one makes it: its id, series, occurrence, category, name
    /// and creation time stay (its subcategory links are keyed on the id); the amount, currency,
    /// conversion, date and account are the bank's. The account-currency fields come from the
    /// real charge too, never the planned ones: the balance reads `targetAmount` first whenever
    /// the currency is not the account's (red flag 6).
    static func merged(
        _ occurrence: Transaction,
        amount: Double,
        currency: String,
        convertedAmount: Double?,
        targetCurrency: String?,
        targetAmount: Double?,
        accountId: String?,
        date: String
    ) -> Transaction {
        let account = accountId ?? occurrence.accountId
        return Transaction(
            id: occurrence.id,
            date: date,
            description: occurrence.description,
            amount: amount,
            currency: currency,
            convertedAmount: convertedAmount,
            type: occurrence.type,
            category: occurrence.category,
            subcategory: occurrence.subcategory,
            accountId: account,
            targetAccountId: occurrence.targetAccountId,
            accountName: account == occurrence.accountId ? occurrence.accountName : nil,
            targetAccountName: occurrence.targetAccountName,
            targetCurrency: targetCurrency,
            targetAmount: targetAmount,
            recurringSeriesId: occurrence.recurringSeriesId,
            recurringOccurrenceId: occurrence.recurringOccurrenceId,
            createdAt: occurrence.createdAt
        )
    }

    /// The planned charge an expense picked by hand stands for: the series' nearest generated
    /// occurrence (it has an occurrence id; a payment linked by hand has none) not yet taken for
    /// a real charge, within half the series' period. nil links the expense to the series as it
    /// is (an old charge, before the series started).
    static func plannedOccurrence(
        for charge: Transaction,
        among seriesTransactions: [Transaction],
        frequency: RecurringFrequency,
        isTaken: (String) -> Bool
    ) -> Transaction? {
        guard let chargeDay = ImportDuplicateDetector.dayNumber(charge.date) else { return nil }
        let window = frequency.realChargeWindowDays
        return seriesTransactions
            .compactMap { occurrence -> (Transaction, Int)? in
                guard occurrence.id != charge.id,
                      occurrence.recurringOccurrenceId != nil,
                      !isTaken(occurrence.id),
                      let day = ImportDuplicateDetector.dayNumber(occurrence.date),
                      abs(day - chargeDay) <= window
                else { return nil }
                return (occurrence, abs(day - chargeDay))
            }
            .min { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.id < $1.0.id }?
            .0
    }
}

extension RecurringFrequency {
    /// How far a real charge picked by hand may be from its planned date: half the period, so
    /// it never takes the next period's charge.
    nonisolated var realChargeWindowDays: Int {
        switch self {
        case .daily: return 0
        case .weekly: return 3
        case .monthly: return 15
        case .quarterly: return 45
        case .yearly: return 182
        }
    }
}
