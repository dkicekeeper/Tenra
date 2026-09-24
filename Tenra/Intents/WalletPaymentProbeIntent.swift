//
//  WalletPaymentProbeIntent.swift
//  Tenra
//
//  DEBUG-only action for the Wallet automation spike
//  (plans/004-spike-wallet-automation.md). Wire it to Shortcuts → Automation →
//  Wallet ("Transaction" before iOS 26) with Run Immediately, and map the
//  automation's Merchant / Amount / Card / Name fields to its parameters.
//
//  It only RECORDS what arrives (WalletPaymentProbeLog, shown in Settings →
//  Experiments). It never creates, edits or deletes a transaction: the
//  maintainer keeps logging manually while the spike runs on real payments.
//

#if DEBUG
import AppIntents
import OSLog
import UIKit

struct WalletPaymentProbeIntent: AppIntent {

    private static let log = Logger(subsystem: "Tenra", category: "WalletPaymentProbe")

    static var title: LocalizedStringResource = "Tenra Wallet Probe (debug)"
    static var description = IntentDescription("Records Wallet automation payloads for the Apple Pay logging spike. Saves nothing.")

    static var supportedModes: IntentModes { .background }

    // All optional, so each Wallet field can be wired in independently.
    @Parameter(title: "Merchant")
    var merchant: String?

    /// The automation's Amount passed as text, to see its raw representation.
    @Parameter(title: "Amount (text)")
    var rawAmount: String?

    /// The same Amount passed as a currency amount, to see whether the code survives.
    @Parameter(title: "Amount (currency)")
    var currencyAmount: IntentCurrencyAmount?

    @Parameter(title: "Card")
    var card: String?

    @Parameter(title: "Name")
    var name: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let ranInBackground = UIApplication.shared.applicationState != .active
        let services = await IntentEnvironment.shared.services()
        let history = services.store.transactions

        var suggested: String?
        if let merchant, !merchant.isEmpty {
            let parser = services.makeParser()
            let probeId = "wallet-probe"
            let probe = Transaction(
                id: probeId,
                date: DateFormatters.dateFormatter.string(from: Date()),
                description: merchant,
                amount: 0,
                currency: currencyAmount?.currencyCode ?? services.store.baseCurrency,
                type: .expense,
                category: ""
            )
            suggested = await CategorySuggestionProvider.suggestions(
                for: [probe],
                history: history,
                categories: services.categories.customCategories,
                keywordMatcher: { parser.keywordCategory(in: $0) }
            )[probeId]
        }

        let entry = WalletPaymentProbeEntry(
            receivedAt: Date(),
            merchant: merchant,
            rawAmount: rawAmount,
            currencyAmountValue: currencyAmount.map { NSDecimalNumber(decimal: $0.amount).doubleValue },
            currencyAmountCode: currencyAmount?.currencyCode,
            card: card,
            name: name,
            ranInBackground: ranInBackground,
            suggestedCategory: suggested,
            historyCount: history.count
        )
        WalletPaymentProbeLog.shared.append(entry)

        Self.log.info("""
            probe recorded: background=\(ranInBackground, privacy: .public) \
            hasMerchant=\(merchant != nil, privacy: .public) \
            hasCurrencyAmount=\(currencyAmount != nil, privacy: .public) \
            code=\(currencyAmount?.currencyCode ?? "-", privacy: .public) \
            suggested=\(suggested != nil, privacy: .public) \
            history=\(history.count, privacy: .public)
            """)

        return .result()
    }
}
#endif
