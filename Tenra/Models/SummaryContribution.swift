//
//  SummaryContribution.swift
//  Tenra
//
//  The SINGLE rule for how a transaction contributes to a Summary card
//  (income / expense / internal-transfer totals + planned expenses).
//
//  Historically three summary paths (SummaryCalculator, TransactionQueryService,
//  and a now-deleted TransactionStore.summary) each had their own switch over
//  TransactionType, and they DISAGREED — most visibly on deposit-interest accrual
//  (counted as income on the home screen, excluded on the history screen). Routing
//  every path through this one function makes them structurally consistent.
//

import Foundation

/// Which Summary bucket a transaction falls into, given whether it is future-dated.
enum SummaryContribution: Equatable {
    case income
    case expense
    case internalTransfer
    /// Future-dated expense/loan payment — surfaced as `Summary.plannedAmount`, not realized.
    case plannedExpense
    /// Does not affect any summary total (e.g. deposit top-up/withdrawal, or a future
    /// income/transfer that is neither realized nor a planned expense).
    case ignored
}

extension TransactionType {
    /// THE classification rule shared by every summary calculator.
    ///
    /// Realized (`isFuture == false`):
    /// - income + deposit interest accrual → `.income`
    /// - expense + loan payments → `.expense`
    /// - internal transfer → `.internalTransfer`
    /// - deposit top-up / withdrawal → `.ignored` (they move principal, not income/expense)
    ///
    /// Future (`isFuture == true`): only expense and loan payment become `.plannedExpense`;
    /// everything else future is `.ignored` (realized figures exclude future-dated tx).
    func summaryContribution(isFuture: Bool) -> SummaryContribution {
        if isFuture {
            return (self == .expense || self == .loanPayment) ? .plannedExpense : .ignored
        }
        switch self {
        case .income, .depositInterestAccrual:
            return .income
        case .expense, .loanPayment, .loanEarlyRepayment:
            return .expense
        case .internalTransfer:
            return .internalTransfer
        case .depositTopUp, .depositWithdrawal:
            return .ignored
        }
    }
}
