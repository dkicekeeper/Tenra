//
//  AgentPlanningTests.swift
//  TenraTests
//
//  The assistant's planning tools: `simulate_loan` prices a loan as it runs and after
//  refinancing, an extra monthly payment or an early repayment (LoanWhatIf), and
//  `project_savings` grows regular saving at an assumed return (SavingsProjection). The
//  expected figures come from an independent calculation; server/assistant/test/eval.test.ts
//  pins the same ones for the eval's copy of the formulas. All amounts are KZT.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AgentPlanningTests {

    private static let now = FastDateParser.date(from: "2026-10-28")!.addingTimeInterval(12 * 3600)

    private static func near(_ value: Double?, _ expected: Double, _ tolerance: Double = 0.02) -> Bool {
        guard let value else { return false }
        return abs(value - expected) <= tolerance
    }

    // MARK: - LoanWhatIf

    @Test func aLoanRunsOutWithItsPayment() throws {
        let plan = try LoanWhatIf.plan(principal: 1_000_000, ratePercent: 22, payment: 85_000, monthsLeft: nil)
        #expect(plan.monthsLeft == 14)
        #expect(Self.near(plan.totalInterest, 136_861.43))
    }

    @Test func refinancingLowersThePaymentAndPaysBackTheFees() throws {
        let current = try LoanWhatIf.plan(principal: 1_000_000, ratePercent: 22, payment: 85_000, monthsLeft: nil)
        let after = try LoanWhatIf.apply(LoanWhatIf.Scenario(newRatePercent: 16, fees: 20_000), to: current)
        #expect(Self.near(after.monthlyPayment, 78_776.30))
        #expect(after.monthsLeft == 14)
        #expect(Self.near(after.totalInterest, 102_868.15))
        #expect(LoanWhatIf.breakEvenMonths(fees: 20_000, current: current, scenario: after) == 4)
    }

    @Test func extraOrEarlyPaymentsShortenTheLoan() throws {
        let current = try LoanWhatIf.plan(principal: 1_000_000, ratePercent: 22, payment: 85_000, monthsLeft: nil)
        let extra = try LoanWhatIf.apply(LoanWhatIf.Scenario(extraMonthly: 15_000), to: current)
        #expect(extra.monthsLeft == 12)
        #expect(Self.near(extra.totalInterest, 114_887.97))
        let early = try LoanWhatIf.apply(LoanWhatIf.Scenario(oneOff: 300_000), to: current)
        #expect(early.monthsLeft == 10)
        #expect(Self.near(early.totalInterest, 65_789.64))
        #expect(Self.near(early.monthlyPayment, 85_000))
    }

    @Test func aLoanFromWordsGetsItsAnnuity() throws {
        let plan = try LoanWhatIf.plan(principal: 2_000_000, ratePercent: 18, payment: nil, monthsLeft: 36)
        #expect(Self.near(plan.monthlyPayment, 72_304.79))
        #expect(plan.monthsLeft == 36)
        #expect(Self.near(plan.totalInterest, 602_972.48, 0.5))
    }

    @Test func aPaymentBelowTheInterestIsRefused() {
        #expect(throws: LoanWhatIf.Failure.paymentBelowInterest) {
            _ = try LoanWhatIf.plan(principal: 1_000_000, ratePercent: 22, payment: 10_000, monthsLeft: nil)
        }
    }

    // MARK: - SavingsProjection

    @Test func savingsCompoundMonthly() {
        let result = SavingsProjection.project(start: 0, monthly: 50_000, annualReturnPercent: 8, years: 10, inflationPercent: 6)
        #expect(Self.near(result.finalAmount, 9_006_213.66, 0.5))
        #expect(result.contributed == 6_000_000)
        #expect(Self.near(result.finalAmountReal, 5_029_022.67, 0.5))
        #expect(result.years.count == 10)
        #expect(Self.near(result.years.first?.total, 621_694.32, 0.5))
    }

    // MARK: - Tools

    private static func makeToolkit() -> (FinanceToolkit, TransactionStore) {
        let defaults = UserDefaults(suiteName: "tests.\(UUID().uuidString)")!
        let repo = UserDefaultsRepository(userDefaults: defaults)
        let store = TransactionStore(
            repository: repo,
            balanceCoordinator: BalanceCoordinator(repository: repo),
            recurringStore: RecurringStore(repository: repo)
        )
        let loan = LoanInfo(
            bankName: "Bank", loanType: .annuity,
            originalPrincipal: 1_500_000, remainingPrincipal: 1_000_000,
            interestRateAnnual: 22, termMonths: 24,
            startDate: "2026-01-01", monthlyPayment: 85_000, paymentDay: 5
        )
        store.accounts = [
            Account(id: "acc_kaspi", name: "Kaspi Gold", currency: "KZT", balance: 260_850),
            Account(id: "acc_car", name: "Автокредит", currency: "KZT", loanInfo: loan, initialBalance: 1_500_000, balance: 1_000_000),
        ]
        let toolkit = FinanceToolkit(store: store, learned: VoiceLearningStore(defaults: defaults), now: { now })
        return (toolkit, store)
    }

    @Test func simulateLoanReadsTheLoanFromTheApp() async throws {
        let (toolkit, store) = Self.makeToolkit()
        _ = store
        let output = await toolkit.execute(name: "simulate_loan", input: ["account_id": "acc_car", "new_rate_percent": 16, "fees": 20_000])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["currency"] == "KZT")
        #expect(value["loan"] == "Автокредит")
        #expect(value.value(atPath: "current.months_left") == .number(14))
        #expect(Self.near(value["interest_saved"]?.numberValue, 13_993.29))
        #expect(value["break_even_months"] == .number(4))
        #expect(Self.near(value["monthly_payment_change"]?.numberValue, -6_223.70))
    }

    @Test func simulateLoanTakesALoanFromWordsAndChecksItsInput() async throws {
        let (toolkit, store) = Self.makeToolkit()
        _ = store
        let manual = await toolkit.execute(name: "simulate_loan", input: ["principal": 2_000_000, "rate_percent": 18, "months_left": 36])
        let value = try #require(manual.value, "\(manual.error ?? "")")
        #expect(value["scenario"] == .null)
        #expect(Self.near(value.value(atPath: "current.monthly_payment")?.numberValue, 72_304.79))

        let notALoan = await toolkit.execute(name: "simulate_loan", input: ["account_id": "acc_kaspi"])
        #expect(notALoan.error == "Account acc_kaspi is not a loan.")
        let missing = await toolkit.execute(name: "simulate_loan", input: ["principal": 2_000_000])
        #expect(missing.error?.contains("principal, rate_percent and months_left") == true)
        let tooMuch = await toolkit.execute(name: "simulate_loan", input: ["account_id": "acc_car", "one_off": 2_000_000])
        #expect(tooMuch.error?.contains("covers the whole loan") == true)
    }

    @Test func projectSavingsGivesAYearlySeries() async throws {
        let (toolkit, store) = Self.makeToolkit()
        _ = store
        let output = await toolkit.execute(name: "project_savings", input: ["monthly": 50_000, "years": 10, "annual_return_percent": 8, "inflation_percent": 6])
        let value = try #require(output.value, "\(output.error ?? "")")
        #expect(value["currency"] == "KZT")
        #expect(Self.near(value["final_amount"]?.numberValue, 9_006_213.66))
        #expect(value["contributed"] == .number(6_000_000))
        #expect(value.value(atPath: "series.0.key") == "2027-10")
        #expect(value.value(atPath: "series.9.key") == "2036-10")

        let bad = await toolkit.execute(name: "project_savings", input: ["monthly": 0, "years": 10, "annual_return_percent": 8])
        #expect(bad.error?.contains("one of them must be above zero") == true)
    }

    @Test func monthsAndYearsAreCountsInCards() {
        #expect(AgentReplyData.kind(ofPath: "current.months_left") == .count)
        #expect(AgentReplyData.kind(ofPath: "break_even_months") == .count)
        #expect(AgentReplyData.kind(ofPath: "years") == .count)
        #expect(AgentReplyData.kind(ofPath: "scenario.rate_percent") == .percent)
        #expect(AgentReplyData.kind(ofPath: "monthly_payment_change") == .amount)
    }
}
