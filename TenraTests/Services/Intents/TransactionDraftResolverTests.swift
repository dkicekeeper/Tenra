//
//  TransactionDraftResolverTests.swift
//  TenraTests
//
//  Pins the resolution rules that shipped inside
//  VoiceInputConfirmationView.saveTransaction (lines 416-530) before that logic
//  was extracted into TransactionDraftService.
//
//  Do NOT edit these tests during the extraction: a test that must change to
//  keep passing is a behavior change, not a refactor.
//
//  @MainActor is mandatory here — the suite constructs MainActor-isolated types
//  and mutates the process-global CurrencyRateStore.shared, so its synchronous
//  tests must serialize on the main actor against other rate-mutating suites.
//

import Testing
import Foundation
@testable import Tenra

@MainActor
struct TransactionDraftResolverTests {

    // MARK: - Fixtures

    private func account(
        _ id: String,
        currency: String = "KZT",
        deposit: DepositInfo? = nil,
        loan: LoanInfo? = nil
    ) -> Account {
        Account(
            id: id,
            name: id,
            currency: currency,
            depositInfo: deposit,
            loanInfo: loan,
            balance: 0
        )
    }

    /// Matches the convenience initializer used by
    /// TenraTests/Services/Voice/VoiceInputParserTests.swift:44
    private func category(_ name: String, type: TransactionType = .expense) -> CustomCategory {
        CustomCategory(
            name: name,
            iconSource: .sfSymbol("circle"),
            colorHex: "#f97316",
            type: type
        )
    }

    private func depositInfo() -> DepositInfo {
        DepositInfo(
            bankName: "T",
            initialPrincipal: 1_000_000,
            capitalizationEnabled: false,
            interestRateAnnual: 0,
            interestRateHistory: [RateChange(effectiveFrom: "2026-01-01", annualRate: 0)],
            interestPostingDay: 1,
            lastInterestCalculationDate: "2026-01-01",
            lastInterestPostingMonth: "2026-01-01",
            interestAccruedForCurrentPeriod: 0,
            startDate: "2026-01-01"
        )
    }

    private func loanInfo() -> LoanInfo {
        LoanInfo(
            bankName: "B",
            loanType: .annuity,
            originalPrincipal: 1_000_000,
            remainingPrincipal: 800_000,
            interestRateAnnual: 12,
            termMonths: 12,
            startDate: "2026-01-01",
            paymentDay: 1
        )
    }

    /// Learning store backed by an ephemeral suite so production defaults stay clean.
    private func emptyLearningStore(_ suite: String) -> VoiceLearningStore {
        UserDefaults().removePersistentDomain(forName: suite)
        return VoiceLearningStore(defaults: UserDefaults(suiteName: suite)!)
    }

    private var otherName: String { String(localized: "category.other") }

    // MARK: - Amount (pins lines 431-434)

    @Test("No amount parsed is a blocking issue")
    func missingAmount() {
        let op = ParsedOperation(type: .expense, amount: nil, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.1")
        )
        #expect(result == .failure(.missingAmount))
    }

    @Test("Zero or negative amount is a blocking issue")
    func nonPositiveAmount() {
        let op = ParsedOperation(type: .expense, amount: 0, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.2")
        )
        #expect(result == .failure(.missingAmount))
    }

    // MARK: - Account (pins lines 436-445)

    @Test("Named account is used verbatim and produces no warning")
    func namedAccount() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a2", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1"), account("a2")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.3")
        )
        let draft = try result.get()
        #expect(draft.accountId == "a2")
        #expect(draft.warnings.isEmpty)
    }

    @Test("Loan and deposit accounts are never eligible")
    func loanAndDepositExcluded() {
        let deposit = account("d1", deposit: depositInfo())
        let loan = account("l1", loan: loanInfo())
        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [deposit, loan],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.4")
        )
        #expect(result == .failure(.noEligibleAccount))
    }

    @Test("No accounts at all is a blocking issue")
    func noAccounts() {
        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.5")
        )
        #expect(result == .failure(.noEligibleAccount))
    }

    @Test("Learned account wins over first-regular when no account is named")
    func learnedAccountPreferred() throws {
        let learned = emptyLearningStore("draft.tests.6")
        // VoiceLearningStore.confidenceThreshold is 2, so record twice.
        learned.recordSave(category: "Food", accountId: "a2")
        learned.recordSave(category: "Food", accountId: "a2")

        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1"), account("a2")],
            categories: [category("Food")],
            learned: learned
        )
        let draft = try result.get()
        #expect(draft.accountId == "a2")
        #expect(draft.warnings.contains(.accountInferred))
    }

    @Test("Falls back to the first eligible account and warns")
    func firstEligibleAccountFallback() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1"), account("a2")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.7")
        )
        let draft = try result.get()
        #expect(draft.accountId == "a1")
        #expect(draft.warnings.contains(.accountInferred))
    }

    // MARK: - Category (pins lines 447-464)

    @Test("Unknown category is substituted with Other and warns")
    func unknownCategorySubstituted() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a1", categoryName: "Nonexistent")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food"), category(otherName)],
            learned: emptyLearningStore("draft.tests.8")
        )
        let draft = try result.get()
        #expect(draft.categoryName == otherName)
        #expect(draft.warnings.contains(.categorySubstituted(original: "Nonexistent")))
    }

    @Test("Category of the wrong transaction type does not match")
    func categoryTypeMustMatch() throws {
        // "Salary" exists only as income; an expense operation must not use it.
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a1", categoryName: "Salary")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Salary", type: .income), category(otherName)],
            learned: emptyLearningStore("draft.tests.9")
        )
        let draft = try result.get()
        #expect(draft.categoryName == otherName)
    }

    @Test("Unknown category with no Other fallback is a blocking issue")
    func noFallbackCategory() {
        let op = ParsedOperation(type: .expense, amount: 3000, accountId: "a1", categoryName: "Nonexistent")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.10")
        )
        #expect(result == .failure(.noFallbackCategory))
    }

    // MARK: - Currency (pins lines 466-491)

    @Test("Matching currency needs no conversion")
    func sameCurrencyNoConversion() throws {
        let op = ParsedOperation(type: .expense, amount: 3000, currencyCode: "KZT", accountId: "a1", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1", currency: "KZT")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.11")
        )
        let draft = try result.get()
        #expect(draft.convertedAmount == nil)
        #expect(draft.currency == "KZT")
    }

    @Test("Mismatched currency with a cold cache is a blocking issue")
    func coldCacheBlocks() {
        CurrencyRateStore.shared.clearAll()
        let op = ParsedOperation(type: .expense, amount: 10, currencyCode: "USD", accountId: "a1", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1", currency: "KZT")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.12"),
            conversion: .cachedOnly
        )
        #expect(result == .failure(.needsFXConversion(amount: 10, from: "USD", to: "KZT")))
    }

    @Test("A caller-provided conversion is used verbatim")
    func providedConversionUsed() throws {
        let op = ParsedOperation(type: .expense, amount: 10, currencyCode: "USD", accountId: "a1", categoryName: "Food")
        let result = TransactionDraftService.makeDraft(
            from: op,
            accounts: [account("a1", currency: "KZT")],
            categories: [category("Food")],
            learned: emptyLearningStore("draft.tests.13"),
            conversion: .provided(5400)
        )
        let draft = try result.get()
        #expect(draft.convertedAmount == 5400)
    }
}
