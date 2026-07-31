//
//  CheckSpendingIntent.swift
//  Tenra
//
//  Read-only. Answers "how much did I spend today" without opening the app.
//  Goes through SpendingQueryService, which reads CoreData directly rather than
//  TransactionStore: an intent process has no transactions loaded.
//

import AppIntents
import CoreData
import SwiftUI

enum SpendingPeriodAppEnum: String, AppEnum {

    case today
    case thisWeek
    case thisMonth

    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "intent.checkSpending.period"
    )

    static var caseDisplayRepresentations: [SpendingPeriodAppEnum: DisplayRepresentation] = [
        .today: "intent.checkSpending.period.today",
        .thisWeek: "intent.checkSpending.period.week",
        .thisMonth: "intent.checkSpending.period.month"
    ]

    var domain: SpendingPeriod {
        switch self {
        case .today: .today
        case .thisWeek: .thisWeek
        case .thisMonth: .thisMonth
        }
    }
}

struct CheckSpendingIntent: AppIntent {

    static var title: LocalizedStringResource = "intent.checkSpending.title"
    static var description = IntentDescription("intent.checkSpending.description")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "intent.checkSpending.period", default: .today)
    var period: SpendingPeriodAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {

        let services = await IntentEnvironment.shared.services()
        let baseCurrency = services.settings.settings.baseCurrency

        let total = try SpendingQueryService.total(
            period: period.domain,
            baseCurrency: baseCurrency,
            context: CoreDataStack.shared.persistentContainer.viewContext
        )

        let amountText = Formatting.formatCurrencySmart(
            total.amount,
            currency: total.currency
        )
        let text = String(
            format: String(localized: "intent.checkSpending.answer"),
            amountText
        )

        return .result(dialog: IntentDialog(stringLiteral: text)) {
            SpendingSummarySnippet(total: total, period: period)
        }
    }
}
