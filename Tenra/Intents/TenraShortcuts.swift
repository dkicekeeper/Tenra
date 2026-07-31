//
//  TenraShortcuts.swift
//  Tenra
//
//  Surfaces the intents in Siri, Spotlight and the Shortcuts app.
//
//  Every phrase MUST contain \(.applicationName) — the system rejects phrases
//  without it. The phrases themselves are localized in AppShortcuts.strings,
//  which is a separate file from Localizable.strings by system requirement.
//
//  IMPORTANT — why the spoken phrase does not carry the transaction text:
//  App Shortcut phrases may only interpolate AppEntity or AppEnum parameters.
//  A String parameter is rejected at build time by appintentsmetadataprocessor
//  ("Invalid parameter type. AppEntity and AppEnum are the only allowed types").
//  So "Log 3000 for coffee in Tenra" as a single utterance is not expressible.
//  The flow is two turns instead: the user says "Log a transaction in Tenra",
//  Siri asks what it was via the parameter's requestValueDialog, and the user
//  speaks the phrase. The free-text parameter still works as a single step in
//  the Shortcuts app, where typed String parameters are allowed.
//
//  The system caches this provider. Edited phrases do not take effect until the
//  app is reinstalled, which is expected and not a bug.
//

import AppIntents

struct TenraShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogTransactionIntent(),
            phrases: [
                "Log a transaction in \(.applicationName)",
                "Log an expense in \(.applicationName)",
                "Record a transaction in \(.applicationName)"
            ],
            shortTitle: "intent.log.title",
            systemImageName: "mic.fill"
        )

        AppShortcut(
            intent: CheckSpendingIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "Check my spending in \(.applicationName)"
            ],
            shortTitle: "intent.checkSpending.title",
            systemImageName: "chart.pie.fill"
        )

        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)"
            ],
            shortTitle: "intent.addExpense.title",
            systemImageName: "plus.circle.fill"
        )
    }
}
