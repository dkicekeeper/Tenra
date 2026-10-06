//
//  IntentEnvironmentTests.swift
//  TenraTests
//

import Testing
@testable import Tenra

// `.sharedProcessState`: the bootstrap test runs AppCoordinator's fast path, which reads
// the shared CoreData store and settings.
@MainActor
@Suite(.sharedProcessState)
struct IntentEnvironmentTests {

    @Test("A registered coordinator is reused rather than replaced")
    func reusesRegisteredCoordinator() async {
        let environment = IntentEnvironment()
        let coordinator = AppCoordinator()
        environment.register(coordinator)

        let services = await environment.services()

        #expect(services.store === coordinator.transactionStore)
    }

    @Test("Registering twice keeps the first coordinator")
    func registrationIsIdempotent() async {
        let environment = IntentEnvironment()
        let first = AppCoordinator()
        let second = AppCoordinator()
        environment.register(first)
        environment.register(second)

        let services = await environment.services()

        #expect(services.store === first.transactionStore)
        #expect(services.store !== second.transactionStore)
    }

    @Test("Without a coordinator there is nothing for the app to adopt")
    func noExistingCoordinator() async {
        let environment = IntentEnvironment()
        #expect(await environment.existingCoordinator() == nil)
    }

    @Test("The app adopts the coordinator an intent built before the UI existed")
    func appAdoptsTheIntentCoordinator() async {
        let environment = IntentEnvironment()
        // An intent ran first (cold background launch) and bootstrapped a coordinator.
        let intentStore = await environment.services().store

        let adopted = await environment.existingCoordinator()

        #expect(adopted?.transactionStore === intentStore)
    }
}
