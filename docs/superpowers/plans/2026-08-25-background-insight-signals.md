# Background Insight Signal Pushes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insight signal pushes fire while the app is closed (BGAppRefreshTask) and are delivered at organic times inside a 09:00–21:00 window instead of back-to-back after an in-app recompute.

**Architecture:** A new headless `BackgroundInsightsRefresher` loads data straight from `CoreDataRepository`, runs the existing nonisolated `InsightsService.computeGranularities([.month, .week])`, and feeds results into `InsightSignalService` / `WeeklyDigestScheduler`. `InsightSignalService` gains a pure windowed `deliveryDates` scheduler (replacing the fixed "+3 min" stagger) and cancels pending signals that are no longer eligible. Spec: `docs/superpowers/specs/2026-08-25-background-insight-signals-design.md`.

**Tech Stack:** Swift/SwiftUI iOS 26, BackgroundTasks (BGAppRefreshTask), UserNotifications, swift-testing.

## Global Constraints

- Build/test destination: `platform=iOS Simulator,name=iPhone 17 Pro`.
- Delivery window: 09:00–21:00 local; morning slot 09:00 + 0–90 min jitter; spacing between same-run pushes: random 2–4 h.
- BG task identifier: `dakacom.Tenra.insightsRefresh`; `earliestBeginDate = +4 h`.
- Existing caps unchanged: 7-day per-id dedup, 5/week, 2/recompute (`perRunCap`).
- Dedup history records at SCHEDULING time; cancelled-stale entries stay in history.
- swift-testing: filter at SUITE level only (`-only-testing:TenraTests/<TypeName>`); parse results with `grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"`.
- No em dashes in any user-facing string (none are added by this plan).
- New Swift files need NO pbxproj edits (file-system-synchronized groups).

---

### Task 1: Windowed delivery scheduler (`deliveryDates`)

**Files:**
- Modify: `Tenra/Services/Notifications/InsightSignalService.swift` (constants block around line 76 and a new nonisolated static section after `notificationBody`)
- Test: `TenraTests/Services/Insights/InsightSignalServiceTests.swift`

**Interfaces:**
- Produces: `nonisolated static func InsightSignalService.deliveryDates(count:now:calendar:rng:) -> [Date]`, constants `deliveryWindowStartHour = 9`, `deliveryWindowEndHour = 21`, `morningJitterMinutes = 90`, `minRunSpacing: TimeInterval = 2*3600`, `maxRunSpacing: TimeInterval = 4*3600`. Task 3 consumes `deliveryDates`.

- [ ] **Step 1: Write the failing tests**

Append to `TenraTests/Services/Insights/InsightSignalServiceTests.swift` inside `struct InsightSignalServiceTests` (a seeded RNG so results are deterministic):

```swift
    // MARK: - Delivery window scheduling

    /// Deterministic RNG for delivery-date tests (SplitMix64).
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test("first delivery is immediate when now is inside the 09:00-21:00 window")
    func deliveryFirstInsideWindow() {
        var rng = SeededRNG(state: 1)
        let now = date(2026, 8, 25, 14, 0)
        let dates = InsightSignalService.deliveryDates(count: 1, now: now, rng: &rng)
        #expect(dates == [now])
    }

    @Test("night-time delivery moves to next morning 09:00-10:30")
    func deliveryNightMovesToMorning() {
        var rng = SeededRNG(state: 2)
        let now = date(2026, 8, 25, 23, 30)
        let dates = InsightSignalService.deliveryDates(count: 1, now: now, rng: &rng)
        let cal = Calendar.current
        #expect(dates.count == 1)
        #expect(cal.component(.day, from: dates[0]) == 26)
        let minutes = cal.component(.hour, from: dates[0]) * 60 + cal.component(.minute, from: dates[0])
        #expect(minutes >= 9 * 60 && minutes <= 10 * 60 + 30)
    }

    @Test("early morning (05:00) uses the SAME day's morning slot")
    func deliveryEarlyMorningSameDay() {
        var rng = SeededRNG(state: 3)
        let now = date(2026, 8, 25, 5, 0)
        let dates = InsightSignalService.deliveryDates(count: 1, now: now, rng: &rng)
        #expect(Calendar.current.component(.day, from: dates[0]) == 25)
        #expect(Calendar.current.component(.hour, from: dates[0]) >= 9)
    }

    @Test("subsequent deliveries are spaced 2-4h and never leave the window")
    func deliverySpacingAndWindow() {
        var rng = SeededRNG(state: 4)
        let now = date(2026, 8, 25, 20, 30) // near window end -> overflow to next morning
        let dates = InsightSignalService.deliveryDates(count: 3, now: now, rng: &rng)
        #expect(dates.count == 3)
        #expect(dates[0] == now)
        let cal = Calendar.current
        for d in dates {
            let hour = cal.component(.hour, from: d)
            #expect(hour >= 9 && hour < 21)
        }
        for i in 1..<dates.count {
            #expect(dates[i] > dates[i - 1])
        }
    }

    @Test("deliveryDates is deterministic under a seeded RNG and empty for count 0")
    func deliveryDeterminismAndZero() {
        let now = date(2026, 8, 25, 22, 0)
        var rng1 = SeededRNG(state: 42)
        var rng2 = SeededRNG(state: 42)
        #expect(InsightSignalService.deliveryDates(count: 2, now: now, rng: &rng1)
             == InsightSignalService.deliveryDates(count: 2, now: now, rng: &rng2))
        var rng3 = SeededRNG(state: 42)
        #expect(InsightSignalService.deliveryDates(count: 0, now: now, rng: &rng3).isEmpty)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightSignalServiceTests 2>&1 | grep -aE "error:|Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)" | tail -20
```

Expected: compile error `type 'InsightSignalService' has no member 'deliveryDates'` (the test target fails to build — that is the failing state for swift-testing).

- [ ] **Step 3: Implement `deliveryDates`**

In `Tenra/Services/Notifications/InsightSignalService.swift`, replace the constant

```swift
    /// Spacing between pushes selected in the same run (the first fires
    /// immediately, the next after this interval).
    nonisolated static let staggerInterval: TimeInterval = 3 * 60
```

with

```swift
    /// Delivery window: signals are only delivered between these local hours.
    /// A signal falling outside is moved to the next morning slot.
    nonisolated static let deliveryWindowStartHour = 9
    nonisolated static let deliveryWindowEndHour = 21
    /// Morning slot = 09:00 + random 0...90 min, so post-night deliveries do not
    /// all land at exactly 09:00 (subscription reminders and digest live there).
    nonisolated static let morningJitterMinutes = 90
    /// Random spacing between pushes selected in the same run.
    nonisolated static let minRunSpacing: TimeInterval = 2 * 3600
    nonisolated static let maxRunSpacing: TimeInterval = 4 * 3600
```

Then add after `notificationBody(for:)`:

```swift
    // MARK: - Delivery window scheduling (pure, unit-tested)

    /// Returns `count` delivery dates: the first is `now` when inside the
    /// 09:00-21:00 window (otherwise the next morning slot), each subsequent one
    /// is 2-4 h after the previous, overflowing past 21:00 into the next morning.
    /// Pure given an injected RNG - tests pass a seeded generator.
    nonisolated static func deliveryDates(
        count: Int,
        now: Date,
        calendar: Calendar = .current,
        rng: inout some RandomNumberGenerator
    ) -> [Date] {
        guard count > 0 else { return [] }
        var dates: [Date] = []
        dates.reserveCapacity(count)
        var cursor = now
        for index in 0..<count {
            var candidate: Date
            if index == 0 {
                candidate = isInsideWindow(now, calendar: calendar)
                    ? now
                    : nextMorningSlot(after: now, calendar: calendar, rng: &rng)
            } else {
                let spacing = TimeInterval.random(in: minRunSpacing...maxRunSpacing, using: &rng)
                candidate = cursor.addingTimeInterval(spacing)
                if !isInsideWindow(candidate, calendar: calendar) {
                    candidate = nextMorningSlot(after: candidate, calendar: calendar, rng: &rng)
                }
            }
            dates.append(candidate)
            cursor = candidate
        }
        return dates
    }

    private nonisolated static func isInsideWindow(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= deliveryWindowStartHour && hour < deliveryWindowEndHour
    }

    /// 09:00 + 0...90 min jitter on the next day whose window start is still ahead
    /// of `date` (05:00 resolves to the SAME day's morning).
    private nonisolated static func nextMorningSlot(
        after date: Date,
        calendar: Calendar,
        rng: inout some RandomNumberGenerator
    ) -> Date {
        var day = calendar.startOfDay(for: date)
        var windowStart = calendar.date(byAdding: .hour, value: deliveryWindowStartHour, to: day) ?? date
        if date >= windowStart {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            windowStart = calendar.date(byAdding: .hour, value: deliveryWindowStartHour, to: day) ?? date
        }
        let jitterSeconds = Int.random(in: 0...(morningJitterMinutes * 60), using: &rng)
        return windowStart.addingTimeInterval(TimeInterval(jitterSeconds))
    }
```

Note: `processInsights` still references `staggerInterval` at this point — replace that reference in the SAME edit to keep the target compiling: in the loop body, change

```swift
            // First signal delivers now; the rest are staggered so a post-absence
            // recompute never lands several banners back-to-back.
            let trigger: UNNotificationTrigger? = index == 0
                ? nil
                : UNTimeIntervalNotificationTrigger(timeInterval: Self.staggerInterval * Double(index), repeats: false)
```

to a temporary equivalent that will be finished in Task 3:

```swift
            // Temporary bridge - Task 3 replaces this with windowed deliveryDates.
            let trigger: UNNotificationTrigger? = index == 0
                ? nil
                : UNTimeIntervalNotificationTrigger(timeInterval: 180 * Double(index), repeats: false)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightSignalServiceTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)" | tail -20
```

Expected: all InsightSignalServiceTests pass, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Notifications/InsightSignalService.swift TenraTests/Services/Insights/InsightSignalServiceTests.swift
git commit -m "feat(signals): pure 09:00-21:00 windowed deliveryDates scheduler"
```

---

### Task 2: Eligible-set derivation for stale-pending cancellation

**Files:**
- Modify: `Tenra/Services/Notifications/InsightSignalService.swift`
- Test: `TenraTests/Services/Insights/InsightSignalServiceTests.swift`

**Interfaces:**
- Consumes: `InsightSignalKind.from(_:)` (existing).
- Produces: `nonisolated static func InsightSignalService.eligibleSignalIds(from:enabledKinds:) -> Set<String>`. Task 3 consumes it.

- [ ] **Step 1: Write the failing test**

Append inside `struct InsightSignalServiceTests`:

```swift
    // MARK: - Eligible set (stale-pending cancellation)

    @Test("eligibleSignalIds keeps critical/warning of enabled kinds, drops the rest")
    func eligibleSet() {
        let insights = [
            makeInsight(id: "budget_over", type: .budgetOverspend, severity: .critical),
            makeInsight(id: "spending_spike", type: .spendingSpike, severity: .warning),
            makeInsight(id: "neutral_one", type: .budgetOverspend, severity: .neutral),   // severity-gated out
            makeInsight(id: "net_cash", type: .netCashFlow, severity: .critical)          // non-signal type
        ]
        let all = InsightSignalService.eligibleSignalIds(from: insights, enabledKinds: allKinds)
        #expect(all == ["budget_over", "spending_spike"])

        let noSpike = InsightSignalService.eligibleSignalIds(
            from: insights, enabledKinds: allKinds.subtracting([.spendingSpike])
        )
        #expect(noSpike == ["budget_over"])

        #expect(InsightSignalService.eligibleSignalIds(from: [], enabledKinds: allKinds).isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightSignalServiceTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)" | tail -5
```

Expected: compile error `has no member 'eligibleSignalIds'`.

- [ ] **Step 3: Implement**

Add right after `deliveryDates`'s private helpers in `InsightSignalService.swift`:

```swift
    // MARK: - Eligible set (stale-pending cancellation)

    /// Ids of insights that would currently qualify as signals (severity gate +
    /// enabled kind), IGNORING dedup history - a signal already scheduled is in
    /// history by design, yet must stay pending as long as it still qualifies.
    /// Pending ids outside this set are cancelled by `processInsights`.
    nonisolated static func eligibleSignalIds(
        from insights: [Insight],
        enabledKinds: Set<InsightSignalKind>
    ) -> Set<String> {
        Set(insights.compactMap { insight in
            guard let kind = InsightSignalKind.from(insight),
                  enabledKinds.contains(kind) else { return nil }
            return insight.id
        })
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Same command as Step 2. Expected: `** TEST SUCCEEDED **`, `eligibleSet()` listed as passed.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Notifications/InsightSignalService.swift TenraTests/Services/Insights/InsightSignalServiceTests.swift
git commit -m "feat(signals): eligibleSignalIds for stale pending cancellation"
```

---

### Task 3: Rewire `processInsights` — windowed triggers + stale cancellation

**Files:**
- Modify: `Tenra/Services/Notifications/InsightSignalService.swift` (`processInsights`, header doc comment)

**Interfaces:**
- Consumes: `deliveryDates` (Task 1), `eligibleSignalIds` (Task 2).
- Produces: `processInsights(_:now:)` unchanged signature — `BackgroundInsightsRefresher` (Task 5) and `InsightsViewModel` (existing call site, no change) both call it.

No new unit test: the method body is UNUserNotificationCenter I/O; its decision logic (`selectSignals`, `deliveryDates`, `eligibleSignalIds`) is already unit-tested. Verification is a green build + existing suite.

- [ ] **Step 1: Rewrite `processInsights`**

Replace the whole `processInsights` method with:

```swift
    /// Diffs freshly computed insights against the alert history, cancels pending
    /// signals that no longer qualify, and schedules new critical/warning signals
    /// at organic times inside the 09:00-21:00 delivery window. Call after every
    /// insight recompute (foreground or BGAppRefresh) - dedup, the weekly cap and
    /// the per-run cap make repeated calls safe.
    func processInsights(_ insights: [Insight], now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        let auth = await center.notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional else {
            Self.logger.debug("🔔 [Signals] notifications not authorized — skipped")
            return
        }

        // Cancel scheduled-but-undelivered signals that no longer qualify
        // (signal left critical/warning, or its kind was toggled off). Their
        // history records stay - a flapping signal must not re-push.
        let enabledKinds = settings.enabledKinds
        let pendingSignalIds = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.notificationIdPrefix) }
        if !pendingSignalIds.isEmpty {
            let eligible = Self.eligibleSignalIds(from: insights, enabledKinds: enabledKinds)
            let stale = pendingSignalIds.filter {
                !eligible.contains(String($0.dropFirst(Self.notificationIdPrefix.count)))
            }
            if !stale.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: stale)
                Self.logger.debug("🔔 [Signals] cancelled \(stale.count) stale pending signal(s)")
            }
        }

        let selected = Self.selectSignals(
            from: insights,
            enabledKinds: enabledKinds,
            history: loadHistory(),
            now: now
        )
        guard !selected.isEmpty else { return }

        var rng = SystemRandomNumberGenerator()
        let fireDates = Self.deliveryDates(count: selected.count, now: now, rng: &rng)

        // Prune expired records while we're writing anyway.
        var history = loadHistory().filter { $0.date > now.addingTimeInterval(-Self.dedupWindow) }
        for (insight, fireDate) in zip(selected, fireDates) {
            let content = UNMutableNotificationContent()
            content.title = insight.title
            content.body = Self.notificationBody(for: insight)
            content.sound = .default
            // Near-immediate dates deliver now; future ones get a calendar trigger
            // so they survive the app being suspended or relaunched.
            let trigger: UNNotificationTrigger?
            if fireDate.timeIntervalSince(now) < 60 {
                trigger = nil
            } else {
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: fireDate
                )
                trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            }
            let request = UNNotificationRequest(
                identifier: Self.notificationIdPrefix + insight.id,
                content: content,
                trigger: trigger
            )
            do {
                try await center.add(request)
                history.append(FiredRecord(id: insight.id, date: now))
                Self.logger.debug("🔔 [Signals] scheduled '\(insight.id, privacy: .public)' for \(fireDate, privacy: .public)")
            } catch {
                Self.logger.warning("🔔 [Signals] failed to schedule '\(insight.id, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
        saveHistory(history)
    }
```

Also update the file-header comment bullet added earlier: replace

```swift
//  - At most 2 pushes per recompute, staggered — a post-absence launch must not
//    dump the whole weekly budget as one burst of banners.
```

with

```swift
//  - At most 2 pushes per recompute, delivered inside a 09:00-21:00 window with
//    randomized spacing (deliveryDates) — no burst of banners, no night pushes.
```

- [ ] **Step 2: Build and run the signal suite**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightSignalServiceTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)" | tail -5
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Notifications/InsightSignalService.swift
git commit -m "feat(signals): windowed delivery + stale pending cancellation in processInsights"
```

---

### Task 4: Prune unused `transactionStore` dependency from `InsightsService`

Makes the service constructible headlessly (Task 5) without a MainActor `TransactionStore`. The property is stored but never read (verified: no usages outside `init` across `Tenra/Services/Insights/*.swift`).

**Files:**
- Modify: `Tenra/Services/Insights/InsightsService.swift:42,69-79`
- Modify: `Tenra/ViewModels/AppCoordinator.swift:201-206`
- Modify: `TenraTests/Services/Insights/InsightSignalGeneratorTests.swift:30-36`

**Interfaces:**
- Produces: `InsightsService.init(filterService:queryService:budgetService:)` — Task 5 consumes this exact signature.

- [ ] **Step 1: Remove the property and init parameter**

In `Tenra/Services/Insights/InsightsService.swift` delete line 42 (`let transactionStore: TransactionStore`) and change the init to:

```swift
    init(
        filterService: TransactionFilterService,
        queryService: TransactionQueryService,
        budgetService: CategoryBudgetService
    ) {
        self.filterService = filterService
        self.queryService = queryService
        self.budgetService = budgetService
    }
```

- [ ] **Step 2: Update the two call sites**

`Tenra/ViewModels/AppCoordinator.swift:201` — remove the `transactionStore:` argument:

```swift
        let insightsService = InsightsService(
            filterService: insightsFilterService,
            queryService: insightsQueryService,
            budgetService: insightsBudgetService
        )
```

`TenraTests/Services/Insights/InsightSignalGeneratorTests.swift:30` — same removal (the store stays retained in the returned tuple; generators read it via `DataSnapshot`, not the service):

```swift
        let service = InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: store)
        )
```

- [ ] **Step 3: Build and run the generator suite**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightSignalGeneratorTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)" | tail -5
```

Expected: `** TEST SUCCEEDED **`. If the compiler reports any other reader of `insightsService.transactionStore`, STOP and re-evaluate (the premise "unused" would be wrong).

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Insights/InsightsService.swift Tenra/ViewModels/AppCoordinator.swift TenraTests/Services/Insights/InsightSignalGeneratorTests.swift
git commit -m "refactor(insights): drop unused transactionStore dependency from InsightsService"
```

---

### Task 5: `BackgroundInsightsRefresher` + registration + Info.plist

**Files:**
- Create: `Tenra/Services/Insights/BackgroundInsightsRefresher.swift`
- Modify: `Tenra/AppDelegate.swift` (register in `didFinishLaunching`)
- Modify: `Tenra/TenraApp.swift` (submit on `scenePhase == .background`, inside the existing `.onChange(of: scenePhase)`)
- Modify: `Tenra/Info.plist`

No unit test: the class is BGTaskScheduler + UNUserNotificationCenter orchestration over already-tested compute; verified by build + on-device LLDB simulation (Step 5).

- [ ] **Step 1: Add Info.plist keys**

```bash
plutil -insert UIBackgroundModes -array Tenra/Info.plist
plutil -insert UIBackgroundModes.0 -string fetch Tenra/Info.plist
plutil -insert BGTaskSchedulerPermittedIdentifiers -array Tenra/Info.plist
plutil -insert BGTaskSchedulerPermittedIdentifiers.0 -string dakacom.Tenra.insightsRefresh Tenra/Info.plist
plutil -p Tenra/Info.plist | grep -A2 -E "UIBackgroundModes|BGTaskScheduler"
```

Expected output shows both keys with their single values.

- [ ] **Step 2: Create the refresher**

`Tenra/Services/Insights/BackgroundInsightsRefresher.swift`:

```swift
//
//  BackgroundInsightsRefresher.swift
//  Tenra
//
//  Closes the BGAppRefresh follow-up from the 2026-07 insights audit: signals and
//  the weekly digest used to (re)compute only when the Analytics tab recomputed
//  insights. This task recomputes them headlessly a few times a day (iOS decides
//  exactly when — BGAppRefreshTask is best-effort), so signal pushes arrive while
//  the app is closed, at organic times via InsightSignalService.deliveryDates.
//
//  Deliberately headless: loads straight from CoreDataRepository — no
//  AppCoordinator, TransactionStore or ViewModels, so no UI side effects and no
//  MainActor startup cost. Known limitation (spec'd): the background pass does NOT
//  generate recurring catch-up or deposit interest — it sees data as of the last
//  foreground session. Acceptable for transition-style alerts.
//
//  Spec: docs/superpowers/specs/2026-08-25-background-insight-signals-design.md
//

import Foundation
import BackgroundTasks
import UserNotifications
import os

@MainActor
final class BackgroundInsightsRefresher {
    static let shared = BackgroundInsightsRefresher()

    /// Must match BGTaskSchedulerPermittedIdentifiers in Info.plist.
    nonisolated static let taskIdentifier = "dakacom.Tenra.insightsRefresh"
    /// iOS treats this as "no earlier than"; actual runs are opportunistic.
    nonisolated static let refreshInterval: TimeInterval = 4 * 3600

    private static let logger = Logger(subsystem: "Tenra", category: "BackgroundInsightsRefresher")

    /// Register the launch handler. MUST be called before
    /// `didFinishLaunchingWithOptions` returns (BGTaskScheduler requirement).
    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                Self.shared.handle(refreshTask)
            }
        }
    }

    /// Submit the next refresh request. Safe to call repeatedly — a new submit
    /// replaces the pending request for the same identifier.
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected on Simulator (unsupported) and when Background App Refresh
            // is disabled in system settings — log, don't crash.
            Self.logger.debug("BG submit skipped: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        // Chain the next run first, so a crash/expiration can't break the chain.
        scheduleNextRefresh()
        let work = Task { [weak self] in
            let success = await self?.refresh() ?? false
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Headless recompute: repository load → InsightsService → signal pushes +
    /// weekly digest. Returns false only when work was cut short (cancellation).
    func refresh() async -> Bool {
        let settings = InsightSignalSettings.shared
        guard settings.isEnabled || settings.weeklyDigestEnabled else { return true }
        let auth = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard auth == .authorized || auth == .provisional else { return true }

        let baseCurrency: String
        if let appSettings = try? await SettingsStorageService().loadSettings() {
            baseCurrency = appSettings.baseCurrency
        } else {
            baseCurrency = AppSettings.makeDefault().baseCurrency
        }

        // Repository fetches are nonisolated — run them off the main thread.
        let repository = CoreDataRepository()
        async let transactionsLoad = Task.detached(priority: .utility) {
            repository.loadTransactions(dateRange: nil)
        }.value
        async let accountsLoad = Task.detached(priority: .utility) {
            repository.loadAccounts()
        }.value
        async let categoriesLoad = Task.detached(priority: .utility) {
            repository.loadCategories()
        }.value
        async let seriesLoad = Task.detached(priority: .utility) {
            repository.loadRecurringSeries()
        }.value
        let transactions = await transactionsLoad
        let accounts = await accountsLoad
        let categories = await categoriesLoad
        let series = await seriesLoad

        guard !transactions.isEmpty, !accounts.isEmpty else { return true }
        guard !Task.isCancelled else { return false }

        // Persisted balances (maintained by BalanceCoordinator.persistBalance while
        // the app runs) stand in for the in-memory balance snapshot.
        let balances = Dictionary(accounts.map { ($0.id, $0.balance) },
                                  uniquingKeysWith: { first, _ in first })
        let snapshot = InsightsService.DataSnapshot(
            transactions: transactions,
            categories: categories,
            recurringSeries: series,
            accounts: accounts,
            balanceFor: { balances[$0] ?? 0 }
        )
        let service = InsightsService(
            filterService: TransactionFilterService(),
            queryService: TransactionQueryService(),
            budgetService: CategoryBudgetService(store: nil)
        )
        let cacheManager = TransactionCacheManager()
        let currencyService = TransactionCurrencyService()

        let result = await Task.detached(priority: .utility) {
            let preAggregated = InsightsService.PreAggregatedData.build(
                from: transactions,
                baseCurrency: baseCurrency,
                recurringSeries: series
            )
            return service.computeGranularities(
                [.month, .week],
                transactions: transactions,
                baseCurrency: baseCurrency,
                cacheManager: cacheManager,
                currencyService: currencyService,
                snapshot: snapshot,
                firstTransactionDate: preAggregated.firstDate,
                preAggregated: preAggregated,
                sharedInsights: nil
            )
        }.value
        guard !Task.isCancelled else { return false }

        if let monthInsights = result.results[.month]?.insights {
            await InsightSignalService.shared.processInsights(monthInsights)
        }
        if let weekPoints = result.results[.week]?.periodPoints {
            await WeeklyDigestScheduler.shared.reschedule(
                weekPoints: weekPoints,
                baseCurrency: baseCurrency
            )
        }
        Self.logger.debug("BG refresh done: \(transactions.count) tx, month insights: \(result.results[.month]?.insights.count ?? 0)")
        return true
    }
}
```

- [ ] **Step 3: Register in AppDelegate and schedule in TenraApp**

`Tenra/AppDelegate.swift` — in `didFinishLaunchingWithOptions`, after `UNUserNotificationCenter.current().delegate = self`:

```swift
        // Background insights refresh — registration must happen before launch
        // completes. Scheduling happens on scenePhase → .background (TenraApp).
        BackgroundInsightsRefresher.shared.register()
```

`Tenra/TenraApp.swift` — inside the existing `.onChange(of: scenePhase) { _, phase in ... }`, after the whole `if phase == .active { ... }` block, add:

```swift
                if phase == .background {
                    // Ask iOS for a background insights recompute while we're away.
                    BackgroundInsightsRefresher.shared.scheduleNextRefresh()
                }
```

- [ ] **Step 4: Build + full changed-area test sweep**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | head -10
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/InsightSignalServiceTests -only-testing:TenraTests/InsightSignalGeneratorTests 2>&1 | grep -aE "Test case .* failed|\*\* TEST (SUCCEEDED|FAILED)" | tail -5
```

Expected: `BUILD SUCCEEDED`, `** TEST SUCCEEDED **`, no failed cases.

- [ ] **Step 5: Document the on-device verification (do not run here)**

BGTaskScheduler does not run on the Simulator. Report to the user for device verification: run from Xcode on the iPhone, background the app once, pause in the debugger, then

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"dakacom.Tenra.insightsRefresh"]
```

and check the Console for `BackgroundInsightsRefresher` log lines and (with a qualifying signal) a scheduled notification.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Insights/BackgroundInsightsRefresher.swift Tenra/AppDelegate.swift Tenra/TenraApp.swift Tenra/Info.plist
git commit -m "feat(signals): BGAppRefreshTask background insights refresh"
```

---

### Task 6: Docs update

**Files:**
- Modify: `docs/domains/insights.md` (§Signal notifications, around lines 171-176)

- [ ] **Step 1: Rewrite the section entries**

In `docs/domains/insights.md`, in the "Signal notifications (Phase C/D)" section:

1. In the `InsightSignalService` bullet, replace the delivery description `+ 2-per-recompute cap with a 3-min stagger` wording with `+ 2-per-recompute cap; delivery inside a 09:00-21:00 window with randomized spacing (deliveryDates; night signals move to next morning 09:00-10:30); pending signals that stop qualifying are cancelled on the next recompute (history kept — no flapping re-push)`.
2. Replace the known-limitation bullet

```
- ⚠️ Known limitation: signals/digest only (re)compute when InsightsViewModel recomputes (Analytics tab usage). BGAppRefresh follow-up in the audit doc.
```

with

```
- `BackgroundInsightsRefresher` (`Services/Insights/`) — BGAppRefreshTask (`dakacom.Tenra.insightsRefresh`, earliest +4h, registered in AppDelegate, submitted on scenePhase → .background): headless recompute straight from `CoreDataRepository` (no TransactionStore/AppCoordinator), feeds `processInsights(.month)` + digest `reschedule(.week)`. Does NOT run recurring/deposit catch-up — sees data as of the last foreground session. Simulator does not run BGTasks; verify on device via LLDB `_simulateLaunchForTaskWithIdentifier:`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/domains/insights.md
git commit -m "docs(insights): background refresh + delivery window in signal notifications"
```
