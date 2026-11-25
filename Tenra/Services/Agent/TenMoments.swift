//
//  TenMoments.swift
//  Tenra
//
//  Ten's moments (docs/plan-ten-gamification.md §6, stage 1): when something good happens, Ten
//  comes out over the whole app (DesignKit's MomentOverlay in MomentPresenter's own window): a
//  goal reached, a debt settled, a loan paid off, an asset sold for more than it cost, a month
//  inside the budgets, the first payment that recorded itself. Only good news; warnings stay
//  cards and Home's messages.
//
//  Rules (§6.3): one moment at a time; a moment of the person's own action shows after the
//  action finished (a short pause, the sheet gone); the others (a month inside the budgets, the
//  first capture) at most two a day, not before onboarding is done; each event's key once. The
//  switch "Ten's moments" in Settings › Assistant turns them off; "Ten chats" off drops Ten's
//  line. Where Ten is not on the device (AssistantAvailability), the screens keep their confetti.
//

import Foundation
import SwiftUI

/// Something good that happened, for Ten to celebrate.
enum TenMomentEvent: Equatable, Sendable {
    case goalReached(name: String)
    case debtSettled(name: String)
    case loanPaidOff(name: String)
    case assetSold(name: String)
    /// Every monthly budget kept last month (TenMomentRules.budgetMonthKept).
    case budgetMonth
    /// A payment recorded itself for the first time (Wallet or a bank notification).
    case firstCapture

    /// Celebrates what the person just did (always shown) rather than something noticed.
    var isOwnAction: Bool {
        switch self {
        case .goalReached, .debtSettled, .loanPaidOff, .assetSold: true
        case .budgetMonth, .firstCapture: false
        }
    }
}

/// A moment as it shows: Ten's face and gesture, his line, the title and the text.
struct TenMoment: Equatable {
    let key: String
    let event: TenMomentEvent
    let title: String
    let message: String
    let line: String
    let mood: ParticleCreature.Mood
    let gesture: CreatureGesture
    let celebrates: Bool

    /// The catalog (§6.4) in words.
    static func make(_ event: TenMomentEvent, key: String) -> TenMoment {
        switch event {
        case .goalReached(let name):
            TenMoment(key: key, event: event,
                      title: String(localized: "moment.goal.title"),
                      message: String(format: String(localized: "moment.goal.text"), name),
                      line: String(localized: "moment.goal.line"),
                      mood: .celebrating, gesture: .hop, celebrates: true)
        case .debtSettled(let name):
            TenMoment(key: key, event: event,
                      title: String(localized: "moment.debt.title"),
                      message: String(format: String(localized: "moment.debt.text"), name),
                      line: String(localized: "moment.debt.line"),
                      mood: .celebrating, gesture: .hop, celebrates: true)
        case .loanPaidOff(let name):
            TenMoment(key: key, event: event,
                      title: String(localized: "moment.loan.title"),
                      message: String(format: String(localized: "moment.loan.text"), name),
                      line: String(localized: "moment.loan.line"),
                      mood: .celebrating, gesture: .hop, celebrates: true)
        case .assetSold(let name):
            TenMoment(key: key, event: event,
                      title: String(localized: "moment.asset.title"),
                      message: String(format: String(localized: "moment.asset.text"), name),
                      line: String(localized: "moment.asset.line"),
                      mood: .proud, gesture: .nod, celebrates: false)
        case .budgetMonth:
            TenMoment(key: key, event: event,
                      title: String(localized: "moment.budget.title"),
                      message: String(localized: "moment.budget.text"),
                      line: String(localized: "moment.budget.line"),
                      mood: .proud, gesture: .hop, celebrates: true)
        case .firstCapture:
            TenMoment(key: key, event: event,
                      title: String(localized: "moment.capture.title"),
                      message: String(localized: "moment.capture.text"),
                      line: String(localized: "moment.capture.line"),
                      mood: .happy, gesture: .perk, celebrates: false)
        }
    }
}

/// The rules, apart from the app, for the tests.
nonisolated enum TenMomentRules {
    /// Moments a day the person did not call up themselves.
    static let unsolicitedPerDay = 2
    /// After the action: the sheet closes, the save lands.
    static let pause: Duration = .milliseconds(600)
    /// After the app comes to the front, before a noticed moment: Home settles first.
    static let settle: Duration = .milliseconds(1500)
    /// The first days of a month, when last month's budgets are celebrated.
    static let budgetMonthDays = 7
    /// Expenses last month for it to count as a month of use.
    static let budgetMonthExpenses = 10
    /// How recent the first capture is for its moment (an older one was before the moments).
    static let firstCaptureDays = 7

    /// Whether a moment may show now.
    static func mayShow(ownAction: Bool, unsolicitedToday: Int) -> Bool {
        ownAction || unsolicitedToday < unsolicitedPerDay
    }

    /// The key of last month's budgets on `now`, nil past the first days of the month.
    static func budgetMonthKey(now: Date, calendar: Calendar = .current) -> String? {
        let day = calendar.component(.day, from: now)
        guard day <= budgetMonthDays,
              let lastMonth = calendar.date(byAdding: .month, value: -1, to: now) else { return nil }
        let parts = calendar.dateComponents([.year, .month], from: lastMonth)
        return String(format: "budgetMonth:%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Whether every monthly budget that ran through last month (reset on the 1st, set before
    /// it began) kept within its limit, in a month with `budgetMonthExpenses` expenses or more:
    /// the same spending rule as the budgets' own (CategoryBudgetService.spent).
    static func budgetMonthKept(
        categories: [CustomCategory],
        transactions: [Transaction],
        baseCurrency: String?,
        now: Date,
        calendar: Calendar = .current,
        rates: RateSnapshot? = nil
    ) -> Bool {
        guard let thisMonth = calendar.dateInterval(of: .month, for: now),
              let lastStart = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) else { return false }
        let lastEnd = thisMonth.start.addingTimeInterval(-1)
        let budgets = categories.filter {
            $0.type == .expense && ($0.budgetAmount ?? 0) > 0 && $0.budgetPeriod == .monthly
                && $0.budgetResetDay == 1 && ($0.budgetStartDate.map { $0 <= lastStart } ?? true)
        }
        guard !budgets.isEmpty else { return false }
        let from = FastDateParser.string(from: lastStart)
        let to = FastDateParser.string(from: lastEnd)
        var expenses = 0
        for tx in transactions where tx.type == .expense && tx.date >= from && tx.date <= to {
            expenses += 1
            if expenses >= budgetMonthExpenses { break }
        }
        guard expenses >= budgetMonthExpenses else { return false }
        return budgets.allSatisfy { category in
            CategoryBudgetService.spent(
                for: category, transactions: transactions, baseCurrency: baseCurrency,
                from: lastStart, through: lastEnd, rates: rates
            ) <= (category.budgetAmount ?? 0)
        }
    }

    /// Whether the first capture is recent enough to celebrate.
    static func firstCaptureIsNew(_ firstCaptureAt: Date?, now: Date) -> Bool {
        guard let firstCaptureAt else { return false }
        return now.timeIntervalSince(firstCaptureAt) <= Double(firstCaptureDays) * 86_400
    }
}

/// Shows Ten's moments over the app.
@MainActor
final class TenMoments {
    static let shared = TenMoments()

    /// Settings › Assistant › "Ten's moments".
    static let enabledKey = "assistant.moments"

    private let defaults: UserDefaults
    /// Ten is on this device (AssistantAvailability); the tests pass their own.
    private let available: () -> Bool
    /// Puts a moment over the app; false when it could not (another one is up, no window).
    private let present: (TenMoment, @escaping () -> Void) -> Bool
    /// Every key shown, with when: an event is celebrated once.
    private var shown: [String: Date]
    /// Moments waiting for the one up to close, or for the app to come to the front.
    private(set) var queue: [TenMoment] = []
    private var isWaiting = false
    /// Tries without a window in a row: past `maxTries` the queue waits for the next
    /// `checkNoticed` (the app back in front).
    private var tries = 0
    private static let maxTries = 3
    /// What Ten wears (TenWardrobeStore), read when a moment shows.
    var accessory: () -> CreatureAccessory? = { nil }

    private static let storageKey = "tenMoments.shown.v1"

    init(
        defaults: UserDefaults = .standard,
        available: @escaping () -> Bool = { AssistantAvailability.isAvailable },
        present: ((TenMoment, @escaping () -> Void) -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.available = available
        self.present = present ?? { moment, closed in TenMoments.presentOverApp(moment, defaults: defaults, closed: closed) }
        shown = (defaults.dictionary(forKey: Self.storageKey) as? [String: Date]) ?? [:]
    }

    /// Ten is on this device and the person has not turned the moments off.
    var isOn: Bool {
        available() && (defaults.object(forKey: Self.enabledKey) as? Bool ?? true)
    }

    func hasShown(_ key: String) -> Bool { shown[key] != nil }

    /// Moments today the person did not call up.
    func unsolicitedToday(now: Date = Date(), calendar: Calendar = .current) -> Int {
        shown.filter { !$0.key.hasPrefix("own:") && calendar.isDate($0.value, inSameDayAs: now) }.count
    }

    /// Celebrates `event` once per `key`. True when Ten will show it: the caller then plays no
    /// confetti of its own. False when the moments are off, the key was shown, or today's
    /// noticed moments are used up.
    @discardableResult
    func celebrate(_ event: TenMomentEvent, key: String, now: Date = Date()) -> Bool {
        let stored = (event.isOwnAction ? "own:" : "") + key
        guard isOn, shown[stored] == nil,
              TenMomentRules.mayShow(ownAction: event.isOwnAction, unsolicitedToday: unsolicitedToday(now: now)) else { return false }
        shown[stored] = now
        defaults.set(shown, forKey: Self.storageKey)
        queue.append(TenMoment.make(event, key: stored))
        UsageEvents.shared.count(.moment(event))
        showNext(after: event.isOwnAction ? TenMomentRules.pause : TenMomentRules.settle)
        return true
    }

    /// What Ten notices on his own when the app comes to the front: last month inside the
    /// budgets (its spending summed off the main actor) and the first capture. Last month
    /// inside the budgets is also a message on Home ("Ten writes", AssistantInbox), with the
    /// moments switched off too.
    func checkNoticed(coordinator: AppCoordinator, inbox: AssistantInbox = .shared, now: Date = Date()) {
        guard available(), !coordinator.needsOnboarding, coordinator.isFullyInitialized else { return }
        let momentsOn = isOn
        if momentsOn {
            // A moment that found no window (the app went to the background) shows now.
            tries = 0
            showNext(after: TenMomentRules.settle)
            if TenMomentRules.firstCaptureIsNew(WalletCaptureStore.shared.firstCaptureAt, now: now) {
                celebrate(.firstCapture, key: "firstCapture", now: now)
            }
        }
        guard let key = TenMomentRules.budgetMonthKey(now: now) else { return }
        let wantsMoment = momentsOn && !hasShown(key)
        let wantsNotice = !inbox.hasPosted(key)
        guard wantsMoment || wantsNotice else { return }
        let categories = coordinator.transactionStore.categories
        let transactions = coordinator.transactionStore.transactions
        let base = coordinator.transactionsViewModel.appSettings.baseCurrency
        let rates = RateSnapshot()
        Task {
            let kept = await Task.detached(priority: .utility) {
                TenMomentRules.budgetMonthKept(categories: categories, transactions: transactions, baseCurrency: base, now: now, rates: rates)
            }.value
            guard kept else { return }
            if wantsNotice { inbox.post([AssistantNotices.budgetMonth(key: key, now: now)], now: now) }
            if wantsMoment { celebrate(.budgetMonth, key: key, now: now) }
        }
    }

    private func showNext(after delay: Duration) {
        guard !isWaiting, !queue.isEmpty, tries < Self.maxTries else { return }
        isWaiting = true
        Task {
            try? await Task.sleep(for: delay)
            isWaiting = false
            guard let moment = queue.first else { return }
            let shownNow = present(moment) { [weak self] in
                self?.showNext(after: TenMomentRules.pause)
            }
            if shownNow {
                tries = 0
                queue.removeFirst()
            } else {
                // Another moment is up, or no window: a few more tries, then the next return
                // to the app (checkNoticed).
                tries += 1
                showNext(after: TenMomentRules.settle)
            }
        }
    }

    /// The moment in DesignKit's window over the app: over sheets, the tab bar and navigation.
    private static func presentOverApp(_ moment: TenMoment, defaults: UserDefaults, closed: @escaping () -> Void) -> Bool {
        let chats = defaults.object(forKey: AssistantChatter.enabledKey) as? Bool ?? true
        let accessory = TenMoments.shared.accessory()
        return MomentPresenter.shared.present(onDismissed: closed) {
            MomentOverlay(
                title: moment.title,
                message: moment.message,
                celebrates: moment.celebrates,
                dismissTitle: String(localized: "moment.dismiss")
            ) {
                TenMomentHero(moment: moment, accessory: accessory, chats: chats)
            }
        }
    }
}

/// Ten in a moment: his face for it, a gesture once he is in, his line while "Ten chats" is on.
struct TenMomentHero: View {
    let moment: TenMoment
    let accessory: CreatureAccessory?
    let chats: Bool

    @State private var gestures = 0

    var body: some View {
        ParticleCreature(
            mood: moment.mood,
            speech: chats ? CreatureSpeech(moment.line, emotion: .joy) : nil,
            accessory: accessory
        )
        .creatureGesture(moment.gesture, trigger: gestures)
        .frame(width: TenMomentMetrics.hero, height: TenMomentMetrics.hero)
        // One element with the moment's title after it (MomentOverlay): Ten's line first.
        .accessibilityLabel(moment.line)
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            gestures += 1
        }
    }
}

enum TenMomentMetrics {
    /// Ten's size in a moment, as on the assistant's home.
    static let hero: CGFloat = 220
}
