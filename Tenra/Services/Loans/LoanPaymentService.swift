//
//  LoanPaymentService.swift
//  Tenra
//
//  Service for loan/installment payment calculations: annuity formula,
//  amortization schedules, payment breakdowns, early repayment handling.
//

import Foundation

nonisolated enum LoanPaymentService {

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
            let applicableKeys = earlyRepaymentsByMonth.keys.filter { $0 < dateStr }
            for erDate in applicableKeys {
                remaining -= earlyRepaymentsByMonth.removeValue(forKey: erDate) ?? 0
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

    // MARK: - Early Repayment Transaction

    /// Create an early repayment transaction and update loan state.
    /// Returns the transaction + updated loanInfo so the caller can persist both.
    static func createEarlyRepaymentTransaction(
        account: Account,
        loanInfo: LoanInfo,
        amount: Decimal,
        date: String,
        type: EarlyRepaymentType,
        sourceAccountId: String,
        sourceAccountName: String?,
        note: String? = nil
    ) -> (transaction: Transaction, updatedLoanInfo: LoanInfo) {
        var updated = loanInfo

        applyEarlyRepayment(
            loanInfo: &updated,
            amount: amount,
            date: date,
            type: type,
            note: note
        )

        let transaction = Transaction(
            id: UUID().uuidString,
            date: date,
            description: note ?? String(localized: "loan.earlyRepayment.description", defaultValue: "Early repayment"),
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            currency: account.currency,
            type: .loanEarlyRepayment,
            category: TransactionType.loanPaymentCategoryName,
            accountId: account.id,
            targetAccountId: sourceAccountId,
            accountName: account.name,
            targetAccountName: sourceAccountName
        )

        return (transaction, updated)
    }

    // MARK: - Manual Payment

    /// Create a manual loan payment transaction and update loan state.
    /// Returns the transaction + updated loanInfo so the caller can persist both.
    static func createManualPayment(
        account: Account,
        loanInfo: LoanInfo,
        paymentAmount: Decimal,
        dateStr: String,
        sourceAccountId: String,
        sourceAccountName: String?
    ) -> (transaction: Transaction, updatedLoanInfo: LoanInfo) {
        var updated = loanInfo

        let (interest, principalPart) = paymentBreakdown(
            remainingPrincipal: updated.remainingPrincipal,
            annualRate: updated.interestRateAnnual,
            monthlyPayment: paymentAmount
        )

        let actualPrincipal = min(principalPart, updated.remainingPrincipal)
        let actualPayment = actualPrincipal + interest

        updated.remainingPrincipal -= actualPrincipal
        updated.totalInterestPaid += interest
        updated.paymentsMade += 1
        updated.lastPaymentDate = dateStr

        let transaction = Transaction(
            id: UUID().uuidString,
            date: dateStr,
            description: String(localized: "loan.payment.description", defaultValue: "Loan payment"),
            amount: NSDecimalNumber(decimal: actualPayment).doubleValue,
            currency: account.currency,
            type: .loanPayment,
            category: TransactionType.loanPaymentCategoryName,
            accountId: account.id,
            targetAccountId: sourceAccountId,
            accountName: account.name,
            targetAccountName: sourceAccountName
        )

        return (transaction, updated)
    }

    // MARK: - Link Existing Payments

    /// Recalculates loan state after linking existing transactions.
    static func recalculateAfterLinking(
        loanInfo: inout LoanInfo,
        linkedPaymentCount: Int,
        linkedPaymentDates: [String]
    ) {
        loanInfo.paymentsMade = linkedPaymentCount
        loanInfo.lastPaymentDate = linkedPaymentDates.last

        if loanInfo.loanType == .installment {
            let totalPaid = loanInfo.monthlyPayment * Decimal(linkedPaymentCount)
            loanInfo.remainingPrincipal = loanInfo.originalPrincipal - totalPaid
            loanInfo.totalInterestPaid = 0
            return
        }

        // Annuity: walk payments chronologically, compute interest/principal split
        var remaining = loanInfo.originalPrincipal
        var totalInterest: Decimal = 0

        for _ in 0..<linkedPaymentCount {
            let breakdown = paymentBreakdown(
                remainingPrincipal: remaining,
                annualRate: loanInfo.interestRateAnnual,
                monthlyPayment: loanInfo.monthlyPayment
            )
            remaining -= breakdown.principal
            totalInterest += breakdown.interest
        }

        loanInfo.remainingPrincipal = max(remaining, 0)
        loanInfo.totalInterestPaid = totalInterest
    }

    // MARK: - Private Helpers

    private static func daysInMonth(date: Date) -> Int {
        let calendar = Calendar.current
        return calendar.range(of: .day, in: .month, for: date)?.count ?? 30
    }
}

// MARK: - Decimal Rounding Helper

private extension Decimal {
    nonisolated func rounded(_ scale: Int) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, .bankers)
        return result
    }
}
