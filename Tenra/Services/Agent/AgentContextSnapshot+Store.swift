//
//  AgentContextSnapshot+Store.swift
//  Tenra
//
//  The <app_context> snapshot from the app's own state: today, the app's language, the base
//  currency, the accounts and categories the model may name by id, and the remembered facts.
//

import Foundation

extension AgentContextSnapshot {
    @MainActor
    init(store: TransactionStore, facts: [AgentFact] = [], now: Date = Date()) {
        self.init(
            today: now,
            timeZone: .current,
            locale: Bundle.main.preferredLocalizations.first ?? "en",
            baseCurrency: store.baseCurrency,
            accounts: store.accounts.map { account in
                Account(
                    id: account.id,
                    name: account.name,
                    currency: account.currency,
                    kind: account.isLoan ? "loan" : account.isDeposit ? "deposit" : "regular"
                )
            },
            categories: store.categories
                .filter { $0.type == .expense || $0.type == .income }
                .map { Category(id: $0.id, name: $0.name, isIncome: $0.type == .income) },
            facts: facts.map { Fact(id: $0.id, text: $0.text) }
        )
    }
}
