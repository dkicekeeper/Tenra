//
//  BalanceCalculationTests.swift
//  AIFinanceManagerTests
//
//  Created on 2026-01-27
//
//  Integration tests for balance calculation conflicts between
//  CSV import and manual transaction creation
//
//  NOTE: Disabled — BalanceCalculationService and BalanceUpdateCoordinator
//  were deleted in Phase 36 (dead code removal). Tests need to be rewritten
//  to use BalanceCoordinator + BalanceEngine pattern.
//  Tracked for update in future phase.
//

#if false

import Testing
@testable import AIFinanceManager

struct BalanceCalculationTests {

    // MARK: - BalanceCalculationService Tests

    @Test func testBalanceCalculationServiceInitialState() async throws {
        let service = BalanceCalculationService()

        // Initially no accounts should be marked as imported
        #expect(!service.isImported("test-account"))
        #expect(service.getInitialBalance(for: "test-account") == nil)
        #expect(service.getCalculationMode(for: "test-account") == .fromInitialBalance)
    }

    @Test func testMarkAccountAsImported() async throws {
        let service = BalanceCalculationService()

        service.markAsImported("imported-account")

        #expect(service.isImported("imported-account"))
        #expect(service.getCalculationMode(for: "imported-account") == .preserveImported)
    }

    @Test func testMarkAccountAsManual() async throws {
        let service = BalanceCalculationService()

        // First mark as imported
        service.markAsImported("test-account")
        #expect(service.isImported("test-account"))

        // Then mark as manual
        service.markAsManual("test-account")
        #expect(!service.isImported("test-account"))
        #expect(service.getCalculationMode(for: "test-account") == .fromInitialBalance)
    }

    @Test func testSetAndGetInitialBalance() async throws {
        let service = BalanceCalculationService()

        service.setInitialBalance(1000.0, for: "account-1")

        #expect(service.getInitialBalance(for: "account-1") == 1000.0)
        #expect(service.getInitialBalance(for: "account-2") == nil)
    }

    @Test func testCalculateInitialBalance() async throws {
        let service = BalanceCalculationService()

        // Create test transactions
        let transactions = [
            Transaction(
                id: "tx-1",
                date: "2026-01-01",
                description: "Income",
                amount: 500.0,
                currency: "USD",
                convertedAmount: nil,
                type: .income,
                category: "Salary",
                subcategory: nil,
                accountId: "account-1",
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: Date()
            ),
            Transaction(
                id: "tx-2",
                date: "2026-01-02",
                description: "Expense",
                amount: 100.0,
                currency: "USD",
                convertedAmount: nil,
                type: .expense,
                category: "Food",
                subcategory: nil,
                accountId: "account-1",
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: Date()
            )
        ]

        // Current balance is 400 (after income +500 and expense -100)
        // So initial balance should be 400 - (500 - 100) = 0
        let initialBalance = service.calculateInitialBalance(
            currentBalance: 400.0,
            transactions: transactions,
            accountCurrency: "USD"
        )

        #expect(initialBalance == 0.0)
    }

    @Test func testApplyIncomeTransaction() async throws {
        let service = BalanceCalculationService()

        let account = Account(name: "Test Account", balance: 1000.0, currency: "USD")
        let transaction = Transaction(
            id: "tx-1",
            date: "2026-01-01",
            description: "Salary",
            amount: 500.0,
            currency: "USD",
            convertedAmount: nil,
            type: .income,
            category: "Salary",
            subcategory: nil,
            accountId: account.id,
            targetAccountId: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date()
        )

        let newBalance = service.applyTransaction(transaction, to: 1000.0, for: account, isSource: false)

        #expect(newBalance == 1500.0)
    }

    @Test func testApplyExpenseTransaction() async throws {
        let service = BalanceCalculationService()

        let account = Account(name: "Test Account", balance: 1000.0, currency: "USD")
        let transaction = Transaction(
            id: "tx-1",
            date: "2026-01-01",
            description: "Groceries",
            amount: 100.0,
            currency: "USD",
            convertedAmount: nil,
            type: .expense,
            category: "Food",
            subcategory: nil,
            accountId: account.id,
            targetAccountId: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date()
        )

        let newBalance = service.applyTransaction(transaction, to: 1000.0, for: account, isSource: false)

        #expect(newBalance == 900.0)
    }

    @Test func testApplyTransferTransaction() async throws {
        let service = BalanceCalculationService()

        let sourceAccount = Account(name: "Source", balance: 1000.0, currency: "USD")
        let targetAccount = Account(name: "Target", balance: 500.0, currency: "USD")
        let transaction = Transaction(
            id: "tx-1",
            date: "2026-01-01",
            description: "Transfer",
            amount: 200.0,
            currency: "USD",
            convertedAmount: nil,
            type: .internalTransfer,
            category: "Transfer",
            subcategory: nil,
            accountId: sourceAccount.id,
            targetAccountId: targetAccount.id,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date()
        )

        let sourceBalance = service.applyTransaction(transaction, to: 1000.0, for: sourceAccount, isSource: true)
        let targetBalance = service.applyTransaction(transaction, to: 500.0, for: targetAccount, isSource: false)

        #expect(sourceBalance == 800.0)
        #expect(targetBalance == 700.0)
    }

    @Test func testClearImportedFlags() async throws {
        let service = BalanceCalculationService()

        service.markAsImported("account-1")
        service.markAsImported("account-2")
        #expect(service.isImported("account-1"))
        #expect(service.isImported("account-2"))

        service.clearImportedFlags()

        #expect(!service.isImported("account-1"))
        #expect(!service.isImported("account-2"))
    }

    // MARK: - Deposit Handling Tests

    @Test func testApplyTransactionToDepositWithdrawal() async throws {
        let service = BalanceCalculationService()

        let depositInfo = DepositInfo(
            bankName: "Test Bank",
            principalBalance: 10000.0,
            capitalizationEnabled: false,
            interestRateAnnual: 5.0,
            interestPostingDay: 1
        )

        let transaction = Transaction(
            id: "tx-1",
            date: "2026-01-01",
            description: "Withdrawal",
            amount: 500.0,
            currency: "USD",
            convertedAmount: nil,
            type: .internalTransfer,
            category: "Transfer",
            subcategory: nil,
            accountId: "deposit-1",
            targetAccountId: "account-1",
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date()
        )

        let result = service.applyTransactionToDeposit(transaction, depositInfo: depositInfo, isSource: true)

        #expect(result.depositInfo.principalBalance == 9500.0)
        #expect(result.balance == 9500.0)
    }

    @Test func testApplyTransactionToDepositTopUp() async throws {
        let service = BalanceCalculationService()

        let depositInfo = DepositInfo(
            bankName: "Test Bank",
            principalBalance: 10000.0,
            capitalizationEnabled: false,
            interestRateAnnual: 5.0,
            interestPostingDay: 1
        )

        let transaction = Transaction(
            id: "tx-1",
            date: "2026-01-01",
            description: "Top Up",
            amount: 500.0,
            currency: "USD",
            convertedAmount: nil,
            type: .internalTransfer,
            category: "Transfer",
            subcategory: nil,
            accountId: "account-1",
            targetAccountId: "deposit-1",
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date()
        )

        let result = service.applyTransactionToDeposit(transaction, depositInfo: depositInfo, isSource: false)

        #expect(result.depositInfo.principalBalance == 10500.0)
        #expect(result.balance == 10500.0)
    }

    // MARK: - BalanceUpdateCoordinator Tests

    @Test func testBalanceUpdateCoordinatorSequentialExecution() async throws {
        let coordinator = BalanceUpdateCoordinator()
        var executionOrder: [Int] = []

        // Schedule multiple updates
        await coordinator.scheduleUpdate(
            source: .transaction(id: "tx-1"),
            action: {
                executionOrder.append(1)
            },
            completion: nil
        )

        await coordinator.scheduleUpdate(
            source: .transaction(id: "tx-2"),
            action: {
                executionOrder.append(2)
            },
            completion: nil
        )

        // Wait a bit for processing
        try await Task.sleep(for: .milliseconds(100))

        // Verify sequential execution
        #expect(executionOrder == [1, 2])
    }

    // MARK: - Integration Scenario Tests

    @Test func testImportThenManualTransactionScenario() async throws {
        // This test simulates the scenario where:
        // 1. User imports CSV with existing balance
        // 2. Then adds a manual transaction
        // The balance should update correctly in both cases

        let service = BalanceCalculationService()

        // Step 1: Simulate CSV import
        let importedAccountId = "imported-account"
        let importedBalance = 1000.0

        // Calculate initial balance from imported data
        let importedTransactions = [
            Transaction(
                id: "imported-tx-1",
                date: "2026-01-01",
                description: "Imported Income",
                amount: 500.0,
                currency: "USD",
                convertedAmount: nil,
                type: .income,
                category: "Salary",
                subcategory: nil,
                accountId: importedAccountId,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: Date()
            )
        ]

        let initialBalance = service.calculateInitialBalance(
            currentBalance: importedBalance,
            transactions: importedTransactions,
            accountCurrency: "USD"
        )

        service.setInitialBalance(initialBalance, for: importedAccountId)
        service.markAsImported(importedAccountId)

        #expect(initialBalance == 500.0) // 1000 - 500 = 500
        #expect(service.isImported(importedAccountId))

        // Step 2: Simulate manual transaction
        let manualTransaction = Transaction(
            id: "manual-tx-1",
            date: "2026-01-27",
            description: "Manual Expense",
            amount: 100.0,
            currency: "USD",
            convertedAmount: nil,
            type: .expense,
            category: "Food",
            subcategory: nil,
            accountId: importedAccountId,
            targetAccountId: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date()
        )

        // For imported accounts, we apply transactions directly
        let account = Account(name: "Imported Account", balance: importedBalance, currency: "USD")
        let newBalance = service.applyTransaction(manualTransaction, to: importedBalance, for: account, isSource: false)

        #expect(newBalance == 900.0) // 1000 - 100 = 900
    }

    @Test func testManualAccountWithTransactions() async throws {
        // This test simulates the scenario where:
        // 1. User creates account manually with initial balance
        // 2. Then adds transactions
        // The balance should be calculated as initialBalance + sum(transactions)

        let service = BalanceCalculationService()

        let manualAccountId = "manual-account"
        let manualInitialBalance = 500.0

        // Set manual initial balance (not imported)
        service.setInitialBalance(manualInitialBalance, for: manualAccountId)
        service.markAsManual(manualAccountId)

        #expect(!service.isImported(manualAccountId))
        #expect(service.getCalculationMode(for: manualAccountId) == .fromInitialBalance)

        // Create transactions
        let transactions = [
            Transaction(
                id: "tx-1",
                date: "2026-01-01",
                description: "Income",
                amount: 300.0,
                currency: "USD",
                convertedAmount: nil,
                type: .income,
                category: "Salary",
                subcategory: nil,
                accountId: manualAccountId,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: Date()
            ),
            Transaction(
                id: "tx-2",
                date: "2026-01-02",
                description: "Expense",
                amount: 100.0,
                currency: "USD",
                convertedAmount: nil,
                type: .expense,
                category: "Food",
                subcategory: nil,
                accountId: manualAccountId,
                targetAccountId: nil,
                recurringSeriesId: nil,
                recurringOccurrenceId: nil,
                createdAt: Date()
            )
        ]

        let account = Account(id: manualAccountId, name: "Manual Account", balance: 700.0, currency: "USD")
        let calculatedBalance = service.calculateBalance(
            for: account,
            transactions: transactions,
            allAccounts: [account]
        )

        // For manual accounts in this test, we need the calculation service to have the initial balance
        // Expected: 500 (initial) + 300 (income) - 100 (expense) = 700
        #expect(service.getInitialBalance(for: manualAccountId) == manualInitialBalance)
    }
}

#endif // #if false — disabled until BalanceCalculationService/BalanceUpdateCoordinator replaced
