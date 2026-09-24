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
    /// Between two of the user's own accounts ("Перевод на свой счет", a deposit
    /// moving to the card). Neither spending nor income.
    case ownAccountTransfer
    case other

    /// Longest keywords first within each kind is not needed: kinds are checked in a
    /// fixed order (cash withdrawal before transfer, since "перевод наличных"-style
    /// labels are cash) and every keyword is a lowercase substring.
    static func classify(_ text: String?) -> StatementOperationKind {
        guard let text, !text.isEmpty else { return .other }
        let value = text.lowercased()
        if ownAccountKeywords.contains(where: { value.contains($0) }) { return .ownAccountTransfer }
        if cashWithdrawalKeywords.contains(where: { value.contains($0) }) { return .cashWithdrawal }
        if transferKeywords.contains(where: { value.contains($0) }) { return .transfer }
        if topUpKeywords.contains(where: { value.contains($0) }) { return .topUp }
        if purchaseKeywords.contains(where: { value.contains($0) }) { return .purchase }
        return .other
    }

    /// Operation plus the row's details. Some banks name an own-account move only in
    /// the details (Freedom: operation "Пополнение", details "Перевод вклада по
    /// Договору ..."). Purchases are never re-read: a merchant name is not a marker.
    static func classify(operation: String?, details: String) -> StatementOperationKind {
        let kind = classify(operation)
        switch kind {
        case .purchase, .cashWithdrawal, .ownAccountTransfer:
            return kind
        case .transfer, .topUp, .other:
            let value = details.lowercased()
            return ownAccountKeywords.contains(where: { value.contains($0) }) ? .ownAccountTransfer : kind
        }
    }

    /// Transfers, top-ups and cash withdrawals are money moving between accounts
    /// more often than real spending/income; the review screen labels them.
    var isMoneyMovement: Bool {
        switch self {
        case .transfer, .topUp, .cashWithdrawal, .ownAccountTransfer: return true
        case .purchase, .other: return false
        }
    }

    /// Rows that start unchecked on the review screen, because importing them as
    /// spending or income would count the same money twice: cash is spent (and
    /// logged) later, and an own-account move lands in another account the user has.
    var startsUnchecked: Bool {
        self == .cashWithdrawal || self == .ownAccountTransfer
    }

    /// Checked before every other kind: "Перевод на свой счет" is a transfer too.
    /// Russian "депозит" only; English "deposit" means an ordinary top-up.
    private static let ownAccountKeywords = [
        "свой счет", "свой счёт", "своего счета", "своего счёта", "свои счета", "своих счетов",
        "своими счетами", "между своими", "вклада по договору", "депозит",
        "власний рахунок", "власного рахунку", "своїми рахунками", "між своїми",
        "own account", "between own", "eigenes konto", "eigenen konten", "entre mis cuentas",
        "entre vos comptes", "tra i miei conti", "entre minhas contas", "kendi hesab"
    ]

    private static let cashWithdrawalKeywords = [
        "снятие", "зняття", "cash withdrawal", "atm", "bargeld", "geldautomat", "retiro",
        "retrait", "prelievo", "saque", "nakit çekim", "para çekme"
    ]
    private static let transferKeywords = [
        "перевод", "переказ", "transfer", "überweisung", "transferencia", "virement",
        "bonifico", "transferência", "havale"
    ]
    private static let topUpKeywords = [
        "пополнение", "поповнення", "поступлен", "зачислен", "надходження", "зарахування", "top up", "top-up", "topup", "einzahlung", "ingreso en",
        "recarga", "dépôt", "deposito", "depósito", "para yatırma"
    ]
    private static let purchaseKeywords = [
        "покупка", "покупки", "purchase", "kauf", "compra", "achat", "acquisto", "alışveriş"
    ]
}
