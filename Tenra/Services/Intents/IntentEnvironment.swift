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
//  A database that fails to open is never built on: the bootstrap checks the store first and
//  the intent fails with a message pointing to the app (which shows what happened), instead of
//  a coordinator whose repositories would read the legacy UserDefaults copy.
//

import Foundation

@MainActor
final class IntentEnvironment {

    static let shared = IntentEnvironment()

    private var coordinator: AppCoordinator?
    /// Resolves to nil when the store could not be opened.
    private var bootstrap: Task<AppCoordinator?, Never>?

    init() {}

    /// Called by TenraApp immediately after it constructs its coordinator.
    func register(_ coordinator: AppCoordinator) {
        guard self.coordinator == nil else { return }
        self.coordinator = coordinator
    }

    /// Throws `IntentStoreUnavailableError` when the database could not be opened, or the app's
    /// full load failed (the app is showing its error screen; nothing may write meanwhile).
    func services() async throws -> IntentServices {
        guard let coordinator = await resolveCoordinator(), coordinator.startupFailure == nil else {
            throw IntentStoreUnavailableError()
        }
        return IntentServices(coordinator: coordinator)
    }

    /// The coordinator this process already has, or nil: one an intent built before the
    /// app's UI existed (the Wallet automation or Siri launched the process in the
    /// background), including one still bootstrapping. TenraApp adopts it instead of
    /// building a second: `register` keeps the first coordinator, so with two of them every
    /// later intent wrote through the fast-path-only store, over the balances and the
    /// whole-table saves of the store the UI uses.
    func existingCoordinator() async -> AppCoordinator? {
        if let coordinator { return coordinator }
        if let bootstrap { return await bootstrap.value }
        return nil
    }

    private func resolveCoordinator() async -> AppCoordinator? {
        if let coordinator { return coordinator }
        if let bootstrap { return await bootstrap.value }

        // The store check runs inside the task, so concurrent callers share one bootstrap
        // (an await before `bootstrap = task` would let two of them build a coordinator each).
        let task = Task { @MainActor () -> AppCoordinator? in
            let failure = await Task.detached(priority: .userInitiated) {
                CoreDataStack.shared.openStoreIfNeeded()
            }.value
            guard failure == nil else { return nil }
            let created = AppCoordinator()
            await created.initializeFastPath()
            return created
        }
        bootstrap = task
        guard let created = await task.value else {
            // Let a later run check again: the store may open once the device is unlocked.
            bootstrap = nil
            return nil
        }
        if coordinator == nil { coordinator = created }
        return created
    }
}

/// An intent ran while the database could not be opened. Siri and Shortcuts show the message.
/// `nonisolated`: with MainActor default isolation the conformance would be main-actor-isolated,
/// and the system reads the message off the main actor.
nonisolated struct IntentStoreUnavailableError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "intent.error.storeUnavailable" }
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
