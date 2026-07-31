//
//  IntentEnvironmentTests.swift
//  TenraTests
//

import Testing
@testable import Tenra

@MainActor
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
}
