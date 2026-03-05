//
//  LoanPaymentService.swift
//  AIFinanceManager
//
//  Service for loan/installment payment calculations: annuity formula,
//  amortization schedules, payment breakdowns, early repayment handling.
//

import Foundation

enum LoanPaymentService {

    // MARK: - Monthly Payment Calculation

    /// Аннуитетная формула: P = L × [r(1+r)^n] / [(1+r)^n − 1]
    /// Для рассрочки (rate=0): P = L / n
    static func calculateMonthlyPayment(
        principal: Decimal,
        annualRate: Decimal,
        termMonths: Int
    ) -> Decimal {
        guard termMonths > 0 else { return 0 }
        guard annualRate > 0 else {
            // Рассрочка: простое деление
            return (principal / Decimal(termMonths)).rounded(2)
        }

        let rDouble = NSDecimalNumber(decimal: annualRate / 100 / 12).doubleValue
        let pDouble = NSDecimalNumber(decimal: principal).doubleValue
        let n = Double(termMonths)

        let power = pow(1 + rDouble, n)
        let result = pDouble * (rDouble * power) / (power - 1)
        return Decimal(result).rounded(2)
    }

    // MARK: - Payment Breakdown

    /// Разбивка платежа на проценты и тело
    static func paymentBreakdown(
        remainingPrincipal: Decimal,
        annualRate: Decimal,
        monthlyPayment: Decimal
    ) -> (interest: Decimal, principal: Decimal) {
        guard annualRate > 0 else {
            return (interest: 0, principal: monthlyPayment)
        }
        let monthlyRate = annualRate / 100 / 12
        let interestPortion = (remainingPrincipal * monthlyRate).rounded(2)
        let principalPortion = monthlyPayment - interestPortion
        return (interest: interestPortion, principal: principalPortion)
    }

    // MARK: - Amortization Schedule

    struct AmortizationEntry: Identifiable {
        let id: Int // paymentNumber
        let paymentNumber: Int
        let date: String           // YYYY-MM-DD
        let payment: Decimal
        let principal: Decimal
        let interest: Decimal
        let remainingBalance: Decimal
        let isPaid: Bool
    }

    /// Генерация полного графика амортизации
    static func generateAmortizationSchedule(loanInfo: LoanInfo) -> [AmortizationEntry] {
        var schedule: [AmortizationEntry] = []
        var remaining = loanInfo.originalPrincipal
        let calendar = Calendar.current

        guard let startDate = DateFormatters.dateFormatter.date(from: loanInfo.startDate) else {
            return []
        }

        // Собираем даты досрочных погашений для учёта
        var earlyRepaymentsByMonth: [String: Decimal] = [:]
        for er in loanInfo.earlyRepayments {
            earlyRepaymentsByMonth[er.date, default: 0] += er.amount
        }

        for i in 1...loanInfo.termMonths {
            guard remaining > 0 else { break }

            guard let paymentDate = calendar.date(byAdding: .month, value: i, to: startDate) else { break }
            let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)

            // Применяем досрочные погашения, произошедшие до этой даты
            for (erDate, erAmount) in earlyRepaymentsByMonth {
                if erDate < dateStr {
                    remaining -= erAmount
                    earlyRepaymentsByMonth.removeValue(forKey: erDate)
                }
            }
            guard remaining > 0 else { break }

            let (interest, principalPart) = paymentBreakdown(
                remainingPrincipal: remaining,
                annualRate: loanInfo.interestRateAnnual,
                monthlyPayment: loanInfo.monthlyPayment
            )

            // Последний платёж: очищаем остаток точно
            let actualPrincipal = min(principalPart, remaining)
            let actualPayment = actualPrincipal + interest
            remaining -= actualPrincipal

            schedule.append(AmortizationEntry(
                id: i,
                paymentNumber: i,
                date: dateStr,
                payment: actualPayment.rounded(2),
                principal: actualPrincipal.rounded(2),
                interest: interest.rounded(2),
                remainingBalance: max(0, remaining).rounded(2),
                isPaid: i <= loanInfo.paymentsMade
            ))
        }

        return schedule
    }

    // MARK: - Summary Stats

    /// Общая сумма процентов по графику
    static func totalInterestOverLife(loanInfo: LoanInfo) -> Decimal {
        let schedule = generateAmortizationSchedule(loanInfo: loanInfo)
        return schedule.reduce(Decimal(0)) { $0 + $1.interest }
    }

    /// Общая сумма платежей по графику
    static func totalPaymentsOverLife(loanInfo: LoanInfo) -> Decimal {
        let schedule = generateAmortizationSchedule(loanInfo: loanInfo)
        return schedule.reduce(Decimal(0)) { $0 + $1.payment }
    }

    // MARK: - Progress & Helpers

    static func nextPaymentDate(loanInfo: LoanInfo) -> Date? {
        guard loanInfo.remainingPrincipal > 0 else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var components = calendar.dateComponents([.year, .month], from: today)
        components.day = min(loanInfo.paymentDay, daysInMonth(date: today))

        guard let currentMonthDate = calendar.date(from: components) else { return nil }

        if currentMonthDate <= today {
            // Платёж уже прошёл в этом месяце — следующий в следующем месяце
            return calendar.date(byAdding: .month, value: 1, to: currentMonthDate)
        }
        return currentMonthDate
    }

    static func remainingPayments(loanInfo: LoanInfo) -> Int {
        max(0, loanInfo.termMonths - loanInfo.paymentsMade)
    }

    static func progressPercentage(loanInfo: LoanInfo) -> Double {
        guard loanInfo.originalPrincipal > 0 else { return 1.0 }
        let paid = loanInfo.originalPrincipal - loanInfo.remainingPrincipal
        return NSDecimalNumber(decimal: paid / loanInfo.originalPrincipal).doubleValue
    }

    // MARK: - Early Repayment

    /// Применить досрочное погашение: пересчитать срок или платёж
    static func applyEarlyRepayment(
        loanInfo: inout LoanInfo,
        amount: Decimal,
        date: String,
        type: EarlyRepaymentType,
        note: String? = nil
    ) {
        loanInfo.remainingPrincipal -= amount
        loanInfo.earlyRepayments.append(EarlyRepayment(
            date: date, amount: amount, type: type, note: note
        ))

        let remaining = remainingPayments(loanInfo: loanInfo)
        guard remaining > 0 else { return }

        switch type {
        case .reduceTerm:
            // Пересчитываем сколько платежей осталось при текущем размере платежа
            if loanInfo.interestRateAnnual > 0 {
                var newTerm = 0
                var testRemaining = loanInfo.remainingPrincipal
                while testRemaining > 0 && newTerm < 600 {
                    let (_, principal) = paymentBreakdown(
                        remainingPrincipal: testRemaining,
                        annualRate: loanInfo.interestRateAnnual,
                        monthlyPayment: loanInfo.monthlyPayment
                    )
                    testRemaining -= principal
                    newTerm += 1
                }
                loanInfo.termMonths = loanInfo.paymentsMade + newTerm
            } else {
                let newRemaining = Int(
                    ceil(NSDecimalNumber(decimal: loanInfo.remainingPrincipal / loanInfo.monthlyPayment).doubleValue)
                )
                loanInfo.termMonths = loanInfo.paymentsMade + newRemaining
            }

        case .reducePayment:
            // Пересчитываем ежемесячный платёж для оставшегося срока
            loanInfo.monthlyPayment = calculateMonthlyPayment(
                principal: loanInfo.remainingPrincipal,
                annualRate: loanInfo.interestRateAnnual,
                termMonths: remaining
            )
        }

        // Пересчитываем дату окончания
        if let start = DateFormatters.dateFormatter.date(from: loanInfo.startDate) {
            let calendar = Calendar.current
            if let end = calendar.date(byAdding: .month, value: loanInfo.termMonths, to: start) {
                loanInfo.endDate = DateFormatters.dateFormatter.string(from: end)
            }
        }
    }

    // MARK: - Reconciliation

    /// Сверка: создаёт запланированные транзакции платежей на прошедшие даты.
    /// Идемпотентная: можно вызывать многократно без дублирования.
    static func reconcileLoanPayments(
        account: inout Account,
        allTransactions: [Transaction],
        onTransactionCreated: (Transaction) -> Void
    ) {
        guard var loanInfo = account.loanInfo,
              loanInfo.remainingPrincipal > 0 else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        guard let lastReconcDate = DateFormatters.dateFormatter.date(from: loanInfo.lastReconciliationDate) else {
            return
        }
        let lastReconcNormalized = calendar.startOfDay(for: lastReconcDate)

        if lastReconcNormalized >= today { return }

        var checkDate = calendar.date(byAdding: .day, value: 1, to: lastReconcNormalized)!

        while checkDate <= today && loanInfo.remainingPrincipal > 0 {
            if isPaymentDay(date: checkDate, paymentDay: loanInfo.paymentDay, loanInfo: loanInfo) {
                // Идемпотентность: проверяем, был ли уже создан платёж за этот месяц
                let monthStart = monthStartString(for: checkDate)
                let alreadyPaid = allTransactions.contains { tx in
                    tx.accountId == account.id
                    && tx.type == .loanPayment
                    && tx.date >= monthStart
                    && tx.date < nextMonthStartString(for: checkDate)
                }

                if !alreadyPaid {
                    let (interest, principalPart) = paymentBreakdown(
                        remainingPrincipal: loanInfo.remainingPrincipal,
                        annualRate: loanInfo.interestRateAnnual,
                        monthlyPayment: loanInfo.monthlyPayment
                    )

                    let actualPrincipal = min(principalPart, loanInfo.remainingPrincipal)
                    let actualPayment = actualPrincipal + interest

                    let dateString = DateFormatters.dateFormatter.string(from: checkDate)
                    let transactionId = generateLoanPaymentTransactionID(
                        loanId: account.id,
                        month: monthStart,
                        amount: NSDecimalNumber(decimal: actualPayment).doubleValue,
                        currency: account.currency
                    )

                    let transaction = Transaction(
                        id: transactionId,
                        date: dateString,
                        description: String(localized: "loan.payment.description", defaultValue: "Loan payment"),
                        amount: NSDecimalNumber(decimal: actualPayment).doubleValue,
                        currency: account.currency,
                        type: .loanPayment,
                        category: TransactionType.loanPaymentCategoryName,
                        accountId: account.id
                    )

                    onTransactionCreated(transaction)

                    // Обновляем состояние кредита
                    loanInfo.remainingPrincipal -= actualPrincipal
                    loanInfo.totalInterestPaid += interest
                    loanInfo.paymentsMade += 1
                    loanInfo.lastPaymentDate = dateString
                }
            }

            checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
        }

        loanInfo.lastReconciliationDate = DateFormatters.dateFormatter.string(from: today)
        account.loanInfo = loanInfo
    }

    // MARK: - Private Helpers

    private static func isPaymentDay(date: Date, paymentDay: Int, loanInfo: LoanInfo) -> Bool {
        let calendar = Calendar.current
        let day = calendar.component(.day, from: date)
        let maxDay = daysInMonth(date: date)
        let effectivePaymentDay = min(paymentDay, maxDay)

        guard day == effectivePaymentDay else { return false }

        // Проверяем, что этот месяц после начала кредита
        let dateStr = DateFormatters.dateFormatter.string(from: date)
        return dateStr > loanInfo.startDate
    }

    /// Deterministic ID (djb2 hash) — зеркалит DepositInterestService
    private static func generateLoanPaymentTransactionID(
        loanId: String, month: String, amount: Double, currency: String
    ) -> String {
        let normalizedAmount = String(format: "%.2f", amount)
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespaces).uppercased()
        let key = "loan_payment|\(loanId)|\(month)|\(normalizedAmount)|\(normalizedCurrency)"
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = hash &* 31 &+ UInt64(byte)
        }
        return String(format: "lp_%016llx", hash)
    }

    private static func monthStartString(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        let monthStart = calendar.date(from: components)!
        return DateFormatters.dateFormatter.string(from: monthStart)
    }

    private static func nextMonthStartString(for date: Date) -> String {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: date)
        let monthStart = calendar.date(from: components)!
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart)!
        return DateFormatters.dateFormatter.string(from: nextMonth)
    }

    private static func daysInMonth(date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }
}

// MARK: - Decimal Rounding Helper

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }
}
