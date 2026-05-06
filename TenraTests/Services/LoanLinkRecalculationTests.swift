//
//  LoanLinkRecalculationTests.swift
//  TenraTests
//
//  Tests for LoanPaymentService.recalculateAfterLinking
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct LoanLinkRecalculationTests {

    @Test func recalculateLoanState_annuity_updatesAllFields() {
        var loanInfo = LoanInfo(
            bankName: "Bank",
            loanType: .annuity,
            originalPrincipal: 20_400_000,
            remainingPrincipal: 20_400_000,
            interestRateAnnual: 12,
            termMonths: 60,
            startDate: "2021-06-15",
            monthlyPayment: 340_000,
            paymentDay: 15,
            paymentsMade: 0
        )

        let paymentDates = ["2021-07-15", "2021-08-15", "2021-09-15"]

        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &loanInfo,
            linkedPaymentCount: paymentDates.count,
            linkedPaymentDates: paymentDates
        )

        #expect(loanInfo.paymentsMade == 3)
        #expect(loanInfo.lastPaymentDate == "2021-09-15")
        #expect(loanInfo.remainingPrincipal < 20_400_000)
        #expect(loanInfo.totalInterestPaid > 0)
    }

    @Test func recalculateLoanState_installment_simpleDivision() {
        var loanInfo = LoanInfo(
            bankName: "Bank",
            loanType: .installment,
            originalPrincipal: 20_400_000,
            remainingPrincipal: 20_400_000,
            interestRateAnnual: 0,
            termMonths: 60,
            startDate: "2021-06-15",
            monthlyPayment: 340_000,
            paymentDay: 15,
            paymentsMade: 0
        )

        let paymentDates = ["2021-07-15", "2021-08-15", "2021-09-15"]

        LoanPaymentService.recalculateAfterLinking(
            loanInfo: &loanInfo,
            linkedPaymentCount: 3,
            linkedPaymentDates: paymentDates
        )

        #expect(loanInfo.paymentsMade == 3)
        #expect(loanInfo.remainingPrincipal == 19_380_000)
        #expect(loanInfo.totalInterestPaid == 0)
    }
}
