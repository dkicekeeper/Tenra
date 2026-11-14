//
//  FinanceToolkit+Actions.swift
//  Tenra
//
//  What a person asks Ten to do that is not a record (docs/plan-ten-agent.md, things asked
//  directly): a one-off reminder at a day and time (`draft_reminder`, a local notification),
//  the evening spending reminder on, off or at another time (`draft_spending_reminder`, the
//  switch of Settings), and an account's new name or whether it counts in the total
//  (`draft_account_change`). Each is a draft: nothing happens before Save, and Undo takes it
//  back.
//

import Foundation
import UserNotifications

/// A one-off reminder Ten sets: a notification with the person's words at a day and time.
struct AgentReminder: Equatable {
    let id: String
    let text: String
    let date: Date

    var identifier: String { "\(AgentReminderCenter.identifierPrefix)\(id)" }
}

/// What a spending reminder draft replaced.
struct AgentSpendingReminderState: Equatable {
    let on: Bool
    let minutes: Int
}

enum AgentReminderCenter {
    static let identifierPrefix = "tenReminder_"

    enum Failure: Error { case notAllowed }

    /// Asks for notifications when they were never asked, then schedules it.
    @MainActor
    static func schedule(_ reminder: AgentReminder, calendar: Calendar = .current) async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined || status == .provisional {
            _ = await NotificationPermissionManager.shared.requestAuthorization()
        }
        let allowed = await center.notificationSettings().authorizationStatus
        guard allowed == .authorized || allowed == .provisional || allowed == .ephemeral else { throw Failure.notAllowed }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "spendingReminder.notification.title")
        content.body = reminder.text
        content.sound = .default
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.date)
        let request = UNNotificationRequest(
            identifier: reminder.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try await center.add(request)
    }

    static func cancel(_ reminder: AgentReminder) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminder.identifier])
    }
}

extension FinanceToolkit {
    private struct ReminderInput: Decodable {
        let text: String
        let date: String
        let time: String?
    }

    private struct SpendingReminderInput: Decodable {
        let on: Bool
        let time: String?
    }

    private struct AccountChangeInput: Decodable {
        let account: String
        let name: String?
        let inTotal: Bool?

        enum CodingKeys: String, CodingKey {
            case account, name
            case inTotal = "in_total"
        }
    }

    /// "HH:MM" as minutes after midnight.
    private static func minutes(_ raw: String) throws -> Int {
        let parts = raw.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0...23).contains(parts[0]), (0...59).contains(parts[1]) else {
            throw FinanceToolError(message: "time must be HH:MM, 00:00 to 23:59.")
        }
        return parts[0] * 60 + parts[1]
    }

    /// `draft_reminder`: the person's words as a notification at a day and time.
    func draftReminder(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_reminder")) }
        let args = try input.decoded(as: ReminderInput.self)
        let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 200 else { throw FinanceToolError(message: "text must be 1 to 200 characters.") }
        guard let day = FastDateParser.date(from: args.date) else { throw FinanceToolError(message: "date must be YYYY-MM-DD.") }
        let minutes = try args.time.map(Self.minutes) ?? 10 * 60
        guard let date = calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: day)) else {
            throw FinanceToolError(message: "date must be YYYY-MM-DD.")
        }
        guard date > now() else { throw FinanceToolError(message: "The reminder must be later than now.") }
        guard let limit = calendar.date(byAdding: .year, value: 1, to: now()), date <= limit else {
            throw FinanceToolError(message: "A reminder can be at most a year ahead. For a payment that repeats, offer draft_recurring: subscriptions remind before each charge.")
        }
        let reminder = AgentReminder(id: UUID().uuidString, text: text, date: date)
        let id = drafts.add([.reminder(reminder)])
        let hour = String(format: "%02d:%02d", minutes / 60, minutes % 60)
        return .success(["draft_id": .string(id), "text": .string(text), "date": .string(args.date), "time": .string(hour), "set": false])
    }

    /// `draft_spending_reminder`: the evening reminder on or off, and its time.
    func draftSpendingReminder(_ input: JSONValue, defaults: UserDefaults = .standard) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_spending_reminder")) }
        let args = try input.decoded(as: SpendingReminderInput.self)
        let current = AgentSpendingReminderState(on: SpendingReminder.isEnabled(defaults: defaults), minutes: SpendingReminder.minutes(defaults: defaults))
        let minutes = try args.time.map(Self.minutes) ?? current.minutes
        let wanted = AgentSpendingReminderState(on: args.on, minutes: minutes)
        guard wanted != current else { throw FinanceToolError(message: "The spending reminder is already set that way.") }
        let id = drafts.add([.spendingReminder(wanted)])
        return .success([
            "draft_id": .string(id),
            "on": .bool(wanted.on),
            "time": .string(String(format: "%02d:%02d", minutes / 60, minutes % 60)),
            "was_on": .bool(current.on),
            "saved": false,
        ])
    }

    /// `draft_account_change`: an account's new name, or whether it counts in the total balance.
    func draftAccountChange(_ input: JSONValue) throws -> AgentToolOutput {
        guard let drafts else { return .failure(Self.notYet("draft_account_change")) }
        let args = try input.decoded(as: AccountChangeInput.self)
        let reference = args.account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = store.accounts.first(where: { $0.id == reference })
            ?? store.accounts.first(where: { $0.name.lowercased() == reference.lowercased() }) else {
            throw FinanceToolError(message: "Unknown account \(reference). Use an account id from <app_context>.")
        }
        var after = account
        if let name = args.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            guard name.count <= 40 else { throw FinanceToolError(message: "name must be 40 characters or fewer.") }
            after.name = name
        }
        if let inTotal = args.inTotal { after.includeInBalance = inTotal }
        guard after != account else { throw FinanceToolError(message: "Nothing changes: give a new name or in_total.") }
        let id = drafts.add([.accountChange(before: account, after: after)])
        return .success([
            "draft_id": .string(id),
            "account_id": .string(account.id),
            "name": .string(after.name),
            "in_total": .bool(after.includeInBalance),
            "saved": false,
        ])
    }

    /// What these drafts will do (FinanceToolkit.describe).
    func describeAction(_ operation: AgentDraftOperation) -> JSONValue {
        switch operation {
        case .reminder(let reminder):
            return ["type": "reminder", "text": .string(reminder.text), "at": .string(ISO8601DateFormatter().string(from: reminder.date))]
        case .spendingReminder(let state):
            return ["type": "spending_reminder", "on": .bool(state.on), "minutes": .number(Double(state.minutes))]
        case .accountChange(let before, let after):
            return ["type": "account_change", "account_id": .string(before.id), "name": .string(after.name), "in_total": .bool(after.includeInBalance)]
        default:
            return .null
        }
    }
}
