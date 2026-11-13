//
//  FinanceToolkitCompute+SubscriptionAudit.swift
//  Tenra
//
//  `get_subscription_audit` (docs/plan-ten-agent.md, order in the data): each subscription
//  with its real charges, for the assistant to say which deserve a look. The last charges and
//  their amounts, whether the price changed between the last two, whether an active one has
//  gone longer than its interval and a half without a charge, and the subscriptions that share
//  a name. A sweep over the history, run off the main actor on the read tools' snapshot.
//  Nothing is written: pausing goes through `draft_subscription_state`, the amount and
//  cancelling stay on the subscription's screen.
//

import Foundation

extension FinanceToolkitCompute {
    nonisolated struct AuditSubscription: Sendable {
        let id: String
        let name: String
        let amount: Double
        let currency: String
        let frequency: String
        /// The usual days between charges.
        let intervalDays: Int
        let isActive: Bool
        let startDate: String
    }

    /// The most charges one subscription lists, the newest first.
    nonisolated static let auditChargeLimit = 4

    nonisolated static func subscriptionAudit(_ s: FinanceSnapshot, subscriptions: [AuditSubscription]) -> JSONValue {
        let ids = Set(subscriptions.map(\.id))
        var charges: [String: [Transaction]] = [:]
        for tx in s.transactions where tx.date <= s.today {
            guard let series = tx.recurringSeriesId, ids.contains(series) else { continue }
            charges[series, default: []].append(tx)
        }
        var byName: [String: [String]] = [:]
        for subscription in subscriptions {
            byName[subscription.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), default: []].append(subscription.id)
        }
        let today = FastDateParser.date(from: s.today) ?? s.now
        func daysSince(_ day: String) -> Int? {
            FastDateParser.date(from: day).map { Int(today.timeIntervalSince($0) / 86_400) }
        }

        let rows: [JSONValue] = subscriptions.map { subscription in
            let own = (charges[subscription.id] ?? []).sorted { $0.date > $1.date }
            let last = own.first
            let previous = own.dropFirst().first
            var change: JSONValue = .null
            if let last, let previous, previous.amount > 0, last.currency == previous.currency {
                let percent = ((last.amount - previous.amount) / previous.amount * 1000).rounded() / 10
                if abs(percent) >= 1 { change = .number(percent) }
            }
            // No charge for an interval and a half: measured from the last one, else the start.
            let quiet = daysSince(last?.date ?? subscription.startDate) ?? 0
            let missed = subscription.isActive && quiet > subscription.intervalDays * 3 / 2
            let twins = (byName[subscription.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] ?? [])
                .filter { $0 != subscription.id }
            return [
                "id": .string(subscription.id),
                "name": .string(subscription.name),
                "amount": .number(round2(subscription.amount)),
                "currency": .string(subscription.currency),
                "frequency": .string(subscription.frequency),
                "active": .bool(subscription.isActive),
                "charges_total": .number(Double(own.count)),
                "last_charge": last.map { JSONValue.string($0.date) } ?? .null,
                "days_since_last_charge": last.flatMap { daysSince($0.date) }.map { JSONValue.number(Double($0)) } ?? .null,
                "recent_charges": .array(own.prefix(auditChargeLimit).map { ["date": .string($0.date), "amount": .number(round2($0.amount))] }),
                "price_change_percent": change,
                "missed": .bool(missed),
                "same_name_as": .array(twins.map(JSONValue.string)),
            ]
        }
        return ["today": .string(s.today), "subscriptions": .array(rows)]
    }
}
