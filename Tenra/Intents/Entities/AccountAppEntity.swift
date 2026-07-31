//
//  AccountAppEntity.swift
//  Tenra
//
//  Lets the Shortcuts app show a picker of real accounts instead of asking the
//  user to type an identifier.
//

import AppIntents

struct AccountAppEntity: AppEntity {

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "intent.entity.account"
    )

    static var defaultQuery = AccountEntityQuery()

    var id: String
    var name: String
    var currency: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(currency)")
    }
}

struct AccountEntityQuery: EntityQuery {

    @MainActor
    func entities(for identifiers: [String]) async throws -> [AccountAppEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [AccountAppEntity] {
        let services = await IntentEnvironment.shared.services()
        // Loan and deposit accounts are technical and must never be offered as
        // the source of a plain expense, matching TransactionDraftService.
        return services.accounts.accounts
            .filter { !$0.isLoan && !$0.isDeposit }
            .map { AccountAppEntity(id: $0.id, name: $0.name, currency: $0.currency) }
    }
}
