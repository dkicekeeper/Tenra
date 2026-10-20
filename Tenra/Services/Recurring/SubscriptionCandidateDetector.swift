//
//  SubscriptionCandidateDetector.swift
//  Tenra
//
//  "Looks like a subscription" (docs/plan-auto-capture.md §7): merchants charged about
//  once a month for about the same amount, not tracked by any subscription yet. The
//  subscriptions screen offers each as a prefilled new subscription whose first charge is
//  the next expected one, so nothing already recorded is generated again.
//
//  A merchant qualifies when its latest charges, at least three, follow each other every
//  26-35 days, each within 15 % of the latest amount, and the latest one is at most 40 days
//  old. A second charge inside the month breaks the run, so a shop visited every week
//  never qualifies. Only one-off expenses count (no series), up to today.
//
//  Pure and `nonisolated`: the screen runs it over the whole history off the main actor.
//

import Foundation

nonisolated enum SubscriptionCandidateDetector {

    struct Candidate: Sendable, Equatable, Identifiable {
        /// The normalized merchant: what a dismissal remembers.
        let merchant: String
        /// The latest charge's description, as written.
        let sampleDescription: String
        let amount: Double
        let currency: String
        let category: String
        let accountId: String?
        /// "yyyy-MM-dd" of the latest charge.
        let lastDate: String
        /// A month after the latest charge.
        let nextDate: Date
        let charges: Int

        var id: String { merchant + "|" + currency }
    }

    static let minimumCharges = 3
    static let intervalDays = 26...35
    static let amountTolerance = 0.15
    static let staleAfterDays = 40
    static let limit = 5

    /// - Parameters:
    ///   - trackedDescriptions: the descriptions of the subscriptions already kept; a merchant
    ///     sharing a brand word with one (its billing company included) is not offered.
    ///   - dismissed: merchants the user said are not subscriptions.
    static func candidates(
        in transactions: [Transaction],
        trackedDescriptions: [String],
        dismissed: Set<String>,
        now: Date = Date()
    ) -> [Candidate] {
        let todayNumber = dayNumber(of: now)
        let tracked = trackedDescriptions.map { WalletPaymentResolver.billedWords($0) }

        var groups: [String: [(tx: Transaction, day: Int)]] = [:]
        for tx in transactions where tx.type == .expense && tx.recurringSeriesId == nil {
            let merchant = CategorySuggestionService.normalizedMerchant(tx.description)
            guard merchant.count >= CategorySuggestionService.minimumMerchantLength,
                  !dismissed.contains(merchant),
                  let day = ImportDuplicateDetector.dayNumber(tx.date),
                  day <= todayNumber else { continue }
            groups[merchant + "|" + tx.currency, default: []].append((tx, day))
        }

        var result: [Candidate] = []
        for (_, charges) in groups where charges.count >= minimumCharges {
            let sorted = charges.sorted { $0.day != $1.day ? $0.day < $1.day : $0.tx.id < $1.tx.id }
            guard let latest = sorted.last, todayNumber - latest.day <= staleAfterDays else { continue }

            // The run of monthly charges that ends with the latest one.
            var run = 1
            var index = sorted.count - 1
            while index > 0 {
                let previous = sorted[index - 1]
                guard intervalDays.contains(sorted[index].day - previous.day),
                      abs(previous.tx.amount - latest.tx.amount) <= amountTolerance * latest.tx.amount else { break }
                run += 1
                index -= 1
            }
            guard run >= minimumCharges else { continue }

            let merchant = CategorySuggestionService.normalizedMerchant(latest.tx.description)
            let words = WalletPaymentResolver.brandWords(latest.tx.description)
            guard !words.isEmpty, !tracked.contains(where: { !$0.isDisjoint(with: words) }) else { continue }

            guard let lastDate = FastDateParser.date(from: latest.tx.date),
                  let nextDate = Calendar.current.date(byAdding: .month, value: 1, to: lastDate) else { continue }
            result.append(Candidate(
                merchant: merchant,
                sampleDescription: latest.tx.description,
                amount: latest.tx.amount,
                currency: latest.tx.currency,
                category: latest.tx.category,
                accountId: latest.tx.accountId,
                lastDate: latest.tx.date,
                nextDate: nextDate,
                charges: run
            ))
        }
        return Array(
            result
                .sorted { $0.lastDate != $1.lastDate ? $0.lastDate > $1.lastDate : $0.id < $1.id }
                .prefix(limit)
        )
    }

    /// The local day a moment falls on, numbered as `ImportDuplicateDetector.dayNumber`
    /// numbers a "yyyy-MM-dd" key.
    static func dayNumber(of date: Date) -> Int {
        let local = date.timeIntervalSinceReferenceDate + Double(TimeZone.current.secondsFromGMT(for: date))
        return Int((local / 86_400).rounded(.down))
    }
}

/// Merchants the user said are not subscriptions ("Not a subscription" on a candidate).
enum SubscriptionCandidateDismissals {
    private static let key = "subscriptionCandidates.dismissed.v1"

    static func all(defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    static func dismiss(_ merchant: String, defaults: UserDefaults = .standard) {
        var merchants = all(defaults: defaults)
        guard merchants.insert(merchant).inserted else { return }
        defaults.set(merchants.sorted(), forKey: key)
    }
}
