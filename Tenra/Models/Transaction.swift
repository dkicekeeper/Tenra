//
//  Transaction.swift
//  Tenra
//
//  Created on 2024
//

import Foundation

enum TransactionType: String, Codable, Sendable {
    case income
    case expense
    case internalTransfer = "internal"
    case depositTopUp = "deposit_topup"
    case depositWithdrawal = "deposit_withdrawal"
    case depositInterestAccrual = "deposit_interest"
    case loanPayment = "loan_payment"
    case loanEarlyRepayment = "loan_early_repayment"

    /// Static category name stored for internalTransfer transactions.
    /// Must be locale-independent so it survives locale changes and app restarts.
    nonisolated static let transferCategoryName = "Transfer"
    /// Locale-independent category name for loan payment transactions.
    nonisolated static let loanPaymentCategoryName = "Loan Payment"

    /// `true` for transaction types that can change a deposit's running principal when
    /// the deposit appears as either source or target. The reconcile walk uses this to
    /// pre-filter events; `principalDelta` resolves the actual sign per side.
    nonisolated var affectsDepositPrincipal: Bool {
        switch self {
        case .depositTopUp, .depositWithdrawal, .depositInterestAccrual,
             .income, .expense, .internalTransfer:
            return true
        case .loanPayment, .loanEarlyRepayment:
            return false
        }
    }
}

struct Transaction: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let date: String // YYYY-MM-DD
    let description: String
    let amount: Double // Основная сумма операции
    let currency: String // Валюта операции
    let convertedAmount: Double? // Конвертированная сумма в валюте счета
    let type: TransactionType
    let category: String
    let subcategory: String?
    let accountId: String?
    let targetAccountId: String?
    let accountName: String? // Название счета-источника (для отображения удаленных счетов)
    let targetAccountName: String? // Название счета-получателя (для отображения удаленных счетов)
    let targetCurrency: String? // Валюта счета получателя
    let targetAmount: Double? // Сумма на счете получателя (по курсу на момент транзакции)
    let recurringSeriesId: String? // Связь с периодической серией
    let recurringOccurrenceId: String? // Связь с конкретным occurrence
    let createdAt: TimeInterval // Timestamp создания транзакции для сортировки
    
    nonisolated init(
        id: String,
        date: String,
        description: String,
        amount: Double,
        currency: String,
        convertedAmount: Double? = nil,
        type: TransactionType,
        category: String,
        subcategory: String? = nil,
        accountId: String? = nil,
        targetAccountId: String? = nil,
        accountName: String? = nil,
        targetAccountName: String? = nil,
        targetCurrency: String? = nil,
        targetAmount: Double? = nil,
        recurringSeriesId: String? = nil,
        recurringOccurrenceId: String? = nil,
        createdAt: TimeInterval? = nil
    ) {
        self.id = id
        self.date = date
        self.description = description
        self.amount = amount
        self.currency = currency
        self.convertedAmount = convertedAmount
        self.type = type
        self.category = category
        self.subcategory = subcategory
        self.accountId = accountId
        self.targetAccountId = targetAccountId
        self.accountName = accountName
        self.targetAccountName = targetAccountName
        self.targetCurrency = targetCurrency
        self.targetAmount = targetAmount
        self.recurringSeriesId = recurringSeriesId
        self.recurringOccurrenceId = recurringOccurrenceId
        // Если createdAt не передан, используем текущее время
        self.createdAt = createdAt ?? Date().timeIntervalSince1970
    }
    
    // Кастомный decoder для обратной совместимости
    enum CodingKeys: String, CodingKey {
        case id, date, time, description, amount, currency, convertedAmount, type, category, subcategory
        case accountId, targetAccountId, accountName, targetAccountName, targetCurrency, targetAmount, recurringSeriesId, recurringOccurrenceId, createdAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        date = try container.decode(String.self, forKey: .date)
        // Игнорируем поле time для обратной совместимости
        _ = try? container.decodeIfPresent(String.self, forKey: .time)
        description = try container.decode(String.self, forKey: .description)
        amount = try container.decode(Double.self, forKey: .amount)
        currency = try container.decode(String.self, forKey: .currency)
        convertedAmount = try container.decodeIfPresent(Double.self, forKey: .convertedAmount)
        type = try container.decode(TransactionType.self, forKey: .type)
        category = try container.decode(String.self, forKey: .category)
        subcategory = try container.decodeIfPresent(String.self, forKey: .subcategory)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        targetAccountId = try container.decodeIfPresent(String.self, forKey: .targetAccountId)
        accountName = try container.decodeIfPresent(String.self, forKey: .accountName)
        targetAccountName = try container.decodeIfPresent(String.self, forKey: .targetAccountName)
        targetCurrency = try container.decodeIfPresent(String.self, forKey: .targetCurrency)
        targetAmount = try container.decodeIfPresent(Double.self, forKey: .targetAmount)
        recurringSeriesId = try container.decodeIfPresent(String.self, forKey: .recurringSeriesId)
        recurringOccurrenceId = try container.decodeIfPresent(String.self, forKey: .recurringOccurrenceId)
        // Для обратной совместимости: если createdAt отсутствует, используем дату транзакции
        if let existingCreatedAt = try? container.decodeIfPresent(TimeInterval.self, forKey: .createdAt) {
            createdAt = existingCreatedAt
        } else {
            // Если createdAt отсутствует, используем дату транзакции как createdAt
            let dateFormatter = DateFormatters.dateFormatter
            if let transactionDate = dateFormatter.date(from: date) {
                createdAt = transactionDate.timeIntervalSince1970
            } else {
                // Если не удалось распарсить дату, используем текущее время
                createdAt = Date().timeIntervalSince1970
            }
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        // Не кодируем поле time, так как оно больше не существует
        try container.encode(description, forKey: .description)
        try container.encode(amount, forKey: .amount)
        try container.encode(currency, forKey: .currency)
        try container.encodeIfPresent(convertedAmount, forKey: .convertedAmount)
        try container.encode(type, forKey: .type)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(subcategory, forKey: .subcategory)
        try container.encodeIfPresent(accountId, forKey: .accountId)
        try container.encodeIfPresent(targetAccountId, forKey: .targetAccountId)
        try container.encodeIfPresent(accountName, forKey: .accountName)
        try container.encodeIfPresent(targetAccountName, forKey: .targetAccountName)
        try container.encodeIfPresent(targetCurrency, forKey: .targetCurrency)
        try container.encodeIfPresent(targetAmount, forKey: .targetAmount)
        try container.encodeIfPresent(recurringSeriesId, forKey: .recurringSeriesId)
        try container.encodeIfPresent(recurringOccurrenceId, forKey: .recurringOccurrenceId)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct CategoryRule: Codable, Equatable {
    let description: String
    let category: String
    let subcategory: String?
}

struct AnalysisResult: Codable {
    let transactions: [Transaction]
    let summary: Summary
}

struct Summary: Codable, Equatable, Hashable {
    let totalIncome: Double
    let totalExpenses: Double
    let totalInternalTransfers: Double
    let netFlow: Double
    let currency: String
    let startDate: String
    let endDate: String
    let plannedAmount: Double // Сумма всех невыполненных recurring операций
}

// MARK: - Deposit Models

struct RateChange: Codable, Equatable, Hashable {
    let effectiveFrom: String // YYYY-MM-DD
    let annualRate: Decimal
    let note: String?

    nonisolated init(effectiveFrom: String, annualRate: Decimal, note: String? = nil) {
        self.effectiveFrom = effectiveFrom
        self.annualRate = annualRate
        self.note = note
    }
}

struct DepositInfo: Codable, Equatable, Hashable {
    var bankName: String
    var capitalizationEnabled: Bool
    var interestRateAnnual: Decimal
    var interestRateHistory: [RateChange]
    var interestPostingDay: Int
    var lastInterestCalculationDate: String // YYYY-MM-DD
    var lastInterestPostingMonth: String // YYYY-MM-01
    var interestAccruedForCurrentPeriod: Decimal // running daily accrual since last posting
    var initialPrincipal: Decimal // creation-time amount (= Account.initialBalance)
    var startDate: String // YYYY-MM-DD — events on/before this are baked into initialPrincipal

    enum CodingKeys: String, CodingKey {
        case bankName, capitalizationEnabled
        case interestRateAnnual, interestRateHistory, interestPostingDay
        case lastInterestCalculationDate, lastInterestPostingMonth, interestAccruedForCurrentPeriod
        case initialPrincipal, startDate
        // Legacy keys retained for read-only migration of pre-unification payloads.
        case principalBalance
        case interestAccruedNotCapitalized
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bankName = try container.decode(String.self, forKey: .bankName)
        capitalizationEnabled = try container.decode(Bool.self, forKey: .capitalizationEnabled)
        interestRateAnnual = try container.decode(Decimal.self, forKey: .interestRateAnnual)
        interestRateHistory = try container.decode([RateChange].self, forKey: .interestRateHistory)
        interestPostingDay = try container.decode(Int.self, forKey: .interestPostingDay)
        lastInterestCalculationDate = try container.decode(String.self, forKey: .lastInterestCalculationDate)
        lastInterestPostingMonth = try container.decode(String.self, forKey: .lastInterestPostingMonth)
        interestAccruedForCurrentPeriod = try container.decode(Decimal.self, forKey: .interestAccruedForCurrentPeriod)
        // Pre-migration payloads have only `principalBalance`; treat it as the initial principal.
        let legacyPrincipal = try container.decodeIfPresent(Decimal.self, forKey: .principalBalance)
        initialPrincipal = (try container.decodeIfPresent(Decimal.self, forKey: .initialPrincipal))
            ?? legacyPrincipal
            ?? 0
        startDate = (try container.decodeIfPresent(String.self, forKey: .startDate)) ?? lastInterestCalculationDate
    }

    init(
        bankName: String,
        initialPrincipal: Decimal,
        capitalizationEnabled: Bool = true,
        interestRateAnnual: Decimal,
        interestRateHistory: [RateChange]? = nil,
        interestPostingDay: Int,
        lastInterestCalculationDate: String? = nil,
        lastInterestPostingMonth: String? = nil,
        interestAccruedForCurrentPeriod: Decimal = 0,
        startDate: String? = nil
    ) {
        self.bankName = bankName
        self.capitalizationEnabled = capitalizationEnabled
        self.interestRateAnnual = interestRateAnnual
        self.interestRateHistory = interestRateHistory ?? [RateChange(
            effectiveFrom: lastInterestCalculationDate ?? DateFormatters.dateFormatter.string(from: Date()),
            annualRate: interestRateAnnual
        )]
        self.interestPostingDay = interestPostingDay
        let today = DateFormatters.dateFormatter.string(from: Date())
        self.lastInterestCalculationDate = lastInterestCalculationDate ?? today
        if let lastMonth = lastInterestPostingMonth {
            self.lastInterestPostingMonth = lastMonth
        } else {
            let calendar = Calendar.current
            let components = calendar.dateComponents([.year, .month], from: Date())
            if let date = calendar.date(from: components) {
                self.lastInterestPostingMonth = DateFormatters.dateFormatter.string(from: date)
            } else {
                self.lastInterestPostingMonth = today
            }
        }
        self.interestAccruedForCurrentPeriod = interestAccruedForCurrentPeriod
        self.initialPrincipal = initialPrincipal
        self.startDate = startDate ?? lastInterestCalculationDate ?? today
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bankName, forKey: .bankName)
        try container.encode(capitalizationEnabled, forKey: .capitalizationEnabled)
        try container.encode(interestRateAnnual, forKey: .interestRateAnnual)
        try container.encode(interestRateHistory, forKey: .interestRateHistory)
        try container.encode(interestPostingDay, forKey: .interestPostingDay)
        try container.encode(lastInterestCalculationDate, forKey: .lastInterestCalculationDate)
        try container.encode(lastInterestPostingMonth, forKey: .lastInterestPostingMonth)
        try container.encode(interestAccruedForCurrentPeriod, forKey: .interestAccruedForCurrentPeriod)
        try container.encode(initialPrincipal, forKey: .initialPrincipal)
        try container.encode(startDate, forKey: .startDate)
    }
}


// MARK: - Loan Models

enum LoanType: String, Codable, Equatable, Hashable {
    case annuity = "annuity"           // Аннуитетный кредит (фиксированный платёж, % меняется)
    case installment = "installment"   // Рассрочка (0% процентов, равные платежи)
}

enum EarlyRepaymentType: String, Codable, Equatable, Hashable {
    case reduceTerm = "reduce_term"       // Уменьшить срок, сохранить платёж
    case reducePayment = "reduce_payment" // Уменьшить платёж, сохранить срок
}

struct EarlyRepayment: Codable, Equatable, Hashable {
    let date: String        // YYYY-MM-DD
    let amount: Decimal     // Сумма досрочного погашения
    let type: EarlyRepaymentType
    let note: String?

    nonisolated init(date: String, amount: Decimal, type: EarlyRepaymentType, note: String? = nil) {
        self.date = date
        self.amount = amount
        self.type = type
        self.note = note
    }
}

struct LoanInfo: Codable, Equatable, Hashable {
    var bankName: String
    var loanType: LoanType

    // Основная сумма
    var originalPrincipal: Decimal      // Первоначальная сумма кредита (не меняется)
    var remainingPrincipal: Decimal     // Текущий остаток долга

    // Проценты
    var interestRateAnnual: Decimal     // Годовая ставка (0 для рассрочки)
    var interestRateHistory: [RateChange] // История изменения ставок (переиспользует RateChange)
    var totalInterestPaid: Decimal      // Суммарные уплаченные проценты

    // Срок
    var termMonths: Int                 // Общий срок в месяцах
    var startDate: String               // YYYY-MM-DD начало кредита
    var endDate: String                 // YYYY-MM-DD расчётная дата окончания

    // График платежей
    var monthlyPayment: Decimal         // Фиксированный ежемесячный платёж
    var paymentDay: Int                 // 1-31, день месяца для платежа
    var paymentsMade: Int               // Количество совершённых платежей
    var lastPaymentDate: String?        // YYYY-MM-DD последнего платежа
    var lastReconciliationDate: String  // YYYY-MM-DD — для идемпотентной сверки

    // Досрочные погашения
    var earlyRepayments: [EarlyRepayment]

    enum CodingKeys: String, CodingKey {
        case bankName, loanType, originalPrincipal, remainingPrincipal
        case interestRateAnnual, interestRateHistory, totalInterestPaid
        case termMonths, startDate, endDate
        case monthlyPayment, paymentDay, paymentsMade, lastPaymentDate, lastReconciliationDate
        case earlyRepayments
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bankName = try container.decode(String.self, forKey: .bankName)
        loanType = try container.decode(LoanType.self, forKey: .loanType)
        originalPrincipal = try container.decode(Decimal.self, forKey: .originalPrincipal)
        remainingPrincipal = try container.decode(Decimal.self, forKey: .remainingPrincipal)
        interestRateAnnual = try container.decode(Decimal.self, forKey: .interestRateAnnual)
        interestRateHistory = try container.decode([RateChange].self, forKey: .interestRateHistory)
        totalInterestPaid = try container.decode(Decimal.self, forKey: .totalInterestPaid)
        termMonths = try container.decode(Int.self, forKey: .termMonths)
        startDate = try container.decode(String.self, forKey: .startDate)
        endDate = try container.decode(String.self, forKey: .endDate)
        monthlyPayment = try container.decode(Decimal.self, forKey: .monthlyPayment)
        paymentDay = try container.decode(Int.self, forKey: .paymentDay)
        paymentsMade = try container.decode(Int.self, forKey: .paymentsMade)
        lastPaymentDate = try container.decodeIfPresent(String.self, forKey: .lastPaymentDate)
        lastReconciliationDate = try container.decode(String.self, forKey: .lastReconciliationDate)
        earlyRepayments = try container.decode([EarlyRepayment].self, forKey: .earlyRepayments)
    }

    init(
        bankName: String,
        loanType: LoanType,
        originalPrincipal: Decimal,
        remainingPrincipal: Decimal? = nil,
        interestRateAnnual: Decimal = 0,
        interestRateHistory: [RateChange]? = nil,
        totalInterestPaid: Decimal = 0,
        termMonths: Int,
        startDate: String,
        endDate: String? = nil,
        monthlyPayment: Decimal? = nil,
        paymentDay: Int,
        paymentsMade: Int = 0,
        lastPaymentDate: String? = nil,
        lastReconciliationDate: String? = nil,
        earlyRepayments: [EarlyRepayment] = []
    ) {
        self.bankName = bankName
        self.loanType = loanType
        self.originalPrincipal = originalPrincipal
        self.remainingPrincipal = remainingPrincipal ?? originalPrincipal
        self.interestRateAnnual = interestRateAnnual
        self.interestRateHistory = interestRateHistory ?? [RateChange(
            effectiveFrom: startDate,
            annualRate: interestRateAnnual
        )]
        self.totalInterestPaid = totalInterestPaid
        self.termMonths = termMonths
        self.startDate = startDate

        // Вычисляем дату окончания если не передана
        if let end = endDate {
            self.endDate = end
        } else {
            let calendar = Calendar.current
            if let start = DateFormatters.dateFormatter.date(from: startDate),
               let end = calendar.date(byAdding: .month, value: termMonths, to: start) {
                self.endDate = DateFormatters.dateFormatter.string(from: end)
            } else {
                self.endDate = DateFormatters.dateFormatter.string(from: Date())
            }
        }

        // Вычисляем ежемесячный платёж если не передан
        if let payment = monthlyPayment {
            self.monthlyPayment = payment
        } else {
            self.monthlyPayment = LoanPaymentService.calculateMonthlyPayment(
                principal: originalPrincipal,
                annualRate: interestRateAnnual,
                termMonths: termMonths
            )
        }

        self.paymentDay = paymentDay
        self.paymentsMade = paymentsMade
        self.lastPaymentDate = lastPaymentDate
        self.lastReconciliationDate = lastReconciliationDate ?? DateFormatters.dateFormatter.string(from: Date())
        self.earlyRepayments = earlyRepayments
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bankName, forKey: .bankName)
        try container.encode(loanType, forKey: .loanType)
        try container.encode(originalPrincipal, forKey: .originalPrincipal)
        try container.encode(remainingPrincipal, forKey: .remainingPrincipal)
        try container.encode(interestRateAnnual, forKey: .interestRateAnnual)
        try container.encode(interestRateHistory, forKey: .interestRateHistory)
        try container.encode(totalInterestPaid, forKey: .totalInterestPaid)
        try container.encode(termMonths, forKey: .termMonths)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(monthlyPayment, forKey: .monthlyPayment)
        try container.encode(paymentDay, forKey: .paymentDay)
        try container.encode(paymentsMade, forKey: .paymentsMade)
        try container.encodeIfPresent(lastPaymentDate, forKey: .lastPaymentDate)
        try container.encode(lastReconciliationDate, forKey: .lastReconciliationDate)
        try container.encode(earlyRepayments, forKey: .earlyRepayments)
    }
}

struct Account: Identifiable, Codable, Equatable, Hashable {
    let id: String
    var name: String
    var currency: String
    var iconSource: IconSource? // Unified icon/logo source (SF Symbol, brand service)
    var depositInfo: DepositInfo? // Опциональная информация о депозите (nil для обычных счетов)
    var loanInfo: LoanInfo? // Опциональная информация о кредите/рассрочке (nil для обычных счетов)
    var createdDate: Date?
    var shouldCalculateFromTransactions: Bool // Режим расчета баланса: true = из транзакций, false = manual
    var initialBalance: Double?  // Начальный баланс при создании счёта (задаётся один раз, не меняется)
    var balance: Double          // Текущий баланс (обновляется BalanceCoordinator инкрементально)
    var order: Int? // Order for displaying accounts

    init(id: String = UUID().uuidString, name: String, currency: String, iconSource: IconSource? = nil, depositInfo: DepositInfo? = nil, loanInfo: LoanInfo? = nil, createdDate: Date? = nil, shouldCalculateFromTransactions: Bool = false, initialBalance: Double? = nil, balance: Double? = nil, order: Int? = nil) {
        self.id = id
        self.name = name
        self.currency = currency
        self.iconSource = iconSource
        self.depositInfo = depositInfo
        self.loanInfo = loanInfo
        self.createdDate = createdDate ?? Date()
        self.shouldCalculateFromTransactions = shouldCalculateFromTransactions
        let resolvedInitial = initialBalance ?? (shouldCalculateFromTransactions ? 0.0 : nil)
        self.initialBalance = resolvedInitial
        // Current balance starts equal to initialBalance; updated later by BalanceCoordinator
        self.balance = balance ?? resolvedInitial ?? 0.0
        self.order = order
    }

    // Кастомный decoder для обратной совместимости со старыми данными
    enum CodingKeys: String, CodingKey {
        case id, name, balance, currency, bankLogo, iconSource, depositInfo, loanInfo, createdDate, shouldCalculateFromTransactions, initialBalance, order
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        currency = try container.decode(String.self, forKey: .currency)

        // Migration: try new iconSource field first, fallback to old bankLogo
        if let savedIconSource = try container.decodeIfPresent(IconSource.self, forKey: .iconSource) {
            iconSource = savedIconSource
        } else {
            iconSource = nil
        }

        depositInfo = try container.decodeIfPresent(DepositInfo.self, forKey: .depositInfo)
        loanInfo = try container.decodeIfPresent(LoanInfo.self, forKey: .loanInfo)
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate)
        shouldCalculateFromTransactions = try container.decodeIfPresent(Bool.self, forKey: .shouldCalculateFromTransactions) ?? false

        // initialBalance — starting balance at account creation, stored separately
        if let savedInitialBalance = try container.decodeIfPresent(Double.self, forKey: .initialBalance) {
            initialBalance = savedInitialBalance
        } else if let oldBalance = try? container.decodeIfPresent(Double.self, forKey: .balance) {
            initialBalance = shouldCalculateFromTransactions ? 0.0 : oldBalance
        } else {
            initialBalance = shouldCalculateFromTransactions ? 0.0 : nil
        }

        // balance — current running balance; on decode use balance field if present, else initialBalance
        let decodedBalance = try? container.decodeIfPresent(Double.self, forKey: .balance)
        balance = decodedBalance ?? initialBalance ?? 0.0

        order = try container.decodeIfPresent(Int.self, forKey: .order)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(currency, forKey: .currency)
        try container.encodeIfPresent(iconSource, forKey: .iconSource)
        try container.encodeIfPresent(depositInfo, forKey: .depositInfo)
        try container.encodeIfPresent(loanInfo, forKey: .loanInfo)
        try container.encodeIfPresent(createdDate, forKey: .createdDate)
        try container.encode(shouldCalculateFromTransactions, forKey: .shouldCalculateFromTransactions)
        try container.encodeIfPresent(initialBalance, forKey: .initialBalance)
        try container.encode(balance, forKey: .balance)
        try container.encodeIfPresent(order, forKey: .order)
    }
    
    // Computed property для проверки, является ли счет депозитом
    nonisolated var isDeposit: Bool {
        depositInfo != nil
    }

    // Computed property для проверки, является ли счет кредитом/рассрочкой
    nonisolated var isLoan: Bool {
        loanInfo != nil
    }
}
