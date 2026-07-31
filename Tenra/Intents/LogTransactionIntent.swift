//
//  LogTransactionIntent.swift
//  Tenra
//
//  One spoken phrase, one transaction. Declared in the main app target, so it
//  runs in the app's own process: no extension, no App Group.
//
//  The phrase is embedded in the App Shortcut phrase itself (see TenraShortcuts),
//  which is what makes this one-shot rather than a multi-turn Siri
//  interrogation. A three-turn dialogue would be slower than opening the app and
//  would defeat the point.
//
//  `import SwiftUI` is required, not decorative: the `.result(dialog:view:)`
//  factories live in the _AppIntents_SwiftUI cross-import overlay, which only
//  activates when both modules are imported.
//

import AppIntents
import CoreData
import OSLog
import SwiftUI

struct LogTransactionIntent: AppIntent {

    /// Diagnostic trail for the Siri path, which cannot be stepped through in a
    /// debugger. Capture with: Console.app, filter subsystem "Tenra",
    /// category "LogTransactionIntent".
    private static let log = Logger(subsystem: "Tenra", category: "LogTransactionIntent")

    static var title: LocalizedStringResource = "intent.log.title"
    static var description = IntentDescription("intent.log.description")

    /// Stays false. Blocking issues bring the app forward at runtime through
    /// continueInForeground(), because this static is read before perform() runs
    /// and cannot express a per-invocation decision.
    static var openAppWhenRun: Bool = false

    /// Free text, parsed by VoiceInputParser. It cannot be interpolated into an
    /// App Shortcut phrase (only AppEntity/AppEnum parameters can be), so Siri
    /// asks for it with requestValueDialog as a second turn. In the Shortcuts
    /// app it is filled in directly.
    @Parameter(
        title: "intent.log.parameter.phrase",
        requestValueDialog: "intent.log.parameter.phrase.prompt"
    )
    var phrase: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {

        Self.log.info("perform() entered, phrase=\(phrase, privacy: .public)")

        let services = await IntentEnvironment.shared.services()
        let parser = services.makeParser()

        Self.log.info("""
            context: accounts=\(services.accounts.accounts.count, privacy: .public) \
            categories=\(services.categories.customCategories.count, privacy: .public)
            """)

        let operations = parser.parseMulti(phrase)
        guard let first = operations.first else {
            Self.log.error("parseMulti returned no operations")
            return .result(dialog: "intent.log.notUnderstood")
        }

        Self.log.info("""
            parsed: amount=\(String(describing: first.amount), privacy: .public) \
            category=\(first.categoryName ?? "nil", privacy: .public) \
            currency=\(first.currencyCode ?? "nil", privacy: .public) \
            accountId=\(first.accountId ?? "nil", privacy: .public)
            """)

        let result = TransactionDraftService.makeDraft(
            from: first,
            accounts: services.accounts.accounts,
            categories: services.categories.customCategories,
            learned: .shared,
            conversion: .cachedOnly,
            note: phrase,
            suggestAccount: { category in
                IntentAccountSuggester.suggestedAccountId(
                    forCategory: category,
                    accounts: services.accounts.accounts,
                    amount: first.amount.map { NSDecimalNumber(decimal: $0).doubleValue },
                    context: CoreDataStack.shared.persistentContainer.viewContext
                )
            }
        )

        switch result {
        case .failure(let issue):
            Self.log.error("""
                makeDraft BLOCKED: \(String(describing: issue), privacy: .public) \
                | eligibleAccounts=\(services.accounts.accounts.filter { !$0.isLoan && !$0.isDeposit }.count, privacy: .public) \
                | firstAccountCurrency=\(services.accounts.accounts.first?.currency ?? "nil", privacy: .public) \
                | expenseCategories=\(services.categories.customCategories.filter { $0.type == .expense }.map(\.name).joined(separator: ","), privacy: .public) \
                | otherKey=\(String(localized: "category.other"), privacy: .public)
                """)
            // Amount missing, no eligible account, no Other category, or a cold
            // FX cache. Hand it to the UI with the fields prefilled. No network
            // call is attempted here on purpose.
            IntentHandoff.shared.request(first)
            do {
                try await continueInForeground(
                    IntentDialog(stringLiteral: String(localized: "intent.log.openingApp"))
                )
                Self.log.info("continueInForeground returned normally")
            } catch {
                Self.log.error("continueInForeground threw: \(String(describing: error), privacy: .public)")
                throw error
            }
            return .result(dialog: "intent.log.openingApp")

        case .success(let draft):
            let accountName = services.accounts.accounts
                .first { $0.id == draft.accountId }?.name ?? ""

            Self.log.info("""
                resolved: category=\(draft.categoryName, privacy: .public) \
                account=\(accountName, privacy: .public) \
                inferred=\(draft.warnings.contains(.accountInferred), privacy: .public) \
                learned=\(VoiceLearningStore.shared.preferredAccountID(forCategory: draft.categoryName) ?? "none", privacy: .public) \
                ranked=\(IntentAccountSuggester.suggestedAccountId(forCategory: draft.categoryName, accounts: services.accounts.accounts, amount: draft.amount, context: CoreDataStack.shared.persistentContainer.viewContext) ?? "none", privacy: .public)
                """)

            try await requestConfirmation(
                result: .result(dialog: "intent.log.confirm") {
                    TransactionConfirmationSnippet(draft: draft, accountName: accountName)
                }
            )

            _ = try await TransactionDraftService.commit(
                draft,
                store: services.store,
                categoriesViewModel: services.categories
            )
            IntentUsageCounters.shared.record(.intentAdd)

            let amountText = Formatting.formatCurrencySmart(
                draft.amount,
                currency: draft.currency
            )

            // Multi-operation phrases are a Pro feature. Nothing is dropped
            // silently: say exactly what was saved and what was not.
            if operations.count > 1, !PremiumManager.shared.isPro {
                let text = String(
                    format: String(localized: "intent.log.savedWithProHint"),
                    amountText,
                    draft.categoryName,
                    operations.count - 1
                )
                return .result(dialog: IntentDialog(stringLiteral: text))
            }

            let text = String(
                format: String(localized: "intent.log.saved"),
                amountText,
                draft.categoryName
            )
            return .result(dialog: IntentDialog(stringLiteral: text))
        }
    }
}

extension LogTransactionIntent {

    /// Tells the system this action just happened for real, so it can offer it
    /// as a suggestion next time. Failures are ignored on purpose: a donation
    /// is a hint, never a requirement for a save that already succeeded.
    @MainActor
    static func donate(phrase: String) async {
        let intent = LogTransactionIntent()
        intent.phrase = phrase
        _ = try? await intent.donate()
    }
}
