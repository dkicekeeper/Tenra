//
//  DepositInterestService.swift
//  Tenra
//
//  Service for calculating deposit interest accrual and posting
//

import Foundation

nonisolated enum DepositInterestService {

    // MARK: - Public Methods

    /// Рассчитывает проценты за период и обновляет информацию депозита.
    /// Идемпотентный: можно вызывать многократно без дублирования транзакций.
    ///
    /// `principalBalance` is recomputed on every call so same-day events
    /// (e.g. a Top-up made today after this morning's reconcile) are reflected
    /// immediately. The day-by-day interest accrual loop only runs when there
    /// are new days to walk.
    static func reconcileDepositInterest(
        account: inout Account,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        guard var depositInfo = account.depositInfo else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastCalcDate = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestCalculationDate) else {
            return
        }
        let lastCalcDateNormalized = calendar.startOfDay(for: lastCalcDate)

        // Principal events that change the historical principal over time.
        // Events dated on or before `startDate` are baked into `initialPrincipal`.
        let events = allTransactions
            .filter { tx in
                tx.accountId == account.id &&
                tx.type.affectsDepositPrincipal &&
                tx.date > depositInfo.startDate
            }
            .sorted { $0.date < $1.date }

        if lastCalcDateNormalized < today {
            // Day-by-day interest accrual walk — only runs when there are new days.
            let walkStart = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
            let walkStartStr = DateFormatters.dateFormatter.string(from: walkStart)

            var runningPrincipal: Decimal = depositInfo.initialPrincipal
            var eventIdx = 0
            while eventIdx < events.count && events[eventIdx].date < walkStartStr {
                runningPrincipal += principalDelta(for: events[eventIdx], capitalizationEnabled: depositInfo.capitalizationEnabled)
                eventIdx += 1
            }

            var currentDate = walkStart
            var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod

            while currentDate < today {
                let currentDateStr = DateFormatters.dateFormatter.string(from: currentDate)

                while eventIdx < events.count && events[eventIdx].date <= currentDateStr {
                    runningPrincipal += principalDelta(for: events[eventIdx], capitalizationEnabled: depositInfo.capitalizationEnabled)
                    eventIdx += 1
                }

                let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
                let dailyInterest = runningPrincipal * (rate / 100) / 365
                totalAccrued += dailyInterest

                if shouldPostInterest(
                    date: currentDate,
                    postingDay: depositInfo.interestPostingDay,
                    lastPostingMonth: depositInfo.lastInterestPostingMonth
                ) {
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

                currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
            }

            depositInfo.interestAccruedForCurrentPeriod = totalAccrued
            depositInfo.lastInterestCalculationDate = DateFormatters.dateFormatter.string(from: today)
        }

        // ALWAYS recompute principalBalance from `initialPrincipal` walking every event
        // up to and including today. This makes same-day events show in the displayed
        // balance immediately, regardless of whether the day-by-day walk ran above.
        let todayStr = DateFormatters.dateFormatter.string(from: today)
        var principal: Decimal = depositInfo.initialPrincipal
        for tx in events where tx.date <= todayStr {
            principal += principalDelta(for: tx, capitalizationEnabled: depositInfo.capitalizationEnabled)
        }
        depositInfo.principalBalance = principal

        account.depositInfo = depositInfo
    }

    /// Signed amount by which the given deposit-related transaction moves the running principal.
    /// Uses `convertedAmount` when present (already in deposit currency) and falls back to
    /// `amount`. Internal so unit tests can drive it directly.
    static func principalDelta(for tx: Transaction, capitalizationEnabled: Bool) -> Decimal {
        let raw = tx.convertedAmount ?? tx.amount
        let amt = Decimal(raw)
        switch tx.type {
        case .depositTopUp, .income:
            return amt
        case .depositWithdrawal, .expense:
            return -amt
        case .depositInterestAccrual:
            return capitalizationEnabled ? amt : 0
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

    /// Рассчитывает проценты на сегодня (без сохранения).
    /// Legacy overload using cached `principalBalance`. Callers without transaction access
    /// (callsites that just render UI) use this; the historical-accurate overload
    /// `(depositInfo:accountId:allTransactions:)` walks deposit events for precision.
    static func calculateInterestToToday(depositInfo: DepositInfo) -> Decimal {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastCalcDate = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestCalculationDate) else {
            return depositInfo.interestAccruedForCurrentPeriod
        }
        let lastCalcDateNormalized = calendar.startOfDay(for: lastCalcDate)

        var currentDate = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
        var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod

        while currentDate <= today {
            let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
            let baseAmount = depositInfo.principalBalance
            let dailyInterest = baseAmount * (rate / 100) / 365
            totalAccrued += dailyInterest

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return totalAccrued
    }

    /// Рассчитывает проценты на сегодня с учётом исторических топ-апов/снятий.
    /// Unlike the legacy overload, this walks deposit events so daily interest uses
    /// the principal that was actually present on each day.
    static func calculateInterestToToday(
        depositInfo: DepositInfo,
        accountId: String,
        allTransactions: [Transaction]
    ) -> Decimal {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastCalcDate = DateFormatters.dateFormatter.date(from: depositInfo.lastInterestCalculationDate) else {
            return depositInfo.interestAccruedForCurrentPeriod
        }
        let lastCalcDateNormalized = calendar.startOfDay(for: lastCalcDate)

        let events = allTransactions
            .filter { tx in
                tx.accountId == accountId &&
                (tx.type == .depositTopUp || tx.type == .depositWithdrawal || tx.type == .depositInterestAccrual) &&
                tx.date > depositInfo.startDate
            }
            .sorted { $0.date < $1.date }

        let walkStart = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
        let walkStartStr = DateFormatters.dateFormatter.string(from: walkStart)

        var runningPrincipal: Decimal = depositInfo.initialPrincipal
        var eventIdx = 0
        while eventIdx < events.count && events[eventIdx].date < walkStartStr {
            runningPrincipal += principalDelta(for: events[eventIdx], capitalizationEnabled: depositInfo.capitalizationEnabled)
            eventIdx += 1
        }

        var currentDate = walkStart
        var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod

        while currentDate <= today {
            let currentDateStr = DateFormatters.dateFormatter.string(from: currentDate)
            while eventIdx < events.count && events[eventIdx].date <= currentDateStr {
                runningPrincipal += principalDelta(for: events[eventIdx], capitalizationEnabled: depositInfo.capitalizationEnabled)
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

    /// Проверяет, нужно ли начислить проценты в эту дату
    private static func shouldPostInterest(date: Date, postingDay: Int, lastPostingMonth: String) -> Bool {
        let calendar = Calendar.current
        let dateNormalized = calendar.startOfDay(for: date)

        let day = calendar.component(.day, from: dateNormalized)

        var targetDay = postingDay
        if let lastDayOfMonth = calendar.range(of: .day, in: .month, for: dateNormalized)?.upperBound {
            if postingDay >= lastDayOfMonth {
                targetDay = lastDayOfMonth - 1
            }
        }

        guard day == targetDay else {
            return false
        }

        guard let lastPostingDate = DateFormatters.dateFormatter.date(from: lastPostingMonth) else {
            return true
        }

        let lastPostingComponents = calendar.dateComponents([.year, .month], from: lastPostingDate)
        let currentComponents = calendar.dateComponents([.year, .month], from: dateNormalized)

        return lastPostingComponents.year != currentComponents.year ||
               lastPostingComponents.month != currentComponents.month
    }

    /// Начисляет проценты (создает транзакцию и обновляет баланс).
    /// Returns `true` if a new transaction was posted (so caller can compound running principal).
    /// Note: principal mutation is deferred to the caller in the new historical walk —
    /// `runningPrincipal` is owned by `reconcileDepositInterest`. This function only
    /// updates `interestAccruedNotCapitalized` when capitalization is off, and the
    /// `lastInterestPostingMonth` marker.
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

        if !depositInfo.capitalizationEnabled {
            depositInfo.interestAccruedNotCapitalized += amount
        }

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
