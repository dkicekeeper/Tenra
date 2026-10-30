//
//  AgentContextSnapshot+Store.swift
//  Tenra
//
//  The <app_context> snapshot from the app's own state: today, the app's language, the base
//  currency, the accounts and categories the model may name by id, the remembered facts, the
//  savings goals, the open personal debts and the held assets.
//

import Foundation

extension AgentContextSnapshot {
    @MainActor
    init(
        store: TransactionStore,
        facts: [AgentFact] = [],
        goals: [SavingsGoal] = [],
        debts: [PersonalDebt] = [],
        assets: [Asset] = [],
        now: Date = Date()
    ) {
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
            facts: facts.map { Fact(id: $0.id, text: $0.text) },
            goals: goals.map { Goal(id: $0.id, name: $0.name, currency: $0.currency) },
            debts: debts.filter { !$0.isSettled }.map {
                Debt(id: $0.id, person: $0.person, direction: FinanceToolkit.wire($0.direction), currency: $0.currency)
            },
            assets: assets.filter { !$0.isSold }.map { OwnedAsset(id: $0.id, name: $0.name, kind: $0.kind.rawValue, currency: $0.currency) }
        )
    }
}
