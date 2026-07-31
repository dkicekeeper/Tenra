//
//  IntentHandoff.swift
//  Tenra
//
//  Carries a ParsedOperation from an intent that could not complete headlessly
//  into the running UI, where the existing voice confirmation screen finishes
//  the job. Set by the intent immediately before it returns .openAppWhenRun;
//  consumed and cleared by MainTabView.
//

import Foundation
import Observation

@MainActor
@Observable
final class IntentHandoff {

    static let shared = IntentHandoff()

    var pendingOperation: ParsedOperation?

    private init() {}

    func request(_ operation: ParsedOperation) {
        pendingOperation = operation
        IntentUsageCounters.shared.record(.intentFallbackToApp)
    }
}
