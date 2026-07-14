//
//  ScreenshotDemoSeeder.swift
//  Tenra
//
//  DEBUG-only: seeds a deterministic, realistic dataset into the (wiped)
//  CoreData store for automated App Store screenshot capture. Runs from
//  `TenraApp.task` BEFORE `AppCoordinator` is constructed, so the normal
//  startup path loads the demo data exactly like real user data.
//
//  Localization: category names resolve through the app's own
//  `String(localized:)` (driven by `-AppleLanguages`); account names and
//  transaction descriptions come from the small per-language lexicon below —
//  they are user data in production, so they never touch Localizable.strings.
//
//  Balances: seeded `Account.balance` values are placeholders. AppCoordinator
//  runs the canonical full recalculation at the end of `initialize()` when
//  ScreenshotDemoMode is active, so displayed balances derive from the seeded
//  transactions via the one true `BalanceCalculationEngine` path.
//

import Foundation

#if DEBUG

enum ScreenshotDemoSeeder {

    /// Wipes the store and seeds the demo dataset. Idempotent per launch —
    /// each capture run starts from the same state.
    static func seed() async {
        guard ScreenshotDemoMode.isActive else { return }

        try? CoreDataStack.shared.resetAllData()

        let dataset = ScreenshotDemoDataset(currency: ScreenshotDemoMode.currencyCode)
        let repository = CoreDataRepository()

        try? repository.saveAccountsSync(dataset.accounts)
        try? repository.saveCategoriesSync(dataset.categories)
        try? repository.saveTransactionsSync(dataset.transactions)

        // Recurring saves are fire-and-forget background tasks — poll until
        // they land so the coordinator's first load sees the subscriptions.
        repository.saveRecurringSeries(dataset.series)
        repository.saveRecurringOccurrences(dataset.occurrences)
        for _ in 0..<30 {
            let seriesCount = repository.loadRecurringSeries().count
            let occurrenceCount = repository.loadRecurringOccurrences().count
            if seriesCount >= dataset.series.count,
               occurrenceCount >= dataset.occurrences.count {
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

// MARK: - Dataset

struct ScreenshotDemoDataset {

    let accounts: [Account]
    let categories: [CustomCategory]
    let transactions: [Transaction]
    let series: [RecurringSeries]
    let occurrences: [RecurringOccurrence]

    init(currency: String) {
        var builder = Builder(currency: currency)
        builder.build()
        self.accounts = builder.accounts
        self.categories = builder.categories
        self.transactions = builder.transactions
        self.series = builder.series
        self.occurrences = builder.occurrences
    }

    // MARK: Builder

    private struct Builder {
        let currency: String
        let savingsCurrency: String
        let lexicon: ScreenshotDemoLexicon
        let calendar = Calendar.current
        var rng = DeterministicRandom(seed: 20260714)

        var accounts: [Account] = []
        var categories: [CustomCategory] = []
        var transactions: [Transaction] = []
        var series: [RecurringSeries] = []
        var occurrences: [RecurringOccurrence] = []

        // Stable ids so re-runs produce identical data.
        let cardId = "demo-account-card"
        let cashId = "demo-account-cash"
        let savingsId = "demo-account-savings"
        let depositId = "demo-account-deposit"
        let loanId = "demo-account-loan"

        init(currency: String) {
            self.currency = currency
            self.savingsCurrency = currency == "USD" ? "EUR" : "USD"
            self.lexicon = ScreenshotDemoLexicon.current()
        }

        // MARK: Amount helpers

        func local(_ eurBase: Double) -> Double {
            ScreenshotDemoCurrency.amount(eurBase, in: currency)
        }

        /// Subscription-style price: keeps the ".99" look for 2-decimal currencies.
        func subscriptionPrice(_ eurBase: Double) -> Double {
            let profile = ScreenshotDemoCurrency.profile(for: currency)
            let raw = eurBase * profile.perEUR
            if profile.decimals > 0 {
                return max(0.99, raw.rounded(.down) + 0.99)
            }
            return ScreenshotDemoCurrency.niceRound(raw, decimals: 0)
        }

        func dateString(daysAgo: Int) -> String {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            return DateFormatters.dateFormatter.string(from: date)
        }

        func dayOfMonth(daysAgo: Int) -> Int {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            return calendar.component(.day, from: date)
        }

        func createdAt(daysAgo: Int, hour: Int = 12) -> TimeInterval {
            let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            let anchored = calendar.date(bySettingHour: hour, minute: 30, second: 0, of: date) ?? date
            return anchored.timeIntervalSince1970
        }

        func presetName(_ presetId: String) -> String {
            guard let preset = CategoryPreset.defaultExpense.first(where: { $0.id == presetId }) else {
                return presetId
            }
            return String(localized: String.LocalizationValue(preset.nameKey))
        }

        // MARK: Build

        mutating func build() {
            buildCategories()
            buildAccounts()
            buildTransactionHistory()
            buildSubscriptions()
        }

        mutating func buildCategories() {
            // EUR-base monthly budgets by preset id; scaled into the demo currency.
            let budgets: [String: Double] = [
                "groceries": 500, "dining": 250, "transport": 150,
                "entertainment": 120, "clothing": 150, "utilities": 200,
                "housing": 900, "health": 100
            ]
            categories = CategoryPreset.defaultExpense.enumerated().map { index, preset in
                var category = CustomCategory(
                    id: "demo-category-\(preset.id)",
                    name: String(localized: String.LocalizationValue(preset.nameKey)),
                    iconSource: preset.iconSource,
                    colorHex: preset.colorHex,
                    type: preset.type,
                    order: index
                )
                if let budget = budgets[preset.id] {
                    category.budgetAmount = local(budget)
                    category.budgetPeriod = .monthly
                    category.budgetResetDay = 1
                    category.budgetStartDate = calendar.date(byAdding: .month, value: -6, to: Date())
                }
                return category
            }
            categories.append(CustomCategory(
                id: "demo-category-salary",
                name: lexicon.salary,
                iconSource: .sfSymbol("banknote.fill"),
                colorHex: "#10b981",
                type: .income,
                order: 0
            ))
        }

        mutating func buildAccounts() {
            let profile = ScreenshotDemoCurrency.profile(for: currency)
            let today = DateFormatters.dateFormatter.string(from: Date())
            _ = today

            let depositStart = dateString(daysAgo: 98)
            let depositInfo = DepositInfo(
                bankName: lexicon.bank,
                initialPrincipal: Decimal(local(3000)),
                capitalizationEnabled: true,
                interestRateAnnual: Decimal(profile.depositRatePercent),
                interestPostingDay: 1,
                lastInterestCalculationDate: depositStart,
                lastInterestPostingMonth: monthStartString(daysAgo: 98),
                startDate: depositStart
            )

            let loanStart = monthStartString(daysAgo: 240)
            let loanInfo = LoanInfo(
                bankName: lexicon.bank,
                loanType: .annuity,
                originalPrincipal: Decimal(local(6000)),
                remainingPrincipal: Decimal(local(4200)),
                interestRateAnnual: Decimal(profile.loanRatePercent),
                termMonths: 24,
                startDate: loanStart,
                paymentDay: 15,
                paymentsMade: 8,
                lastPaymentDate: lastDateString(withDayOfMonth: 15)
            )

            accounts = [
                Account(
                    id: cardId, name: lexicon.card, currency: currency,
                    iconSource: .sfSymbol("creditcard.fill"),
                    createdDate: date(daysAgo: 400),
                    initialBalance: local(1200), order: 0
                ),
                Account(
                    id: cashId, name: lexicon.cash, currency: currency,
                    iconSource: .sfSymbol("banknote"),
                    createdDate: date(daysAgo: 400),
                    initialBalance: local(150), order: 1
                ),
                Account(
                    id: savingsId,
                    name: lexicon.savings.replacingOccurrences(of: "USD", with: savingsCurrency),
                    currency: savingsCurrency,
                    iconSource: .sfSymbol("dollarsign.circle.fill"),
                    createdDate: date(daysAgo: 300),
                    initialBalance: ScreenshotDemoCurrency.amount(800, in: savingsCurrency),
                    order: 2
                ),
                Account(
                    id: depositId, name: lexicon.deposit, currency: currency,
                    iconSource: .sfSymbol("percent"),
                    depositInfo: depositInfo,
                    createdDate: date(daysAgo: 98),
                    initialBalance: local(3000), order: 3
                ),
                Account(
                    id: loanId, name: lexicon.loan, currency: currency,
                    iconSource: .sfSymbol("building.columns.fill"),
                    loanInfo: loanInfo,
                    createdDate: date(daysAgo: 240),
                    initialBalance: 0, order: 4
                )
            ]
        }

        mutating func buildTransactionHistory() {
            let monthlyLoanPayment = (accounts.first { $0.id == loanId }?.loanInfo?.monthlyPayment)
                .map { NSDecimalNumber(decimal: $0).doubleValue } ?? local(280)

            for daysAgo in stride(from: 95, through: 0, by: -1) {
                let dom = dayOfMonth(daysAgo: daysAgo)

                switch dom {
                case 5:
                    addIncome(daysAgo: daysAgo, eurBase: 2800, description: lexicon.salary, category: lexicon.salary)
                case 3:
                    addExpense(daysAgo: daysAgo, eurBase: 850, description: lexicon.rent, presetId: "housing")
                case 10:
                    addExpense(daysAgo: daysAgo, eurBase: 120, description: lexicon.utilities, presetId: "utilities")
                case 12:
                    addExpense(daysAgo: daysAgo, eurBase: 80, description: "Zara", presetId: "clothing")
                case 15:
                    addLoanPayment(daysAgo: daysAgo, amount: ScreenshotDemoCurrency.niceRound(
                        monthlyLoanPayment,
                        decimals: ScreenshotDemoCurrency.profile(for: currency).decimals
                    ))
                case 8:
                    addTransfer(daysAgo: daysAgo, eurBase: 150, targetId: cashId,
                                targetCurrency: currency, description: lexicon.cash)
                case 20:
                    addTransfer(daysAgo: daysAgo, eurBase: 220, targetId: savingsId,
                                targetCurrency: savingsCurrency, description: lexicon.savingsTransfer)
                case 22:
                    addExpense(daysAgo: daysAgo, eurBase: 25, description: lexicon.pharmacy, presetId: "health")
                case 27:
                    addExpense(daysAgo: daysAgo, eurBase: 18, description: lexicon.cinema, presetId: "entertainment")
                default:
                    break
                }

                if daysAgo == 55 {
                    addDepositTopUp(daysAgo: daysAgo, eurBase: 500)
                }

                if daysAgo % 3 == 0 {
                    addExpense(daysAgo: daysAgo, eurBase: 18 + rng.next(upTo: 40),
                               description: lexicon.supermarket, presetId: "groceries")
                }
                if daysAgo % 7 == 2 {
                    addExpense(daysAgo: daysAgo, eurBase: 12 + rng.next(upTo: 14),
                               description: lexicon.lunch, presetId: "dining")
                }
                if daysAgo % 7 == 1 || daysAgo % 7 == 4 {
                    addExpense(daysAgo: daysAgo, eurBase: 3.5 + rng.next(upTo: 3),
                               description: lexicon.coffee, presetId: "dining", fromCash: true)
                }
                if daysAgo % 9 == 0 {
                    addExpense(daysAgo: daysAgo, eurBase: 8 + rng.next(upTo: 12),
                               description: lexicon.taxi, presetId: "transport")
                }
                if daysAgo % 14 == 4 {
                    addExpense(daysAgo: daysAgo, eurBase: 16 + rng.next(upTo: 10),
                               description: lexicon.delivery, presetId: "dining")
                }
                if daysAgo % 14 == 6 {
                    addExpense(daysAgo: daysAgo, eurBase: 22 + rng.next(upTo: 18),
                               description: lexicon.gym, presetId: "services")
                }
            }
        }

        mutating func buildSubscriptions() {
            let subscriptionCategory = presetName("subscriptions")
            let subs: [(name: String, brand: String, eurPrice: Double, chargeDay: Int)] = [
                ("Netflix", "netflix", 12.99, 6),
                ("Spotify", "spotify", 5.99, 14),
                ("YouTube Premium", "youtube", 6.99, 24)
            ]

            for sub in subs {
                let price = subscriptionPrice(sub.eurPrice)
                var chargeDaysAgo: [Int] = []
                for daysAgo in stride(from: 95, through: 0, by: -1)
                where dayOfMonth(daysAgo: daysAgo) == sub.chargeDay {
                    chargeDaysAgo.append(daysAgo)
                }
                guard let firstCharge = chargeDaysAgo.first, let lastCharge = chargeDaysAgo.last else { continue }

                let seriesId = "demo-series-\(sub.brand)"
                series.append(RecurringSeries(
                    id: seriesId,
                    amount: Decimal(price),
                    currency: currency,
                    category: subscriptionCategory,
                    description: sub.name,
                    accountId: cardId,
                    frequency: .monthly,
                    startDate: dateString(daysAgo: firstCharge),
                    lastGeneratedDate: dateString(daysAgo: lastCharge),
                    kind: .subscription,
                    iconSource: .brandService(sub.brand),
                    reminderOffsets: [1, 3],
                    status: .active
                ))

                for (index, daysAgo) in chargeDaysAgo.enumerated() {
                    let txId = "demo-tx-\(sub.brand)-\(index)"
                    transactions.append(Transaction(
                        id: txId,
                        date: dateString(daysAgo: daysAgo),
                        description: sub.name,
                        amount: price,
                        currency: currency,
                        type: .expense,
                        category: subscriptionCategory,
                        accountId: cardId,
                        recurringSeriesId: seriesId,
                        recurringOccurrenceId: "demo-occ-\(sub.brand)-\(index)",
                        createdAt: createdAt(daysAgo: daysAgo, hour: 9)
                    ))
                    occurrences.append(RecurringOccurrence(
                        id: "demo-occ-\(sub.brand)-\(index)",
                        seriesId: seriesId,
                        occurrenceDate: dateString(daysAgo: daysAgo),
                        transactionId: txId
                    ))
                }
            }
        }

        // MARK: Transaction helpers

        mutating func addIncome(daysAgo: Int, eurBase: Double, description: String, category: String) {
            transactions.append(Transaction(
                id: "demo-tx-\(transactions.count)",
                date: dateString(daysAgo: daysAgo),
                description: description,
                amount: local(eurBase),
                currency: currency,
                type: .income,
                category: category,
                accountId: cardId,
                createdAt: createdAt(daysAgo: daysAgo, hour: 10)
            ))
        }

        mutating func addExpense(daysAgo: Int, eurBase: Double, description: String,
                                 presetId: String, fromCash: Bool = false) {
            transactions.append(Transaction(
                id: "demo-tx-\(transactions.count)",
                date: dateString(daysAgo: daysAgo),
                description: description,
                amount: local(eurBase),
                currency: currency,
                type: .expense,
                category: presetName(presetId),
                accountId: fromCash ? cashId : cardId,
                createdAt: createdAt(daysAgo: daysAgo, hour: 13 + transactions.count % 6)
            ))
        }

        mutating func addTransfer(daysAgo: Int, eurBase: Double, targetId: String,
                                  targetCurrency: String, description: String) {
            let sourceAmount = local(eurBase)
            let targetAmount = targetCurrency == currency
                ? sourceAmount
                : ScreenshotDemoCurrency.amount(eurBase, in: targetCurrency)
            transactions.append(Transaction(
                id: "demo-tx-\(transactions.count)",
                date: dateString(daysAgo: daysAgo),
                description: description,
                amount: sourceAmount,
                currency: currency,
                type: .internalTransfer,
                category: TransactionType.transferCategoryName,
                accountId: cardId,
                targetAccountId: targetId,
                targetCurrency: targetCurrency,
                targetAmount: targetAmount,
                createdAt: createdAt(daysAgo: daysAgo, hour: 11)
            ))
        }

        mutating func addDepositTopUp(daysAgo: Int, eurBase: Double) {
            transactions.append(Transaction(
                id: "demo-tx-\(transactions.count)",
                date: dateString(daysAgo: daysAgo),
                description: lexicon.deposit,
                amount: local(eurBase),
                currency: currency,
                type: .depositTopUp,
                category: TransactionType.transferCategoryName,
                accountId: cardId,
                targetAccountId: depositId,
                targetCurrency: currency,
                targetAmount: local(eurBase),
                createdAt: createdAt(daysAgo: daysAgo, hour: 15)
            ))
        }

        mutating func addLoanPayment(daysAgo: Int, amount: Double) {
            transactions.append(Transaction(
                id: "demo-tx-\(transactions.count)",
                date: dateString(daysAgo: daysAgo),
                description: lexicon.loan,
                amount: amount,
                currency: currency,
                type: .loanPayment,
                category: TransactionType.loanPaymentCategoryName,
                accountId: cardId,
                targetAccountId: loanId,
                targetCurrency: currency,
                targetAmount: amount,
                createdAt: createdAt(daysAgo: daysAgo, hour: 16)
            ))
        }

        // MARK: Date helpers

        func date(daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        }

        func monthStartString(daysAgo: Int) -> String {
            let base = date(daysAgo: daysAgo)
            let components = calendar.dateComponents([.year, .month], from: base)
            let start = calendar.date(from: components) ?? base
            return DateFormatters.dateFormatter.string(from: start)
        }

        func lastDateString(withDayOfMonth target: Int) -> String {
            for daysAgo in 0...40 where dayOfMonth(daysAgo: daysAgo) == target {
                return dateString(daysAgo: daysAgo)
            }
            return dateString(daysAgo: 30)
        }
    }
}

// MARK: - Deterministic randomness

/// Tiny LCG so amounts vary realistically but identically across runs.
struct DeterministicRandom {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }

    mutating func next(upTo range: Double) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double((state >> 33) & 0xFFFF_FFFF) / Double(UInt32.max)
        return unit * range
    }
}

// MARK: - Lexicon

/// Account names and transaction descriptions per UI language. These are user
/// data in production (never localized via Localizable.strings), so the demo
/// carries its own small table. Brand names stay global; per-market brands
/// follow docs/localization/<lang>.md. No RU-market brands for uk (see uk.md §1).
struct ScreenshotDemoLexicon {
    let card: String
    let cash: String
    let savings: String
    let deposit: String
    let loan: String
    let bank: String
    let salary: String
    let rent: String
    let utilities: String
    let pharmacy: String
    let cinema: String
    let lunch: String
    let coffee: String
    let supermarket: String
    let taxi: String
    let delivery: String
    let gym: String
    let savingsTransfer: String
    /// Shown as the "recognized" phrase on the demo Voice screen.
    let voiceDemoPhrase: String

    static func current() -> ScreenshotDemoLexicon {
        let preferred = Locale.preferredLanguages.first ?? "en"
        let language = String(preferred.prefix(2)).lowercased()
        let isMX = preferred.lowercased().hasPrefix("es-mx")
        let isCA = preferred.lowercased().hasPrefix("fr-ca")

        switch language {
        case "de":
            return .init(card: "Karte", cash: "Bargeld", savings: "Sparen USD", deposit: "Festgeld",
                         loan: "Kredit", bank: "Bank", salary: "Gehalt", rent: "Miete",
                         utilities: "Nebenkosten", pharmacy: "Apotheke", cinema: "Kino",
                         lunch: "Mittagessen", coffee: "Kaffee", supermarket: "REWE",
                         taxi: "Uber", delivery: "Lieferando", gym: "Fitnessstudio",
                         savingsTransfer: "Sparen",
                         voiceDemoPhrase: "12 Euro für Mittagessen ausgegeben")
        case "es" where isMX:
            return .init(card: "Tarjeta", cash: "Efectivo", savings: "Ahorro USD", deposit: "Depósito",
                         loan: "Préstamo", bank: "Banco", salary: "Sueldo", rent: "Renta",
                         utilities: "Servicios", pharmacy: "Farmacia", cinema: "Cine",
                         lunch: "Comida", coffee: "Café", supermarket: "Soriana",
                         taxi: "DiDi", delivery: "Rappi", gym: "Gimnasio",
                         savingsTransfer: "Ahorro",
                         voiceDemoPhrase: "Gasté 200 pesos en el súper")
        case "es":
            return .init(card: "Tarjeta", cash: "Efectivo", savings: "Ahorro USD", deposit: "Depósito",
                         loan: "Préstamo", bank: "Banco", salary: "Nómina", rent: "Alquiler",
                         utilities: "Suministros", pharmacy: "Farmacia", cinema: "Cine",
                         lunch: "Almuerzo", coffee: "Café", supermarket: "Mercadona",
                         taxi: "Uber", delivery: "Glovo", gym: "Gimnasio",
                         savingsTransfer: "Ahorro",
                         voiceDemoPhrase: "Gasté 12 euros en el súper")
        case "fr":
            return .init(card: "Carte", cash: "Espèces", savings: "Épargne USD", deposit: "Livret",
                         loan: "Crédit", bank: "Banque", salary: "Salaire", rent: "Loyer",
                         utilities: "Charges", pharmacy: "Pharmacie", cinema: "Cinéma",
                         lunch: "Déjeuner", coffee: "Café", supermarket: "Carrefour",
                         taxi: "Uber", delivery: "Uber Eats", gym: "Salle de sport",
                         savingsTransfer: "Épargne",
                         voiceDemoPhrase: isCA ? "12 dollars d'épicerie hier" : "12 euros de courses hier")
        case "tr":
            return .init(card: "Kart", cash: "Nakit", savings: "Birikim USD", deposit: "Mevduat",
                         loan: "Kredi", bank: "Banka", salary: "Maaş", rent: "Kira",
                         utilities: "Faturalar", pharmacy: "Eczane", cinema: "Sinema",
                         lunch: "Öğle yemeği", coffee: "Kahve", supermarket: "Migros",
                         taxi: "Taksi", delivery: "Yemeksepeti", gym: "Spor salonu",
                         savingsTransfer: "Birikim",
                         voiceDemoPhrase: "Markete 450 lira harcadım")
        case "pt":
            return .init(card: "Cartão", cash: "Dinheiro", savings: "Poupança USD", deposit: "CDB",
                         loan: "Empréstimo", bank: "Banco", salary: "Salário", rent: "Aluguel",
                         utilities: "Contas", pharmacy: "Farmácia", cinema: "Cinema",
                         lunch: "Almoço", coffee: "Café", supermarket: "Supermercado",
                         taxi: "99", delivery: "iFood", gym: "Academia",
                         savingsTransfer: "Poupança",
                         voiceDemoPhrase: "Gastei 50 reais no mercado")
        case "it":
            return .init(card: "Carta", cash: "Contanti", savings: "Risparmi USD", deposit: "Deposito",
                         loan: "Prestito", bank: "Banca", salary: "Stipendio", rent: "Affitto",
                         utilities: "Bollette", pharmacy: "Farmacia", cinema: "Cinema",
                         lunch: "Pranzo", coffee: "Caffè", supermarket: "Esselunga",
                         taxi: "Taxi", delivery: "Just Eat", gym: "Palestra",
                         savingsTransfer: "Risparmi",
                         voiceDemoPhrase: "15 euro di benzina")
        case "uk":
            return .init(card: "Картка", cash: "Готівка", savings: "Заощадження USD", deposit: "Депозит",
                         loan: "Кредит", bank: "Банк", salary: "Зарплата", rent: "Оренда",
                         utilities: "Комуналка", pharmacy: "Аптека", cinema: "Кіно",
                         lunch: "Обід", coffee: "Кава", supermarket: "Сільпо",
                         taxi: "Uklon", delivery: "Glovo", gym: "Спортзал",
                         savingsTransfer: "Заощадження",
                         voiceDemoPhrase: "Витратив 250 гривень на продукти")
        case "ja":
            return .init(card: "カード", cash: "現金", savings: "外貨預金 USD", deposit: "定期預金",
                         loan: "ローン", bank: "銀行", salary: "給料", rent: "家賃",
                         utilities: "光熱費", pharmacy: "薬局", cinema: "映画",
                         lunch: "ランチ", coffee: "コーヒー", supermarket: "スーパー",
                         taxi: "タクシー", delivery: "Uber Eats", gym: "ジム",
                         savingsTransfer: "貯金",
                         voiceDemoPhrase: "コンビニで500円使った")
        case "ko":
            return .init(card: "카드", cash: "현금", savings: "외화예금 USD", deposit: "예금",
                         loan: "대출", bank: "은행", salary: "월급", rent: "월세",
                         utilities: "공과금", pharmacy: "약국", cinema: "영화",
                         lunch: "점심", coffee: "커피", supermarket: "이마트",
                         taxi: "택시", delivery: "배달의민족", gym: "헬스장",
                         savingsTransfer: "저축",
                         voiceDemoPhrase: "점심 12,000원 썼어")
        case "ru":
            return .init(card: "Карта", cash: "Наличные", savings: "Накопления USD", deposit: "Депозит",
                         loan: "Кредит", bank: "Банк", salary: "Зарплата", rent: "Аренда",
                         utilities: "Коммуналка", pharmacy: "Аптека", cinema: "Кино",
                         lunch: "Обед", coffee: "Кофе", supermarket: "Супермаркет",
                         taxi: "Такси", delivery: "Доставка", gym: "Спортзал",
                         savingsTransfer: "Накопления",
                         voiceDemoPhrase: "Потратил 5000 тенге на продукты")
        default:
            return .init(card: "Card", cash: "Cash", savings: "Savings USD", deposit: "Deposit",
                         loan: "Loan", bank: "Bank", salary: "Salary", rent: "Rent",
                         utilities: "Utilities", pharmacy: "Pharmacy", cinema: "Cinema",
                         lunch: "Lunch", coffee: "Coffee", supermarket: "Whole Foods",
                         taxi: "Uber", delivery: "DoorDash", gym: "Gym",
                         savingsTransfer: "Savings",
                         voiceDemoPhrase: "Spent 12 dollars on lunch")
        }
    }
}

#endif
