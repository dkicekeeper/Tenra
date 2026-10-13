//
//  AssistantAllowance.swift
//  Tenra
//
//  The assistant's free allowance for people without Pro (PremiumConfig.Assistant): a trial of
//  30 answers in the 7 days after the first question, then 10 a calendar month. Pro has no
//  allowance. The rule is pure; `AssistantUsageStore` keeps the count in the Keychain, so a
//  reinstall does not reset it.
//
//  Not wired yet: free users reach the cloud brain only once the server checks App Attest
//  (docs/plan-ai-assistant.md §5, phase 1).
//

import Foundation
import Security

/// What was spent so far.
nonisolated struct AssistantUsage: Codable, Equatable, Sendable {
    /// The first question; the trial runs `trialDays` from here.
    var firstUse: Date?
    var trialUsed: Int = 0
    /// The month the monthly count belongs to, `yyyy-MM`.
    var month: String?
    var monthUsed: Int = 0
}

nonisolated enum AssistantAllowance {
    struct Status: Equatable, Sendable {
        let remaining: Int
        let limit: Int
        let isTrial: Bool
        /// When the allowance changes: the trial's end, or the next month. Nil before the first
        /// question (the trial has not started).
        let renewsAt: Date?

        var isExhausted: Bool { remaining == 0 }
    }

    static func status(_ usage: AssistantUsage, now: Date, calendar: Calendar = .current) -> Status {
        let trialLimit = PremiumConfig.Assistant.trialActions
        guard let firstUse = usage.firstUse else {
            return Status(remaining: trialLimit, limit: trialLimit, isTrial: true, renewsAt: nil)
        }
        if let trialEnd = trialEnd(firstUse, calendar: calendar), now < trialEnd {
            return Status(remaining: max(0, trialLimit - usage.trialUsed), limit: trialLimit, isTrial: true, renewsAt: trialEnd)
        }
        let monthlyLimit = PremiumConfig.Assistant.monthlyActions
        let used = usage.month == monthKey(now, calendar: calendar) ? usage.monthUsed : 0
        let nextMonth = calendar.dateInterval(of: .month, for: now)?.end
        return Status(remaining: max(0, monthlyLimit - used), limit: monthlyLimit, isTrial: false, renewsAt: nextMonth)
    }

    /// The usage after one more answer. Call only when `status(...).remaining > 0`.
    static func recording(_ usage: AssistantUsage, now: Date, calendar: Calendar = .current) -> AssistantUsage {
        var next = usage
        let firstUse = usage.firstUse ?? now
        next.firstUse = firstUse
        if let trialEnd = trialEnd(firstUse, calendar: calendar), now < trialEnd {
            next.trialUsed += 1
        } else {
            let key = monthKey(now, calendar: calendar)
            if next.month != key {
                next.month = key
                next.monthUsed = 0
            }
            next.monthUsed += 1
        }
        return next
    }

    private static func trialEnd(_ firstUse: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: PremiumConfig.Assistant.trialDays, to: firstUse)
    }

    static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }
}

/// Keeps `AssistantUsage` in the Keychain (this device only; it outlives a reinstall).
nonisolated struct AssistantUsageStore: Sendable {
    let service: String

    init(service: String = "tenra.assistant.usage") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "v1",
        ]
    }

    func load() -> AssistantUsage {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let usage = try? JSONDecoder().decode(AssistantUsage.self, from: data) else { return AssistantUsage() }
        return usage
    }

    func save(_ usage: AssistantUsage) {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}
