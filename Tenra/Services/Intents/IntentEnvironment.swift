//
//  IntentEnvironment.swift
//  Tenra
//
//  Single entry point for obtaining live services from an App Intent, whatever
//  the process state.
//
//  When the app is already running (foreground or suspended), the system runs
//  the intent in that same process and we must reuse its AppCoordinator: a
//  second coordinator would mean a second TransactionStore, and the two would
//  diverge in memory. TenraApp registers its coordinator the moment it builds
//  one.
//
//  When the process was launched solely to run an intent, SwiftUI's App body
//  never runs, so nothing registers a coordinator. We build one and await only
//  initializeFastPath(): accounts + settings + persisted balances, documented
//  at under 50 ms, with no transaction load. That is sufficient because
//  TransactionStore.add updates balances incrementally against the persisted
//  account.balance rather than recomputing from the transactions array.
//

import Foundation

@MainActor
final class IntentEnvironment {

    static let shared = IntentEnvironment()

    private var coordinator: AppCoordinator?
    private var bootstrap: Task<AppCoordinator, Never>?

    init() {}

    /// Called by TenraApp immediately after it constructs its coordinator.
    func register(_ coordinator: AppCoordinator) {
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
    }

    func services() async -> IntentServices {
        IntentServices(coordinator: await resolveCoordinator())
    }

    private func resolveCoordinator() async -> AppCoordinator {
        if let coordinator { return coordinator }
        if let bootstrap { return await bootstrap.value }

        let task = Task { @MainActor () -> AppCoordinator in
            let created = AppCoordinator()
            await created.initializeFastPath()
            return created
        }
        bootstrap = task
        let created = await task.value
        if coordinator == nil { coordinator = created }
        return created
    }
}

@MainActor
struct IntentServices {
    let coordinator: AppCoordinator

    var store: TransactionStore { coordinator.transactionStore }
    var accounts: AccountsViewModel { coordinator.accountsViewModel }
    var categories: CategoriesViewModel { coordinator.categoriesViewModel }
    var settings: SettingsViewModel { coordinator.settingsViewModel }
    var transactions: TransactionsViewModel { coordinator.transactionsViewModel }

    /// Parser wired exactly as the Voice tab wires it (TabViews.swift:87-91).
    /// It holds weak references, so the coordinator must outlive it — which it
    /// does, being retained by IntentEnvironment.
    func makeParser() -> VoiceInputParser {
        VoiceInputParser(
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    }
}
