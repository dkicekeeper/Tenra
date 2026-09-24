//
//  IntentAuthenticationPolicyTests.swift
//  TenraTests
//
//  Reading spending totals requires an unlocked iPhone; logging a transaction
//  from the lock screen stays allowed (worst case a junk entry the user can
//  delete, and the Apple Pay automation may run while locked).
//

import Testing
import AppIntents
@testable import Tenra

struct IntentAuthenticationPolicyTests {

    private func isRequiresAuthentication(_ policy: IntentAuthenticationPolicy) -> Bool {
        if case .requiresAuthentication = policy { return true }
        return false
    }

    private func isAlwaysAllowed(_ policy: IntentAuthenticationPolicy) -> Bool {
        if case .alwaysAllowed = policy { return true }
        return false
    }

    @Test func spendingQueryRequiresUnlock() {
        #expect(isRequiresAuthentication(CheckSpendingIntent.authenticationPolicy))
    }

    @Test func loggingIntentsStayAllowedWhileLocked() {
        #expect(isAlwaysAllowed(LogTransactionIntent.authenticationPolicy))
        #expect(isAlwaysAllowed(AddExpenseIntent.authenticationPolicy))
    }
}
