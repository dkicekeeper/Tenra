//
//  ScreenshotDemoDatasetTests.swift
//  TenraTests
//
//  The demo data the App Store frames and the Threads videos are shot on (ScreenshotDemoSeeder):
//  its loan reads as a real one would, the month paid and the interest of the payments made counted.
//

#if DEBUG

import Foundation
import Testing
@testable import Tenra

@MainActor
struct ScreenshotDemoDatasetTests {

    @Test("The demo loan's month is paid once its payment went out, in any currency",
          arguments: ["KZT", "EUR", "JPY"])
    func loanMonthIsPaid(currency: String) throws {
        let dataset = ScreenshotDemoDataset(currency: currency)
        let loan = try #require(dataset.accounts.first { $0.id == "demo-account-loan" })
        let payments = dataset.transactions.filter { $0.type == .loanPayment && $0.targetAccountId == loan.id }
        let latest = try #require(payments.map(\.date).max())
        let today = try #require(FastDateParser.date(from: latest))

        let status = LoanMonthStatusService.status(
            loan: loan,
            loanTransactions: payments,
            today: today,
            rates: RateSnapshot(rates: [:])
        )
        guard case .paid? = status else {
            Issue.record("the month of \(latest) is \(String(describing: status))")
            return
        }
    }

    @Test("The demo loan counts the interest its payments made took")
    func loanInterestPaid() throws {
        let dataset = ScreenshotDemoDataset(currency: "KZT")
        let info = try #require(dataset.accounts.first { $0.id == "demo-account-loan" }?.loanInfo)
        let schedule = LoanPaymentService.generateAmortizationSchedule(loanInfo: info)
        let expected = schedule.prefix(info.paymentsMade).reduce(Decimal(0)) { $0 + $1.interest }
        #expect(info.totalInterestPaid > 0)
        #expect(info.totalInterestPaid == expected)
    }

    @Test("The demo apartment gained, is valued from listings this month and rented out for a year")
    func apartment() throws {
        let dataset = ScreenshotDemoDataset(currency: "KZT")
        let apartment = try #require(dataset.assets.first { $0.kind == .apartment })
        let value = try #require(AssetValuationMath.currentValue(of: apartment))
        let price = try #require(apartment.purchasePrice)
        #expect(value > price)
        #expect(apartment.valuations.last?.listings?.count == 14)
        #expect(!AssetValuationMath.isStale(apartment))

        let category = try #require(dataset.categories.first { $0.id == apartment.incomeLink?.categoryId })
        #expect(category.type == .income)
        let today = FastDateParser.string(from: Date())
        let rents = dataset.transactions.filter { $0.type == .income && $0.category == category.name }
        #expect(rents.count == 12)
        #expect(rents.allSatisfy { $0.date <= today })
    }
}

#endif
