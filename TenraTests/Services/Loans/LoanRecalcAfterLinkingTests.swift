//
//  LoanRecalcAfterLinkingTests.swift
//  TenraTests
//
//  M-4: recalculateAfterLinking must reduce the loan principal by the ACTUAL linked
//  payment amounts (split into interest/principal), not by the annuity monthlyPayment.
//  Since loan account balance now derives from remainingPrincipal (C-3), an inaccurate
//  remainingPrincipal here would directly mis-state the loan balance.
//

import Testing
import Foundation
@testable import Tenra

struct LoanRecalcAfterLinkingTests {

    private func annuityLoan(monthlyPayment: Decimal) -> LoanInfo {
        LoanInfo(
            bankName: "B", loanType: .annuity,
            originalPrincipal: 1_000_000, interestRateAnnual: 0,
            termMonths: 10, startDate: "2026-01-01",
            monthlyPayment: monthlyPayment, paymentDay: 1
        )
    }

    @Test("annuity: principal reduces by actual linked amounts, not monthlyPayment")
    func annuityUsesActualAmounts() {
        var info = annuityLoan(monthlyPayment: 100_000)
        // Two real payments of 50_000 each (different from the 100_000 annuity payment).
        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &info,
            linkedPayments: [("2026-02-01", 50_000), ("2026-03-01", 50_000)]
        )
        // 0% interest → principal drops by the actual amounts: 1_000_000 − 100_000.
        #expect(info.remainingPrincipal == 900_000)
        #expect(info.paymentsMade == 2)
        #expect(info.lastPaymentDate == "2026-03-01")
    }

    @Test("installment: principal reduces by the sum of actual amounts")
    func installmentUsesActualAmounts() {
        var info = LoanInfo(
            bankName: "B", loanType: .installment,
            originalPrincipal: 1_000_000, interestRateAnnual: 0,
            termMonths: 10, startDate: "2026-01-01",
            monthlyPayment: 100_000, paymentDay: 1
        )
        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &info,
            linkedPayments: [("2026-02-01", 30_000), ("2026-03-01", 70_000)]
        )
        #expect(info.remainingPrincipal == 900_000)
    }
}
