//
//  LoanPaymentServiceTests.swift
//  AIFinanceManagerTests
//
//  Unit tests for LoanPaymentService — annuity formula, payment breakdown,
//  amortization schedule, progress helpers. All tests are pure (no CoreData).
//  TEST-05
//

import Testing
import Foundation
@testable import AIFinanceManager

@Suite("LoanPaymentService Tests")
struct LoanPaymentServiceTests {

    // MARK: - Helpers

    /// Minimal LoanInfo for testing progress / remaining helpers.
    private func makeLoanInfo(
        originalPrincipal: Decimal = 1_000_000,
        remainingPrincipal: Decimal? = nil,
        annualRate: Decimal = 12,
        termMonths: Int = 12,
        paymentsMade: Int = 0,
        paymentDay: Int = 15,
        startDate: String = "2026-01-15"
    ) -> LoanInfo {
        LoanInfo(
            bankName: "TestBank",
            loanType: annualRate > 0 ? .annuity : .installment,
            originalPrincipal: originalPrincipal,
            remainingPrincipal: remainingPrincipal ?? originalPrincipal,
            interestRateAnnual: annualRate,
            termMonths: termMonths,
            startDate: startDate,
            paymentDay: paymentDay,
            paymentsMade: paymentsMade
        )
    }

    // MARK: - calculateMonthlyPayment

    @Test("Annuity: 1M KZT, 12% annual, 12 months ≈ 88,849 KZT/month")
    func testAnnuityMonthlyPayment() {
        let payment = LoanPaymentService.calculateMonthlyPayment(
            principal: 1_000_000,
            annualRate: 12,
            termMonths: 12
        )
        // P = L × [r(1+r)^n] / [(1+r)^n − 1], r=0.01, n=12 → ≈ 88,848.79
        let paymentDouble = NSDecimalNumber(decimal: payment).doubleValue
        #expect(abs(paymentDouble - 88848.79) < 1.0,
                "Expected ~88848.79, got \(paymentDouble)")
    }

    @Test("Installment (0% rate): equal principal split")
    func testInstallmentMonthlyPayment() {
        let payment = LoanPaymentService.calculateMonthlyPayment(
            principal: 600_000,
            annualRate: 0,
            termMonths: 12
        )
        #expect(payment == 50_000, "600K / 12 months = 50K")
    }

    @Test("Zero termMonths returns 0")
    func testZeroTermReturnsZero() {
        let payment = LoanPaymentService.calculateMonthlyPayment(
            principal: 500_000,
            annualRate: 12,
            termMonths: 0
        )
        #expect(payment == 0)
    }

    @Test("Single-month loan: full principal + one month interest")
    func testOneMonthLoan() {
        let payment = LoanPaymentService.calculateMonthlyPayment(
            principal: 100_000,
            annualRate: 12,
            termMonths: 1
        )
        // monthlyRate = 1%, interest = 1000, principal = 100000, total = 101000
        #expect(payment == 101_000)
    }

    // MARK: - paymentBreakdown

    @Test("Breakdown: first month of 1M at 12% annual")
    func testPaymentBreakdownFirstMonth() {
        let monthlyPayment = LoanPaymentService.calculateMonthlyPayment(
            principal: 1_000_000,
            annualRate: 12,
            termMonths: 12
        )
        let (interest, principal) = LoanPaymentService.paymentBreakdown(
            remainingPrincipal: 1_000_000,
            annualRate: 12,
            monthlyPayment: monthlyPayment
        )
        // monthlyRate = 12/100/12 = 0.01 → interest = 1,000,000 × 0.01 = 10,000
        #expect(interest == 10_000, "First-month interest on 1M @ 1%/month = 10000")
        let principalDouble = NSDecimalNumber(decimal: principal).doubleValue
        let paymentDouble = NSDecimalNumber(decimal: monthlyPayment).doubleValue
        #expect(abs(principalDouble - (paymentDouble - 10_000)) < 0.02,
                "principal = payment - interest")
    }

    @Test("Breakdown: zero rate → all principal, zero interest")
    func testPaymentBreakdownZeroRate() {
        let (interest, principal) = LoanPaymentService.paymentBreakdown(
            remainingPrincipal: 500_000,
            annualRate: 0,
            monthlyPayment: 50_000
        )
        #expect(interest == 0)
        #expect(principal == 50_000)
    }

    @Test("Breakdown: interest + principal sum equals monthly payment")
    func testBreakdownSumsToPayment() {
        let monthlyPayment: Decimal = 30_000
        let (interest, principal) = LoanPaymentService.paymentBreakdown(
            remainingPrincipal: 200_000,
            annualRate: 18,
            monthlyPayment: monthlyPayment
        )
        let sum = NSDecimalNumber(decimal: interest + principal).doubleValue
        let expected = NSDecimalNumber(decimal: monthlyPayment).doubleValue
        #expect(abs(sum - expected) < 0.02, "interest + principal must equal monthly payment")
    }

    // MARK: - progressPercentage

    @Test("Progress 0% when nothing paid (remaining = original)")
    func testProgressZero() {
        let loan = makeLoanInfo(originalPrincipal: 1_000_000, remainingPrincipal: 1_000_000)
        let progress = LoanPaymentService.progressPercentage(loanInfo: loan)
        #expect(abs(progress) < 0.001)
    }

    @Test("Progress 50% when half paid")
    func testProgressHalf() {
        let loan = makeLoanInfo(originalPrincipal: 1_000_000, remainingPrincipal: 500_000)
        let progress = LoanPaymentService.progressPercentage(loanInfo: loan)
        #expect(abs(progress - 0.5) < 0.001)
    }

    @Test("Progress 100% when fully paid (remaining = 0)")
    func testProgressFull() {
        let loan = makeLoanInfo(originalPrincipal: 1_000_000, remainingPrincipal: 0)
        let progress = LoanPaymentService.progressPercentage(loanInfo: loan)
        #expect(abs(progress - 1.0) < 0.001)
    }

    @Test("Progress returns 1.0 for zero original principal (guard case)")
    func testProgressZeroOriginal() {
        let loan = makeLoanInfo(originalPrincipal: 0, remainingPrincipal: 0)
        let progress = LoanPaymentService.progressPercentage(loanInfo: loan)
        #expect(progress == 1.0)
    }

    // MARK: - remainingPayments

    @Test("Remaining = term - payments made")
    func testRemainingPayments() {
        let loan = makeLoanInfo(termMonths: 24, paymentsMade: 10)
        #expect(LoanPaymentService.remainingPayments(loanInfo: loan) == 14)
    }

    @Test("Remaining = 0 when all payments made")
    func testRemainingPaymentsFullyPaid() {
        let loan = makeLoanInfo(termMonths: 12, paymentsMade: 12)
        #expect(LoanPaymentService.remainingPayments(loanInfo: loan) == 0)
    }

    @Test("Remaining clamps to 0 (never negative)")
    func testRemainingPaymentsNonNegative() {
        let loan = makeLoanInfo(termMonths: 12, paymentsMade: 15)
        #expect(LoanPaymentService.remainingPayments(loanInfo: loan) == 0)
    }

    // MARK: - totalInterestOverLife

    @Test("Total interest over life is positive for annuity loan")
    func testTotalInterestPositive() {
        let loan = makeLoanInfo(originalPrincipal: 1_000_000, annualRate: 12, termMonths: 12)
        let totalInterest = LoanPaymentService.totalInterestOverLife(loanInfo: loan)
        #expect(totalInterest > 0, "Non-zero rate must produce positive interest")
    }

    @Test("Total interest is zero for zero-rate installment")
    func testTotalInterestZeroForInstallment() {
        let loan = makeLoanInfo(
            originalPrincipal: 600_000,
            annualRate: 0,
            termMonths: 12,
            paymentsMade: 0
        )
        let totalInterest = LoanPaymentService.totalInterestOverLife(loanInfo: loan)
        #expect(totalInterest == 0)
    }

    // MARK: - Amortization schedule shape

    @Test("Amortization schedule has exactly termMonths entries")
    func testScheduleEntryCount() {
        let loan = makeLoanInfo(originalPrincipal: 500_000, annualRate: 10, termMonths: 6)
        let schedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: loan)
        #expect(schedule.count == 6)
    }

    @Test("Amortization final balance reaches zero (within 1 tenge)")
    func testScheduleFinalBalanceZero() {
        let loan = makeLoanInfo(originalPrincipal: 600_000, annualRate: 0, termMonths: 12)
        let schedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: loan)
        let lastBalance = schedule.last.map { NSDecimalNumber(decimal: $0.remainingBalance).doubleValue } ?? 999
        #expect(abs(lastBalance) < 1.0, "Final balance must be near zero, got \(lastBalance)")
    }
}
