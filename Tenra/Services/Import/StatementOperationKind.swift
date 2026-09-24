//
//  StatementOperationKind.swift
//  Tenra
//
//  Classifies the text of a statement's transaction-type column ("Операция" in
//  Kaspi: Покупка / Перевод / Пополнение / Снятие). The interpreter used to drop
//  that column, so own-account transfers and cash withdrawals were imported as
//  plain spending/income with nothing to tell them apart.
//

import Foundation

nonisolated enum StatementOperationKind: Sendable, Equatable {
    case purchase
    case transfer
    case topUp
    case cashWithdrawal
    case other

    /// Longest keywords first within each kind is not needed: kinds are checked in a
    /// fixed order (cash withdrawal before transfer, since "перевод наличных"-style
    /// labels are cash) and every keyword is a lowercase substring.
    static func classify(_ text: String?) -> StatementOperationKind {
        guard let text, !text.isEmpty else { return .other }
        let value = text.lowercased()
        if cashWithdrawalKeywords.contains(where: { value.contains($0) }) { return .cashWithdrawal }
        if transferKeywords.contains(where: { value.contains($0) }) { return .transfer }
        if topUpKeywords.contains(where: { value.contains($0) }) { return .topUp }
        if purchaseKeywords.contains(where: { value.contains($0) }) { return .purchase }
        return .other
    }

    /// Transfers, top-ups and cash withdrawals are money moving between accounts
    /// more often than real spending/income; the review screen labels them.
    var isMoneyMovement: Bool {
        switch self {
        case .transfer, .topUp, .cashWithdrawal: return true
        case .purchase, .other: return false
        }
    }

    private static let cashWithdrawalKeywords = [
        "снятие", "зняття", "cash withdrawal", "atm", "bargeld", "geldautomat", "retiro",
        "retrait", "prelievo", "saque", "nakit çekim", "para çekme"
    ]
    private static let transferKeywords = [
        "перевод", "переказ", "transfer", "überweisung", "transferencia", "virement",
        "bonifico", "transferência", "havale"
    ]
    private static let topUpKeywords = [
        "пополнение", "поповнення", "top up", "top-up", "topup", "einzahlung", "ingreso en",
        "recarga", "dépôt", "deposito", "depósito", "para yatırma"
    ]
    private static let purchaseKeywords = [
        "покупка", "покупки", "purchase", "kauf", "compra", "achat", "acquisto", "alışveriş"
    ]
}
