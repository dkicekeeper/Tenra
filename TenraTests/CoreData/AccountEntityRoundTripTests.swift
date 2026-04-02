//
//  AccountEntityRoundTripTests.swift
//  AIFinanceManagerTests
//
//  CoreData round-trip tests for AccountEntity:
//    - Scalar fields (id, name, currency, balance)
//    - DepositInfo JSON serialization via depositInfoData (critical P0 fix from 2026-03-05)
//    - LoanInfo JSON serialization via loanInfoData
//    - IconSource JSON serialization via iconSourceData
//
//  Uses an isolated in-memory NSPersistentContainer (same pattern as CoreDataRoundTripTests).
//  TEST-07
//

import Testing
import CoreData
import Foundation
@testable import AIFinanceManager

@Suite("AccountEntity Round-Trip Tests", .serialized)
struct AccountEntityRoundTripTests {

    // MARK: - In-Memory Container

    private func makeContainer() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "AIFinanceManager")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        desc.url = URL(string: "memory://\(UUID().uuidString)")
        desc.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [desc]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let error = loadError { throw error }
        return container
    }

    // MARK: - Account Factory

    private func makeAccount(
        id: String = UUID().uuidString,
        name: String = "Test Account",
        currency: String = "KZT",
        balance: Double = 100_000,
        iconSource: IconSource? = nil,
        depositInfo: DepositInfo? = nil,
        loanInfo: LoanInfo? = nil
    ) -> Account {
        Account(
            id: id,
            name: name,
            currency: currency,
            iconSource: iconSource,
            depositInfo: depositInfo,
            loanInfo: loanInfo,
            createdDate: Date(),
            shouldCalculateFromTransactions: false,
            initialBalance: balance,
            balance: balance
        )
    }

    private func makeDepositInfo(
        bankName: String = "TestBank",
        principal: Decimal = 1_000_000,
        rate: Decimal = 12,
        postingDay: Int = 5
    ) -> DepositInfo {
        DepositInfo(
            bankName: bankName,
            principalBalance: principal,
            capitalizationEnabled: true,
            interestAccruedNotCapitalized: 0,
            interestRateAnnual: rate,
            interestPostingDay: postingDay,
            lastInterestCalculationDate: "2026-01-01",
            lastInterestPostingMonth: "2026-01-01"
        )
    }

    // MARK: - Test A: Scalar fields

    @Test("Test A: Scalar fields round-trip (id, name, currency, balance)")
    func testScalarFieldsRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let account = makeAccount(id: "acc-test-1", name: "Wallet", currency: "USD", balance: 5_000)

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let result = try #require(loaded)
        #expect(result.id == "acc-test-1")
        #expect(result.name == "Wallet")
        #expect(result.currency == "USD")
        #expect(abs(result.balance - 5_000) < 0.01)
    }

    // MARK: - Test B: DepositInfo JSON serialization (P0 fix from 2026-03-05)

    @Test("Test B: DepositInfo survives JSON encode → CoreData → decode round-trip")
    func testDepositInfoRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let depositInfo = makeDepositInfo(bankName: "Kaspi", principal: 2_000_000, rate: 14, postingDay: 15)
        let account = makeAccount(depositInfo: depositInfo)

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let result = try #require(loaded)
        let info = try #require(result.depositInfo, "depositInfo must survive round-trip")
        #expect(info.bankName == "Kaspi")
        #expect(info.principalBalance == 2_000_000)
        #expect(info.interestRateAnnual == 14)
        #expect(info.interestPostingDay == 15)
        #expect(info.capitalizationEnabled == true)
        #expect(info.lastInterestCalculationDate == "2026-01-01")
    }

    @Test("Test C: nil depositInfo stays nil after round-trip")
    func testNilDepositInfoStaysNil() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let account = makeAccount(depositInfo: nil)

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let result = try #require(loaded)
        #expect(result.depositInfo == nil, "Account without deposit must have nil depositInfo")
    }

    // MARK: - Test D: LoanInfo JSON serialization

    @Test("Test D: LoanInfo survives JSON encode → CoreData → decode round-trip")
    func testLoanInfoRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let loanInfo = LoanInfo(
            bankName: "Halyk",
            loanType: .annuity,
            originalPrincipal: 3_000_000,
            interestRateAnnual: 18,
            termMonths: 36,
            startDate: "2026-01-01",
            paymentDay: 10,
            paymentsMade: 2
        )
        let account = makeAccount(loanInfo: loanInfo)

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let result = try #require(loaded)
        let info = try #require(result.loanInfo, "loanInfo must survive round-trip")
        #expect(info.bankName == "Halyk")
        #expect(info.originalPrincipal == 3_000_000)
        #expect(info.interestRateAnnual == 18)
        #expect(info.termMonths == 36)
        #expect(info.paymentsMade == 2)
        #expect(info.loanType == .annuity)
    }

    // MARK: - Test E: IconSource JSON serialization

    @Test("Test E: IconSource .sfSymbol survives round-trip")
    func testIconSourceSfSymbolRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let account = makeAccount(iconSource: .sfSymbol("creditcard"))

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let result = try #require(loaded)
        guard case .sfSymbol(let name) = result.iconSource else {
            Issue.record("Expected .sfSymbol iconSource, got \(String(describing: result.iconSource))")
            return
        }
        #expect(name == "creditcard")
    }

    // MARK: - Test F: Multiple accounts in store

    @Test("Test F: Multiple accounts maintain unique IDs")
    func testMultipleAccountsUniqueIds() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let accounts = (1...5).map { i in
            makeAccount(id: "acc-\(i)", name: "Account \(i)")
        }

        ctx.performAndWait {
            for a in accounts { _ = AccountEntity.from(a, context: ctx) }
            try? ctx.save()
            ctx.reset()
        }

        var fetchedIds: Set<String> = []
        ctx.performAndWait {
            let all = (try? ctx.fetch(AccountEntity.fetchRequest())) ?? []
            fetchedIds = Set(all.compactMap(\.id))
        }

        #expect(fetchedIds.count == 5, "5 accounts must be stored with unique IDs")
        for i in 1...5 {
            #expect(fetchedIds.contains("acc-\(i)"))
        }
    }

    // MARK: - Test G: DepositInfo rate history preserved

    @Test("Test G: DepositInfo.interestRateHistory array survives round-trip")
    func testDepositInfoRateHistoryRoundTrip() throws {
        let container = try makeContainer()
        let ctx = container.viewContext
        let history = [
            RateChange(effectiveFrom: "2026-01-01", annualRate: 10),
            RateChange(effectiveFrom: "2026-03-01", annualRate: 12),
        ]
        var depositInfo = makeDepositInfo()
        depositInfo.interestRateHistory = history
        let account = makeAccount(depositInfo: depositInfo)

        ctx.performAndWait {
            _ = AccountEntity.from(account, context: ctx)
            try? ctx.save()
            ctx.reset()
        }

        var loaded: Account?
        ctx.performAndWait {
            let req = AccountEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", account.id)
            loaded = (try? ctx.fetch(req))?.first?.toAccount()
        }

        let info = try #require(loaded?.depositInfo)
        #expect(info.interestRateHistory.count == 2)
        #expect(info.interestRateHistory[0].annualRate == 10)
        #expect(info.interestRateHistory[1].annualRate == 12)
    }
}
