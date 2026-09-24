//
//  LegacyDepositDiagnostics.swift
//  Tenra
//
//  DEBUG-only, read-only. Deposits converted from a regular account before the
//  `conversionTimestamp` fix have that marker nil and fall back to the startDate
//  cutoff, so inherited pre-conversion income/expense dated after startDate can be
//  re-summed (docs/domains/deposits.md: "stay corrupted until a one-shot recovery").
//  Before designing that recovery, this surfaces which deposits look affected, in
//  Settings > Experiments. It changes nothing.
//

#if DEBUG
import Foundation

nonisolated enum LegacyDepositDiagnostics {

    struct Report: Identifiable, Equatable {
        let id: String
        let name: String
        let startDate: String
        let initialPrincipal: Decimal
        let accruedThisPeriod: Decimal
        /// Plain income/expense/transfer rows on the deposit dated after startDate. A fresh
        /// deposit only gets deposit-typed rows there; plain rows mean inherited history.
        let plainRowsAfterStart: Int
        let isSuspicious: Bool
    }

    /// Reports for deposits WITHOUT `conversionTimestamp` (fresh or legacy-converted).
    static func inspect(accounts: [Account], transactions: [Transaction]) -> [Report] {
        accounts.compactMap { account -> Report? in
            guard let info = account.depositInfo, info.conversionTimestamp == nil else { return nil }
            let plainAfterStart = transactions.filter { tx in
                (tx.accountId == account.id || tx.targetAccountId == account.id)
                    && tx.date > info.startDate
                    && (tx.type == .income || tx.type == .expense || tx.type == .internalTransfer)
            }.count
            return Report(
                id: account.id,
                name: account.name,
                startDate: info.startDate,
                initialPrincipal: info.initialPrincipal,
                accruedThisPeriod: info.interestAccruedForCurrentPeriod,
                plainRowsAfterStart: plainAfterStart,
                isSuspicious: info.interestAccruedForCurrentPeriod < 0 || plainAfterStart > 0
            )
        }
    }
}
#endif
