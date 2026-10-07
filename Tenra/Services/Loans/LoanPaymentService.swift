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

    /// Генерация полного графика амортизации.
    ///
    /// Replays the loan from `originalPrincipal`, applying early repayments in date order,
    /// with the monthly payment that was in force in each month. A "reduce payment"
    /// repayment overwrites `loanInfo.monthlyPayment`, so replaying every month with the
    /// CURRENT payment (the old behavior) made all rows before the repayment wrong, and
    /// `LoansViewModel.markPaymentsPaid` then wrote a wrong remaining principal from them.
    static func generateAmortizationSchedule(loanInfo: LoanInfo) -> [AmortizationEntry] {
        var schedule: [AmortizationEntry] = []
        var remaining = loanInfo.originalPrincipal
        let calendar = Calendar.current

        guard let startDate = DateFormatters.dateFormatter.date(from: loanInfo.startDate) else {
            return []
        }

        let repayments = loanInfo.earlyRepayments.sorted { $0.date < $1.date }
        let reducePayment = repayments.filter { $0.type == .reducePayment }
        var payment = initialMonthlyPayment(loanInfo: loanInfo, reducePayment: reducePayment)
        var nextRepayment = 0
        var reduceApplied = 0

        for i in 1...loanInfo.termMonths {
            guard remaining > 0 else { break }

            guard let paymentDate = calendar.date(byAdding: .month, value: i, to: startDate) else { break }
            let dateStr = DateFormatters.dateFormatter.string(from: paymentDate)

            // Early repayments made before this payment date, in date order.
            while nextRepayment < repayments.count, repayments[nextRepayment].date < dateStr {
                let repayment = repayments[nextRepayment]
                remaining -= repayment.amount
                nextRepayment += 1
                if repayment.type == .reducePayment {
                    reduceApplied += 1
                    payment = paymentAfterReduction(
                        loanInfo: loanInfo,
                        reducePayment: reducePayment,
                        applied: reduceApplied,
                        remaining: remaining,
                        paymentNumber: i
                    )
                }
            }
            guard remaining > 0 else { break }

            let (interest, principalPart) = paymentBreakdown(
                remainingPrincipal: remaining,
                annualRate: loanInfo.interestRateAnnual,
                monthlyPayment: payment
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

    /// Payment before any "reduce payment" repayment: recorded on the first one, or
    /// recomputed from the original terms for repayments recorded before the field existed.
    private static func initialMonthlyPayment(loanInfo: LoanInfo, reducePayment: [EarlyRepayment]) -> Decimal {
        guard let first = reducePayment.first else { return loanInfo.monthlyPayment }
        return first.paymentBefore ?? calculateMonthlyPayment(
            principal: loanInfo.originalPrincipal,
            annualRate: loanInfo.interestRateAnnual,
            termMonths: loanInfo.termMonths
        )
    }

    /// Payment in force after the `applied`-th "reduce payment" repayment: the next
    /// repayment's recorded `paymentBefore`, the current payment after the last one, or
    /// (legacy entries) the same recomputation `applyEarlyRepayment` performed.
    private static func paymentAfterReduction(
        loanInfo: LoanInfo,
        reducePayment: [EarlyRepayment],
        applied: Int,
        remaining: Decimal,
        paymentNumber: Int
    ) -> Decimal {
        if applied >= reducePayment.count {
            return loanInfo.monthlyPayment
        }
        if let recorded = reducePayment[applied].paymentBefore {
            return recorded
        }
        return calculateMonthlyPayment(
            principal: remaining,
            annualRate: loanInfo.interestRateAnnual,
            termMonths: max(1, loanInfo.termMonths - (paymentNumber - 1))
        )
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
        nextPaymentDate(loanInfo: loanInfo, today: Date(), calendar: .current)
    }

    /// The payment day is clamped separately in each month (day 31 → Feb 28 → Mar 31),
    /// never by adding a month to an already-clamped date (which gave Mar 28). A payment
    /// due today is returned as today.
    static func nextPaymentDate(loanInfo: LoanInfo, today now: Date, calendar: Calendar) -> Date? {
        guard loanInfo.remainingPrincipal > 0 else { return nil }
        let today = calendar.startOfDay(for: now)

        func paymentDate(inMonthOf reference: Date) -> Date? {
            var components = calendar.dateComponents([.year, .month], from: reference)
            let days = calendar.range(of: .day, in: .month, for: reference)?.count ?? 30
            components.day = min(loanInfo.paymentDay, days)
            return calendar.date(from: components)
        }

        guard let thisMonth = paymentDate(inMonthOf: today) else { return nil }
        if thisMonth >= today {
            return thisMonth
        }
        guard let nextMonthReference = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today) else {
            return nil
        }
        return paymentDate(inMonthOf: nextMonthReference)
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
        let paymentBefore = loanInfo.monthlyPayment
        let termBefore = loanInfo.termMonths
        loanInfo.remainingPrincipal -= amount
        loanInfo.earlyRepayments.append(EarlyRepayment(
            date: date, amount: amount, type: type, note: note,
            paymentBefore: paymentBefore, termBefore: termBefore
        ))

        let remaining = remainingPayments(loanInfo: loanInfo)
        guard remaining > 0 else { return }

        switch type {
        case .reduceTerm:
            // Пересчитываем сколько платежей осталось при текущем размере платежа
            loanInfo.termMonths = loanInfo.paymentsMade + monthsToRepay(loanInfo)

        case .reducePayment:
            // Пересчитываем ежемесячный платёж для оставшегося срока
            loanInfo.monthlyPayment = calculateMonthlyPayment(
                principal: loanInfo.remainingPrincipal,
                annualRate: loanInfo.interestRateAnnual,
                termMonths: remaining
            )
        }

        // Пересчитываем дату окончания
        refreshEndDate(&loanInfo)
    }

    /// Months the remaining principal takes to repay at the current monthly payment (at
    /// most 600): the term a "reduce term" repayment leaves, and the one undoing it restores.
    private static func monthsToRepay(_ loanInfo: LoanInfo) -> Int {
        if loanInfo.interestRateAnnual > 0 {
            var months = 0
            var left = loanInfo.remainingPrincipal
            while left > 0 && months < 600 {
                let (_, principal) = paymentBreakdown(
                    remainingPrincipal: left,
                    annualRate: loanInfo.interestRateAnnual,
                    monthlyPayment: loanInfo.monthlyPayment
                )
                left -= principal
                months += 1
            }
            return months
        }
        // A zero payment divided the principal by zero and trapped converting NaN to Int.
        guard loanInfo.monthlyPayment > 0 else { return remainingPayments(loanInfo: loanInfo) }
        return Int(ceil(NSDecimalNumber(decimal: loanInfo.remainingPrincipal / loanInfo.monthlyPayment).doubleValue))
    }

    /// `endDate` = `startDate` + `termMonths`.
    private static func refreshEndDate(_ loanInfo: inout LoanInfo) {
        guard let start = DateFormatters.dateFormatter.date(from: loanInfo.startDate),
              let end = Calendar.current.date(byAdding: .month, value: loanInfo.termMonths, to: start)
        else { return }
        loanInfo.endDate = DateFormatters.dateFormatter.string(from: end)
    }

    // MARK: - Early Repayment Transaction

    /// Create an early repayment transaction and update loan state.
    /// Returns the transaction + updated loanInfo so the caller can persist both.
    ///
    /// **Orientation contract:** for loan-payment transactions
    /// `accountId = SOURCE bank` (where money leaves) and
    /// `targetAccountId = LOAN` (debt being repaid). Mirrors `.expense` semantics:
    /// the user-facing "from" account is the bank, and the loan is the destination.
    static func createEarlyRepaymentTransaction(
        account: Account,
        loanInfo: LoanInfo,
        amount: Decimal,
        date: String,
        type: EarlyRepaymentType,
        sourceAccountId: String,
        sourceAccountName: String?,
        note: String? = nil,
        category: String? = nil
    ) -> (transaction: Transaction, updatedLoanInfo: LoanInfo) {
        var updated = loanInfo

        applyEarlyRepayment(
            loanInfo: &updated,
            amount: amount,
            date: date,
            type: type,
            note: note
        )

        // See `createManualPayment` — we leave the category empty when no override
        // is supplied so the UI infers the label from the transaction type.
        let resolvedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let transaction = Transaction(
            id: UUID().uuidString,
            date: date,
            description: note ?? "",
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            currency: account.currency,
            type: .loanEarlyRepayment,
            category: resolvedCategory,
            accountId: sourceAccountId,
            targetAccountId: account.id,
            accountName: sourceAccountName,
            targetAccountName: account.name
        )

        return (transaction, updated)
    }

    // MARK: - Manual Payment

    /// Create a manual loan payment transaction and update loan state.
    /// Returns the transaction + updated loanInfo so the caller can persist both.
    ///
    /// **Orientation contract:** for loan-payment transactions
    /// `accountId = SOURCE bank` (where money leaves) and
    /// `targetAccountId = LOAN` (debt being repaid). Mirrors `.expense` semantics:
    /// the user-facing "from" account is the bank, and the loan is the destination.
    static func createManualPayment(
        account: Account,
        loanInfo: LoanInfo,
        paymentAmount: Decimal,
        dateStr: String,
        sourceAccountId: String,
        sourceAccountName: String?,
        description: String? = nil,
        category: String? = nil
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

        // Leave the description empty when the user doesn't supply one — the UI
        // infers the label from `type == .loanPayment` via CategoryDisplay.
        // Don't prefill a default "Loan payment" string.
        let resolvedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // Category is optional — when the user doesn't pick one we leave it empty
        // and let the UI infer the label from `type == .loanPayment` via
        // `CategoryDisplay.displayName`. We deliberately do NOT fall back to the
        // legacy `loanPaymentCategoryName` constant, which used to surface as a
        // confusing technical pseudo-category in pickers and history.
        let resolvedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let transaction = Transaction(
            id: UUID().uuidString,
            date: dateStr,
            description: resolvedDescription,
            amount: NSDecimalNumber(decimal: actualPayment).doubleValue,
            currency: account.currency,
            type: .loanPayment,
            category: resolvedCategory,
            accountId: sourceAccountId,
            targetAccountId: account.id,
            accountName: sourceAccountName,
            targetAccountName: account.name
        )

        return (transaction, updated)
    }

    // MARK: - Link Existing Payments

    /// Recalculates loan state after linking existing transactions.
    /// `linkedPayments` are the actual payments (chronological), each with its amount in
    /// the loan's currency — the principal is reduced by the ACTUAL amounts paid, not by
    /// the annuity `monthlyPayment` (linked transactions are arbitrary and rarely equal it).
    static func recalculateAfterLinking(
        loanInfo: inout LoanInfo,
        linkedPayments: [(date: String, amount: Decimal)]
    ) {
        loanInfo.paymentsMade = linkedPayments.count
        loanInfo.lastPaymentDate = linkedPayments.last?.date

        if loanInfo.loanType == .installment {
            // No interest split — principal drops by the sum of the actual amounts paid.
            let totalPaid = linkedPayments.reduce(Decimal(0)) { $0 + $1.amount }
            loanInfo.remainingPrincipal = max(loanInfo.originalPrincipal - totalPaid, 0)
            loanInfo.totalInterestPaid = 0
            return
        }

        // Annuity: split each ACTUAL payment into interest (on the current remaining) and
        // principal, walking chronologically.
        var remaining = loanInfo.originalPrincipal
        var totalInterest: Decimal = 0

        for payment in linkedPayments {
            let breakdown = paymentBreakdown(
                remainingPrincipal: remaining,
                annualRate: loanInfo.interestRateAnnual,
                monthlyPayment: payment.amount
            )
            remaining -= breakdown.principal
            totalInterest += breakdown.interest
        }

        loanInfo.remainingPrincipal = max(remaining, 0)
        loanInfo.totalInterestPaid = totalInterest
    }

    // MARK: - Recorded Payments

    /// A loan payment transaction the way its loan's state sees it: the type, the date and
    /// the amount in the loan's currency.
    struct RecordedPayment: Equatable, Sendable {
        let type: TransactionType
        let date: String
        let amount: Decimal
    }

    /// `transaction`, a payment to a loan in `loanCurrency`, as a `RecordedPayment`.
    ///
    /// A payment in another currency converts through the conversion it was saved with
    /// (`TransactionConversion.storedRate`: the equivalent its row shows, or the paying
    /// account's leg in `sourceCurrency`), else at `rates`, else stays unconverted (the
    /// canonical cold-cache fallback). Never `convertedAmount ?? amount` as it is: that is in
    /// the paying account's currency, not the loan's (CLAUDE.md red flag 6).
    static func recordedPayment(
        _ transaction: Transaction,
        loanCurrency: String,
        sourceCurrency: String?,
        rates: RateSnapshot
    ) -> RecordedPayment {
        let amount: Double
        if transaction.currency == loanCurrency {
            amount = transaction.amount
        } else if let rate = TransactionConversion.storedRate(
            in: transaction,
            from: transaction.currency,
            to: loanCurrency,
            accountCurrency: sourceCurrency
        ) {
            amount = transaction.amount * rate
        } else {
            amount = rates.convert(transaction.amount, from: transaction.currency, to: loanCurrency)
                ?? transaction.amount
        }
        return RecordedPayment(type: transaction.type, date: transaction.date, amount: Decimal(amount).rounded(2))
    }

    /// Interest and principal of a regular payment of `amount` (principal + interest, what
    /// its transaction holds) that left `remainingAfter` owed: the inverse of
    /// `createManualPayment` and `recalculateAfterLinking`, where the interest is the month's
    /// rate on the principal owed before the payment. Owed before = (after + amount) / (1 + rate).
    static func split(
        recordedPayment amount: Decimal,
        remainingAfter: Decimal,
        annualRate: Decimal
    ) -> (interest: Decimal, principal: Decimal) {
        guard annualRate > 0 else { return (interest: 0, principal: amount) }
        let monthlyRate = annualRate / 100 / 12
        let owedBefore = (remainingAfter + amount) / (1 + monthlyRate)
        let interest = (owedBefore * monthlyRate).rounded(2)
        return (interest: interest, principal: amount - interest)
    }

    /// The principal owed before `payments` were made, given `remainingAfter`, what is owed
    /// after all of them: each one undone, newest first. An early repayment took its whole
    /// amount off the principal, a regular payment its principal part.
    static func remainingBefore(
        _ payments: [RecordedPayment],
        remainingAfter: Decimal,
        annualRate: Decimal
    ) -> Decimal {
        var remaining = remainingAfter
        for payment in payments.sorted(by: { $0.date > $1.date }) {
            if payment.type == .loanEarlyRepayment {
                remaining += payment.amount
            } else {
                remaining += split(recordedPayment: payment.amount, remainingAfter: remaining, annualRate: annualRate).principal
            }
        }
        return remaining
    }

    // MARK: - Deleted Payment

    /// `loanInfo` with a deleted payment's own effect taken off, so the loan stops counting
    /// it: the debt (and with it the loan's balance, which is the remaining principal), the
    /// interest paid, the payments made and the last payment date; for an early repayment,
    /// its schedule entry and the term or monthly payment it re-planned.
    ///
    /// Only that payment is undone. The ones recorded after it keep the interest split they
    /// were recorded with (a loan's state is written as each payment is recorded, it is not
    /// replayed), and "Mark as paid" in the schedule stays as it is (`markedPaidThrough`).
    ///
    /// - Parameter otherPayments: the loan's payments that remain (both types). Those dated
    ///   after `deleted` were applied on top of it and are undone first, to find the
    ///   principal owed when it was made; the latest regular one becomes `lastPaymentDate`.
    static func reversingPayment(
        _ deleted: RecordedPayment,
        in loanInfo: LoanInfo,
        otherPayments: [RecordedPayment]
    ) -> LoanInfo {
        var info = loanInfo
        switch deleted.type {
        case .loanPayment:
            let owedAfter = remainingBefore(
                otherPayments.filter { $0.date > deleted.date },
                remainingAfter: info.remainingPrincipal,
                annualRate: info.interestRateAnnual
            )
            let parts = split(
                recordedPayment: deleted.amount,
                remainingAfter: owedAfter,
                annualRate: info.interestRateAnnual
            )
            restorePrincipal(parts.principal, in: &info)
            info.totalInterestPaid = max(0, info.totalInterestPaid - parts.interest)
            info.paymentsMade = max(0, info.paymentsMade - 1)
            // Only when this payment (or another one that day) wrote it; a later payment or
            // a "Mark as paid" keeps theirs.
            if info.lastPaymentDate == deleted.date {
                let latestPayment = otherPayments.filter { $0.type == .loanPayment }.map(\.date).max()
                info.lastPaymentDate = [latestPayment, info.markedPaidThrough].compactMap { $0 }.max()
            }
        case .loanEarlyRepayment:
            reverseEarlyRepayment(deleted, in: &info)
        default:
            break
        }
        return info
    }

    /// Gives `principal` back to the debt. Never above the original principal (a "Mark as
    /// unpaid" reset to nothing paid already gave everything back), unless the debt was
    /// already above it.
    private static func restorePrincipal(_ principal: Decimal, in info: inout LoanInfo) {
        let ceiling = max(info.originalPrincipal, info.remainingPrincipal)
        info.remainingPrincipal = max(0, min(info.remainingPrincipal + principal, ceiling))
    }

    /// The inverse of `applyEarlyRepayment`: the principal back, the schedule entry gone, and
    /// the term ("reduce term") or the monthly payment ("reduce payment") it re-planned
    /// restored from what the entry recorded, or recomputed from the restored principal when
    /// it recorded nothing (older entries) or a later repayment of the same kind re-planned
    /// on top of it.
    private static func reverseEarlyRepayment(_ deleted: RecordedPayment, in info: inout LoanInfo) {
        let entries = info.earlyRepayments
        // The entry the transaction recorded: same date and amount (the newest such), or the
        // only one that day when the amount no longer matches (an edited transaction).
        let sameDay = entries.indices.filter { entries[$0].date == deleted.date }
        let matching = sameDay.last { abs(entries[$0].amount - deleted.amount) <= LoanInfo.paidOffThreshold }
        guard let index = matching ?? (sameDay.count == 1 ? sameDay.first : nil) else {
            // No entry to undo: the debt still gets the money back, it is what the balance shows.
            restorePrincipal(deleted.amount, in: &info)
            return
        }
        let entry = entries[index]
        restorePrincipal(entry.amount, in: &info)

        // The next repayment of the same kind, in the schedule's (date) order.
        let next = entries.indices
            .filter { other in
                other != index && entries[other].type == entry.type
                    && (entries[other].date > entry.date || (entries[other].date == entry.date && other > index))
            }
            .min { (entries[$0].date, $0) < (entries[$1].date, $1) }

        var remainingEntries = entries
        if let next {
            // It re-planned from the payment or term this one left. Hand it the one in force
            // before this one, so the schedule replays the right payment up to it and
            // deleting it later restores the right term.
            let later = entries[next]
            remainingEntries[next] = EarlyRepayment(
                date: later.date,
                amount: later.amount,
                type: later.type,
                note: later.note,
                paymentBefore: entry.paymentBefore ?? later.paymentBefore,
                termBefore: entry.termBefore ?? later.termBefore
            )
        }
        remainingEntries.remove(at: index)
        info.earlyRepayments = remainingEntries

        switch entry.type {
        case .reducePayment:
            if next == nil, let paymentBefore = entry.paymentBefore {
                info.monthlyPayment = paymentBefore
            } else {
                let months = remainingPayments(loanInfo: info)
                if months > 0 {
                    info.monthlyPayment = calculateMonthlyPayment(
                        principal: info.remainingPrincipal,
                        annualRate: info.interestRateAnnual,
                        termMonths: months
                    )
                }
            }
        case .reduceTerm:
            if next == nil, let termBefore = entry.termBefore {
                info.termMonths = termBefore
            } else if info.remainingPrincipal > 0 {
                info.termMonths = info.paymentsMade + monthsToRepay(info)
            }
        }
        refreshEndDate(&info)
    }

    // MARK: - Entered Currency

    /// A payment typed in the amount field's `currency`, in the loan's own currency (the
    /// one the schedule runs in), at the cached rate. Nil when no rate is cached. The
    /// payment forms ignored the field's currency, so 100 typed as USD paid 100 ₸ off a
    /// KZT loan.
    static func amountInLoanCurrency(_ amount: Decimal, currency: String, loanCurrency: String) -> Decimal? {
        guard !currency.isEmpty, currency != loanCurrency else { return amount }
        guard let converted = CurrencyConverter.convertSync(
            amount: NSDecimalNumber(decimal: amount).doubleValue,
            from: currency,
            to: loanCurrency
        ) else { return nil }
        return Decimal(converted).rounded(2)
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
