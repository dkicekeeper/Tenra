//
//  DepositInterestService.swift
//  Tenra
//
//  Service for calculating deposit interest accrual and posting
//

import Foundation

nonisolated enum DepositInterestService {

    // MARK: - Public Methods

    /// Walks days from `lastInterestCalculationDate` to today, accruing daily interest
    /// against a transient `runningPrincipal` and posting on `interestPostingDay`.
    /// Idempotent — repeated calls within the same day are no-ops for the walk
    /// (same-day events affect balance through the standard transaction pipeline,
    /// not through this service).
    static func reconcileDepositInterest(
        account: inout Account,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        guard var depositInfo = account.depositInfo else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Anchor the walk at the START of the current (unposted) period rather than
        // at `lastInterestCalculationDate`. The current period is always recomputed
        // from scratch, so principal changes backdated into the open period (e.g. a
        // transfer recorded after a prior reconcile already advanced the calc date)
        // are picked up. Previously the calc date marched ahead of such days and the
        // interest for them was lost forever.
        let periodStart = currentPeriodStart(depositInfo: depositInfo)
        guard periodStart < today else {
            depositInfo.lastInterestCalculationDate = DateFormatters.dateFormatter.string(from: today)
            account.depositInfo = depositInfo
            return
        }

        // Events that move the running principal: anything that touches the deposit
        // account (as source or target) and is principal-affecting. Events on/before
        // `startDate` are already baked into `initialPrincipal`.
        let depositId = account.id
        let events = allTransactions
            .filter { tx in
                tx.type.affectsDepositPrincipal &&
                (tx.accountId == depositId || tx.targetAccountId == depositId) &&
                tx.date > depositInfo.startDate
            }
            .sorted { $0.date < $1.date }

        let walkStart = calendar.date(byAdding: .day, value: 1, to: periodStart)!
        let walkStartStr = DateFormatters.dateFormatter.string(from: walkStart)

        // Seed the principal as it stood at `periodStart` — including any interest
        // capitalized by earlier postings (their `.depositInterestAccrual` events are
        // dated on/before the period start, so they fold into the seed here).
        var runningPrincipal: Decimal = depositInfo.initialPrincipal
        var eventIdx = 0
        while eventIdx < events.count && events[eventIdx].date < walkStartStr {
            runningPrincipal += principalDelta(
                for: events[eventIdx],
                accountId: depositId,
                capitalizationEnabled: depositInfo.capitalizationEnabled
            )
            eventIdx += 1
        }

        var currentDate = walkStart
        var totalAccrued: Decimal = 0

        // `<= today` (not `< today`): the posting day must be reached even when it IS
        // today, otherwise opening the app ON the posting day (e.g. June 1) skips the
        // just-ended period's posting entirely. Matches `calculateInterestToToday`,
        // which the UI uses to display the accrued amount — keeping the two in sync.
        // Idempotency is preserved: the walk fully recomputes from the period start
        // each call, and `postInterest` guards against a duplicate accrual in the month.
        while currentDate <= today {
            let currentDateStr = DateFormatters.dateFormatter.string(from: currentDate)

            // Post BEFORE accruing this day's interest. Interest posted on the posting
            // day (e.g. June 1) covers the period that just ENDED — through the day
            // before. The posting day's own interest belongs to the NEW period, so it
            // must be accrued AFTER the flush, not folded into the amount being posted.
            // (Accruing-then-posting added one extra day to every posting.)
            if isPostingDay(date: currentDate, postingDay: depositInfo.interestPostingDay) {
                let postingAmount = totalAccrued
                if postingAmount > 0 {
                    let posted = postInterest(
                        account: &account,
                        depositInfo: &depositInfo,
                        amount: postingAmount,
                        date: currentDate,
                        allTransactions: allTransactions,
                        onTransactionCreated: onTransactionCreated
                    )
                    if posted, depositInfo.capitalizationEnabled {
                        runningPrincipal += postingAmount
                    }
                    totalAccrued = 0
                }
            }

            // Value date T+1: interest each day is computed on the balance at the
            // START of the day (= the previous day's close), so money earns only from
            // the day AFTER it arrives — matching how KZ banks (incl. Freedom) accrue.
            // Hence `< currentDateStr`, not `<=`: an event dated `currentDate` is folded
            // in tomorrow. (Pre-walk already consumed events before walkStart, so this
            // never double-folds.)
            while eventIdx < events.count && events[eventIdx].date < currentDateStr {
                runningPrincipal += principalDelta(
                    for: events[eventIdx],
                    accountId: depositId,
                    capitalizationEnabled: depositInfo.capitalizationEnabled
                )
                eventIdx += 1
            }

            let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
            let dailyInterest = runningPrincipal * (rate / 100) / 365
            totalAccrued += dailyInterest

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        depositInfo.interestAccruedForCurrentPeriod = totalAccrued
        depositInfo.lastInterestCalculationDate = DateFormatters.dateFormatter.string(from: today)
        account.depositInfo = depositInfo
    }

    /// Signed amount by which a principal-affecting transaction moves the deposit's
    /// running principal. Uses `convertedAmount` for the inflow side (already in the
    /// target's currency); falls back to `amount` for the source side (deposit IS source,
    /// so amount is in deposit currency).
    ///
    /// NOTE (M-1, data-integrity refactor): this is intentionally a SEPARATE definition
    /// from `BalanceCalculationEngine.contribution`. They model DIFFERENT quantities —
    /// `principalDelta` builds the interest-bearing principal; `contribution` builds the
    /// displayed balance (principal + interest). They must NOT be merged. The essential
    /// divergence is `.depositInterestAccrual`: it is gated here by `capitalizationEnabled`
    /// (the principal only grows when interest compounds), whereas `contribution` always
    /// adds it to the balance (the interest is the client's either way). Unifying would
    /// make non-capitalizing deposits compound incorrectly.
    /// Behavior is pinned by `DepositPrincipalDeltaCharacterizationTests`; the cross-
    /// currency transfer inflow now uses `targetAmount` (deposit currency) — see
    /// `DepositCrossCurrencyTransferTests` and docs/domains/deposits.md.
    static func principalDelta(for tx: Transaction, accountId: String, capitalizationEnabled: Bool) -> Decimal {
        switch tx.type {
        case .depositTopUp, .income:
            guard tx.accountId == accountId else { return 0 }
            return Decimal(tx.convertedAmount ?? tx.amount)
        case .depositWithdrawal, .expense:
            guard tx.accountId == accountId else { return 0 }
            return -Decimal(tx.convertedAmount ?? tx.amount)
        case .depositInterestAccrual:
            guard tx.accountId == accountId, capitalizationEnabled else { return 0 }
            return Decimal(tx.convertedAmount ?? tx.amount)
        case .internalTransfer:
            if tx.targetAccountId == accountId {
                // Inflow: credit the TARGET-side amount, which is in the deposit's own
                // currency. Using source-side convertedAmount here would add a wrong-
                // currency amount to the principal for cross-currency top-ups.
                return Decimal(tx.targetAmount ?? tx.convertedAmount ?? tx.amount)
            }
            if tx.accountId == accountId {
                // Outflow: deposit is the source, so `amount` is already in the deposit's
                // currency.
                return -Decimal(tx.amount)
            }
            return 0
        default:
            return 0
        }
    }

    /// Добавляет новую ставку в историю
    static func addRateChange(depositInfo: inout DepositInfo, effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        let rateChange = RateChange(effectiveFrom: effectiveFrom, annualRate: annualRate, note: note)
        depositInfo.interestRateHistory.append(rateChange)
        depositInfo.interestRateHistory.sort { rate1, rate2 in
            guard let date1 = DateFormatters.dateFormatter.date(from: rate1.effectiveFrom),
                  let date2 = DateFormatters.dateFormatter.date(from: rate2.effectiveFrom) else {
                return false
            }
            return date1 < date2
        }
        depositInfo.interestRateAnnual = annualRate
    }

    /// Получает текущую ставку для депозита
    static func currentRate(depositInfo: DepositInfo) -> Decimal {
        return depositInfo.interestRateAnnual
    }

    /// Walks deposit events so daily interest uses the principal that was actually
    /// present on each day. Read-only — does not mutate `depositInfo`.
    static func calculateInterestToToday(
        depositInfo: DepositInfo,
        accountId: String,
        allTransactions: [Transaction]
    ) -> Decimal {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Recompute the current period's accrual fresh from its start (see
        // reconcileDepositInterest). Anchoring at the period start — not at the
        // persisted `lastInterestCalculationDate`/`interestAccruedForCurrentPeriod` —
        // means backdated/late principal changes are always reflected.
        let periodStart = currentPeriodStart(depositInfo: depositInfo)
        guard periodStart < today else { return 0 }

        let events = allTransactions
            .filter { tx in
                tx.type.affectsDepositPrincipal &&
                (tx.accountId == accountId || tx.targetAccountId == accountId) &&
                tx.date > depositInfo.startDate
            }
            .sorted { $0.date < $1.date }

        let walkStart = calendar.date(byAdding: .day, value: 1, to: periodStart)!
        let walkStartStr = DateFormatters.dateFormatter.string(from: walkStart)

        var runningPrincipal: Decimal = depositInfo.initialPrincipal
        var eventIdx = 0
        while eventIdx < events.count && events[eventIdx].date < walkStartStr {
            runningPrincipal += principalDelta(
                for: events[eventIdx],
                accountId: accountId,
                capitalizationEnabled: depositInfo.capitalizationEnabled
            )
            eventIdx += 1
        }

        var currentDate = walkStart
        var totalAccrued: Decimal = 0

        while currentDate <= today {
            let currentDateStr = DateFormatters.dateFormatter.string(from: currentDate)
            // Value date T+1 — see reconcileDepositInterest. Money earns from the day
            // after it arrives, so fold events dated strictly before `currentDate`.
            while eventIdx < events.count && events[eventIdx].date < currentDateStr {
                runningPrincipal += principalDelta(
                    for: events[eventIdx],
                    accountId: accountId,
                    capitalizationEnabled: depositInfo.capitalizationEnabled
                )
                eventIdx += 1
            }
            let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
            let dailyInterest = runningPrincipal * (rate / 100) / 365
            totalAccrued += dailyInterest

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return totalAccrued
    }

    /// Получает следующую дату начисления процентов
    static func nextPostingDate(depositInfo: DepositInfo) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let _ = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestPostingMonth) else {
            return nil
        }

        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = depositInfo.interestPostingDay

        if let date = calendar.date(from: components),
           let lastDayOfMonth = calendar.range(of: .day, in: .month, for: date)?.upperBound {
            if depositInfo.interestPostingDay >= lastDayOfMonth {
                components.day = lastDayOfMonth - 1
            }
        }

        guard let currentMonthPostingDate = calendar.date(from: components) else {
            return nil
        }

        if currentMonthPostingDate <= today {
            var nextMonthComponents = calendar.dateComponents([.year, .month], from: today)
            nextMonthComponents.month = (nextMonthComponents.month ?? 0) + 1
            nextMonthComponents.day = depositInfo.interestPostingDay

            if let nextMonthDate = calendar.date(from: nextMonthComponents),
               let lastDayOfMonth = calendar.range(of: .day, in: .month, for: nextMonthDate)?.upperBound {
                if depositInfo.interestPostingDay >= lastDayOfMonth {
                    nextMonthComponents.day = lastDayOfMonth - 1
                }
            }

            return calendar.date(from: nextMonthComponents)
        }

        return currentMonthPostingDate
    }

    // MARK: - Private Methods

    /// Получает ставку для конкретной даты из истории (история отсортирована по дате)
    private static func rateForDate(date: Date, history: [RateChange]) -> Decimal {
        // Binary-search compatible: history is sorted ascending by effectiveFrom date
        var applicableRate: Decimal = 0
        for rateChange in history {
            guard let effectiveDate = DateFormatters.dateFormatter.date(from: rateChange.effectiveFrom) else {
                continue
            }
            if effectiveDate <= date {
                applicableRate = rateChange.annualRate
            } else {
                break
            }
        }
        return applicableRate > 0 ? applicableRate : (history.first?.annualRate ?? 0)
    }

    /// Start of the current (unposted) interest period — the posting date in
    /// `lastInterestPostingMonth`, clamped to the month's length, but never earlier
    /// than `startDate`. Accrual is recomputed from here on every reconcile/display
    /// call, so principal changes backdated into the open period are always picked up.
    /// (The previous incremental design advanced `lastInterestCalculationDate` past
    /// such days and could never re-accrue them — the root cause of "interest = 0".)
    private static func currentPeriodStart(depositInfo: DepositInfo) -> Date {
        let calendar = Calendar.current
        let startDate = DateFormatters.dateFormatter.date(from: depositInfo.startDate)
            .map { calendar.startOfDay(for: $0) }

        guard let lastPostingMonth = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestPostingMonth) else {
            return startDate ?? calendar.startOfDay(for: Date())
        }
        var comps = calendar.dateComponents([.year, .month], from: lastPostingMonth)
        let monthDate = calendar.date(from: comps) ?? lastPostingMonth
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthDate)?.count ?? depositInfo.interestPostingDay
        comps.day = min(depositInfo.interestPostingDay, daysInMonth)
        let postingDate = calendar.date(from: comps).map { calendar.startOfDay(for: $0) } ?? monthDate

        if let s = startDate, s > postingDate { return s }
        return postingDate
    }

    /// `true` when `date` falls on the deposit's monthly interest-posting day
    /// (clamped to the last day of months shorter than `postingDay`). Within a single
    /// forward walk each posting day is a distinct month, so no month-tracking is
    /// needed — the walk anchors after the last posted period.
    private static func isPostingDay(date: Date, postingDay: Int) -> Bool {
        let calendar = Calendar.current
        let normalized = calendar.startOfDay(for: date)
        let day = calendar.component(.day, from: normalized)
        var targetDay = postingDay
        if let daysInMonth = calendar.range(of: .day, in: .month, for: normalized)?.count, postingDay > daysInMonth {
            targetDay = daysInMonth
        }
        return day == targetDay
    }

    /// Posts interest as a `.depositInterestAccrual` transaction. Returns `true` when a
    /// new transaction is created (so the caller may compound `runningPrincipal`).
    /// Updates only `lastInterestPostingMonth` on `depositInfo` — the running principal
    /// is owned by `reconcileDepositInterest`; the deposit's balance is owned by the
    /// standard balance pipeline (which picks up the new transaction event).
    @discardableResult
    private static func postInterest(
        account: inout Account,
        depositInfo: inout DepositInfo,
        amount: Decimal,
        date: Date,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) -> Bool {
        let calendar = Calendar.current
        let dateNormalized = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: dateNormalized)
        let monthStart = calendar.date(from: components)!
        let monthStartString = DateFormatters.dateFormatter.string(from: monthStart)

        // Idempotency check — in-memory (TransactionStore holds all transactions)
        let alreadyPosted = allTransactions.contains { tx in
            tx.accountId == account.id
            && tx.type == .depositInterestAccrual
            && tx.date >= monthStartString
        }
        if alreadyPosted {
            depositInfo.lastInterestPostingMonth = monthStartString
            return false
        }

        let dateString = DateFormatters.dateFormatter.string(from: date)
        let amountDouble = NSDecimalNumber(decimal: amount).doubleValue
        let transactionId = generateDepositInterestTransactionID(
            depositId: account.id,
            month: monthStartString,
            amount: amountDouble,
            currency: account.currency
        )

        let transaction = Transaction(
            id: transactionId,
            date: dateString,
            description: String(localized: "deposit.interestAccrual.description", defaultValue: "Interest"),
            amount: amountDouble,
            currency: account.currency,
            convertedAmount: nil,
            type: .depositInterestAccrual,
            category: String(localized: "deposit.interestAccrual.category", defaultValue: "Interest"),
            subcategory: nil,
            accountId: account.id,
            targetAccountId: nil,
            accountName: account.name,
            targetAccountName: nil,
            recurringSeriesId: nil,
            recurringOccurrenceId: nil,
            createdAt: Date().timeIntervalSince1970
        )

        onTransactionCreated(transaction)

        depositInfo.lastInterestPostingMonth = monthStartString
        account.depositInfo = depositInfo
        return true
    }

    /// Генерирует стабильный детерминированный ID для транзакции начисления процентов
    /// Использует djb2-хэш — детерминирован между запусками (в отличие от Swift Hasher)
    private static func generateDepositInterestTransactionID(depositId: String, month: String, amount: Double, currency: String) -> String {
        let normalizedAmount = String(format: "%.2f", amount)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespaces).uppercased()
        let key = "deposit_interest|\(depositId)|\(month)|\(normalizedAmount)|\(normalizedCurrency)"

        // djb2 hash — stable across process launches
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = hash &* 31 &+ UInt64(byte)
        }
        return String(format: "di_%016llx", hash)
    }
}
