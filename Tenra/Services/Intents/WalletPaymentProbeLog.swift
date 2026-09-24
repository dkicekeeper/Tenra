//
//  WalletPaymentProbeLog.swift
//  Tenra
//
//  DEBUG-only scaffolding for the Wallet automation spike
//  (plans/004-spike-wallet-automation.md). Records what the Shortcuts
//  "Wallet" automation actually passes to an app action, so the design of real
//  automatic Apple Pay logging can be decided from evidence. Local only, never
//  compiled into Release, deleted once the spike has a recommendation.
//

#if DEBUG
import Foundation

struct WalletPaymentProbeEntry: Codable, Identifiable {
    var id = UUID()
    var receivedAt: Date
    var merchant: String?
    var rawAmount: String?
    var currencyAmountValue: Double?
    var currencyAmountCode: String?
    var card: String?
    var name: String?
    var ranInBackground: Bool
    var suggestedCategory: String?
    /// Transactions loaded when the probe ran. A cold background launch only
    /// runs the fast path, so 0 here means the history tier had nothing to use.
    var historyCount: Int
}

@MainActor
final class WalletPaymentProbeLog {

    static let shared = WalletPaymentProbeLog()

    private static let storageKey = "debug.walletProbe.entries"
    private static let capacity = 50

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Newest first.
    func entries() -> [WalletPaymentProbeEntry] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([WalletPaymentProbeEntry].self, from: data) else {
            return []
        }
        return decoded
    }

    func append(_ entry: WalletPaymentProbeEntry) {
        let updated = Array(([entry] + entries()).prefix(Self.capacity))
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
#endif
