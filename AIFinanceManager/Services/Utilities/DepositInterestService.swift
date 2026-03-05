//
//  DepositInterestService.swift
//  AIFinanceManager
//
//  Service for calculating deposit interest accrual and posting
//

import Foundation

enum DepositInterestService {

    // MARK: - Public Methods

    /// Рассчитывает проценты за период и обновляет информацию депозита
    /// Идемпотентный: можно вызывать многократно без дублирования транзакций
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

        if lastCalcDateNormalized >= today {
            return
        }

        var currentDate = calendar.date(byAdding: .day, value: 1, to: lastCalcDateNormalized)!
        var totalAccrued: Decimal = depositInfo.interestAccruedForCurrentPeriod

        while currentDate < today {
            let rate = rateForDate(date: currentDate, history: depositInfo.interestRateHistory)
            let baseAmount = depositInfo.principalBalance
            let dailyInterest = baseAmount * (rate / 100) / 365
            totalAccrued += dailyInterest

            if shouldPostInterest(
                date: currentDate,
                postingDay: depositInfo.interestPostingDay,
                lastPostingMonth: depositInfo.lastInterestPostingMonth
            ) {
                let postingAmount = totalAccrued
                if postingAmount > 0 {
                    postInterest(
                        account: &account,
                        depositInfo: &depositInfo,
                        amount: postingAmount,
                        date: currentDate,
                        allTransactions: allTransactions,
                        onTransactionCreated: onTransactionCreated
                    )
                    totalAccrued = 0
                }
            }

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        depositInfo.interestAccruedForCurrentPeriod = totalAccrued
        depositInfo.lastInterestCalculationDate = DateFormatters.dateFormatter.string(from: today)

        account.depositInfo = depositInfo
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

    /// Рассчитывает проценты на сегодня (без сохранения)
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

    /// Начисляет проценты (создает транзакцию и обновляет баланс)
    private static func postInterest(
        account: inout Account,
        depositInfo: inout DepositInfo,
        amount: Decimal,
        date: Date,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        let calendar = Calendar.current
        let dateNormalized = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.year, .month], from: dateNormalized)
        let monthStart = calendar.date(from: components)!
        let monthStartString = DateFormatters.dateFormatter.string(from: monthStart)

        // Idempotency check — in-memory (TransactionStore loads all transactions since Phase 16)
        let alreadyPosted = allTransactions.contains { tx in
            tx.accountId == account.id
            && tx.type == .depositInterestAccrual
            && tx.date >= monthStartString
        }
        if alreadyPosted {
            return
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
            description: String(localized: "deposit.interestAccrual.description", defaultValue: "Interest accrual"),
            amount: amountDouble,
            currency: account.currency,
            convertedAmount: nil,
            type: .depositInterestAccrual,
            category: String(localized: "deposit.interestAccrual.category", defaultValue: "Interest accrual"),
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

        if depositInfo.capitalizationEnabled {
            depositInfo.principalBalance += amount
        } else {
            depositInfo.interestAccruedNotCapitalized += amount
        }

        depositInfo.lastInterestPostingMonth = monthStartString
        account.depositInfo = depositInfo
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
