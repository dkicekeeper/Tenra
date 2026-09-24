//
//  LoanScheduleReplayTests.swift
//  TenraTests
//
//  A "reduce payment" early repayment overwrites LoanInfo.monthlyPayment. The
//  schedule used to replay every month with that NEW payment, so all rows before
//  the repayment were wrong and markPaymentsPaid wrote a wrong remaining principal.
//  Also pins the next payment date for payment days 29-31.
//

import Testing
import Foundation
@testable import Tenra

struct LoanScheduleReplayTests {

    private func loan(termMonths: Int = 12, rate: Decimal = 12, paymentDay: Int = 1) -> LoanInfo {
        LoanInfo(
            bankName: "TestBank",
            loanType: rate > 0 ? .annuity : .installment,
            originalPrincipal: 1_200_000,
            remainingPrincipal: 1_200_000,
            interestRateAnnual: rate,
            termMonths: termMonths,
            startDate: "2026-01-01",
            paymentDay: paymentDay,
            paymentsMade: 0
        )
    }

    /// Advance a loan past `rows` scheduled payments, then apply an early repayment.
    private func afterEarlyRepayment(_ type: EarlyRepaymentType, legacy: Bool = false) -> (before: [LoanPaymentService.AmortizationEntry], after: [LoanPaymentService.AmortizationEntry], info: LoanInfo) {
        var info = loan()
        let before = LoanPaymentService.generateAmortizationSchedule(loanInfo: info)
        info.paymentsMade = 6
        info.remainingPrincipal = before[5].remainingBalance
        LoanPaymentService.applyEarlyRepayment(loanInfo: &info, amount: 300_000, date: "2026-07-10", type: type)
        if legacy {
            // Simulate a repayment recorded before `paymentBefore` existed.
            info.earlyRepayments = info.earlyRepayments.map {
                EarlyRepayment(date: $0.date, amount: $0.amount, type: $0.type, note: $0.note, paymentBefore: nil)
            }
        }
        return (before, LoanPaymentService.generateAmortizationSchedule(loanInfo: info), info)
    }

    private func close(_ a: Decimal, _ b: Decimal, _ tolerance: Decimal = 0.02) -> Bool {
        abs(NSDecimalNumber(decimal: a - b).doubleValue) <= NSDecimalNumber(decimal: tolerance).doubleValue
    }

    @Test func reducePaymentKeepsPastRows() {
        let (before, after, info) = afterEarlyRepayment(.reducePayment)
        #expect(info.earlyRepayments.first?.paymentBefore != nil)
        for i in 0..<6 {
            #expect(close(after[i].payment, before[i].payment), "row \(i + 1) payment changed")
            #expect(close(after[i].remainingBalance, before[i].remainingBalance), "row \(i + 1) balance changed")
        }
        #expect(close(after[6].payment, info.monthlyPayment, 1), "row 7 uses the reduced payment")
        #expect(after[6].payment < before[6].payment)
        #expect(close(after.last?.remainingBalance ?? -1, 0, 1))
    }

    @Test func legacyReducePaymentIsReconstructed() {
        let (before, after, _) = afterEarlyRepayment(.reducePayment, legacy: true)
        for i in 0..<6 {
            #expect(close(after[i].payment, before[i].payment, 1), "row \(i + 1) payment changed")
        }
    }

    @Test func reduceTermKeepsPaymentConstant() {
        let (before, after, _) = afterEarlyRepayment(.reduceTerm)
        for i in 0..<6 {
            #expect(close(after[i].payment, before[i].payment))
        }
        #expect(after.count < before.count, "term got shorter")
    }

    @Test func earlyRepaymentJSONWithoutPaymentBeforeDecodes() throws {
        let json = #"{"date":"2026-07-10","amount":300000,"type":"reduce_payment","note":null}"#
        let decoded = try JSONDecoder().decode(EarlyRepayment.self, from: Data(json.utf8))
        #expect(decoded.paymentBefore == nil)
        #expect(decoded.type == .reducePayment)
    }

    // MARK: - Next payment date

    private func next(paymentDay: Int, today: String) -> String? {
        let formatter = DateFormatters.dateFormatter
        let date = LoanPaymentService.nextPaymentDate(
            loanInfo: loan(paymentDay: paymentDay),
            today: formatter.date(from: today)!,
            calendar: .current
        )
        return date.map { formatter.string(from: $0) }
    }

    @Test func paymentDay31ClampsPerMonth() {
        #expect(next(paymentDay: 31, today: "2026-02-28") == "2026-02-28")
        #expect(next(paymentDay: 31, today: "2026-03-01") == "2026-03-31")
        #expect(next(paymentDay: 31, today: "2026-04-30") == "2026-04-30")
    }

    @Test func passedPaymentMovesToNextMonth() {
        #expect(next(paymentDay: 15, today: "2026-05-16") == "2026-06-15")
        #expect(next(paymentDay: 31, today: "2026-03-31") == "2026-03-31")
    }
}
