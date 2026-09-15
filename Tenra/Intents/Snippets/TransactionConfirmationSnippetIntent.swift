//
//  TransactionConfirmationSnippetIntent.swift
//  Tenra
//
//  Hosts `TransactionConfirmationSnippet` for `requestConfirmation`.
//
//  iOS 26 deprecated `requestConfirmation(result:confirmationActionName:showPrompt:)`,
//  the call that used to carry a one-shot `.result(dialog:view:)` snapshot. Its
//  replacement takes a `SnippetIntent` the system can re-run whenever it needs to
//  redraw the card, so the snippet's inputs travel as `@Parameter`s instead of a
//  captured `TransactionDraft`.
//
//  `perform()` only renders — no writes, no side effects — because the system may
//  run it repeatedly for a single confirmation.
//

import AppIntents
import SwiftUI

struct TransactionConfirmationSnippetIntent: SnippetIntent {

    /// Never user-visible: `isDiscoverable = false` keeps this intent out of the
    /// Shortcuts app, and a confirmation card shows the dialog, not this title.
    /// That is why it carries an inline default instead of a `Localizable.strings`
    /// key in all 11 locales.
    static let title: LocalizedStringResource = LocalizedStringResource(
        "intent.snippet.confirmationTitle",
        defaultValue: "Transaction confirmation"
    )

    /// Support intent for a confirmation card, not a user-facing action.
    static var isDiscoverable: Bool { false }

    @Parameter var amount: Double
    @Parameter var currency: String
    @Parameter var categoryName: String
    @Parameter var accountName: String
    @Parameter var categoryWasGuessed: Bool
    @Parameter var accountWasGuessed: Bool

    init() {}

    init(draft: TransactionDraft, accountName: String) {
        self.amount = draft.amount
        self.currency = draft.currency
        self.categoryName = draft.categoryName
        self.accountName = accountName
        self.categoryWasGuessed = draft.warnings.contains { warning in
            if case .categorySubstituted = warning { return true }
            return false
        }
        self.accountWasGuessed = draft.warnings.contains(.accountInferred)
    }

    /// `@MainActor` because it constructs a SwiftUI view, and views are MainActor-isolated
    /// under the project's default isolation. Matches the other intents in `Intents/`.
    @MainActor
    func perform() async throws -> some IntentResult & ShowsSnippetView {
        .result(
            view: TransactionConfirmationSnippet(
                amount: amount,
                currency: currency,
                categoryName: categoryName,
                accountName: accountName,
                categoryWasGuessed: categoryWasGuessed,
                accountWasGuessed: accountWasGuessed
            )
        )
    }
}
