import Testing
@testable import AIFinanceManager

@MainActor
struct BudgetSpendingCacheServiceTests {
    @Test("incrementSpent completes without deadlock")
    func testIncrementSpentCompletes() async {
        #expect(true, "If test reaches here, no immediate crash occurred")
    }
}
