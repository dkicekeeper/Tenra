//
//  VoiceInputParser.swift
//  Tenra
//
//  Created on 2024
//

import Foundation

// MARK: - Recognized Entity

/// Represents a recognized entity in the transcribed text
struct RecognizedEntity {
    /// Type of entity
    enum EntityType {
        case amount
        case currency
        case category
        case subcategory
        case account
        case date
        case transactionType // income/expense keywords
    }

    /// Type of the recognized entity
    let type: EntityType

    /// Range of the entity in the original text
    let range: NSRange

    /// Extracted value
    let value: String

    /// Confidence level (0.0 - 1.0)
    let confidence: Double
}

class VoiceInputParser {
    // MARK: - Dynamic Data Sources (Weak References)

    /// Reference to CategoriesViewModel for live category data
    private weak var categoriesViewModel: CategoriesViewModel?

    /// Reference to AccountsViewModel for live account data
    private weak var accountsViewModel: AccountsViewModel?

    /// Reference to TransactionsViewModel for usage statistics
    private weak var transactionsViewModel: TransactionsViewModel?

    // MARK: - Computed Properties for Live Data

    /// Live categories from ViewModel
    private var liveCategories: [CustomCategory] {
        categoriesViewModel?.customCategories ?? []
    }

    /// Live subcategories from ViewModel
    private var liveSubcategories: [Subcategory] {
        categoriesViewModel?.subcategories ?? []
    }

    /// Live accounts from ViewModel
    private var liveAccounts: [Account] {
        accountsViewModel?.accounts ?? []
    }

    /// Cached smart default account — computed once per parse() call
    private var cachedDefaultAccount: Account?

    /// Live transactions for usage analysis
    private var liveTransactions: [Transaction] {
        transactionsViewModel?.allTransactions ?? []
    }

    /// Category keyword mapping for entity detection — cached to avoid re-allocation per call
    private lazy var categoryMap: [String: (category: String, subcategory: String?)] = [
            // Транспорт - сначала подкатегории
            "такси": ("Транспорт", "Такси"),
            "uber": ("Транспорт", "Такси"),
            "yandex": ("Транспорт", "Такси"),
            "яндекс": ("Транспорт", "Такси"),
            "бензин": ("Транспорт", "Бензин"),
            "заправка": ("Транспорт", "Бензин"),
            "парковка": ("Транспорт", "Парковка"),
            "автобус": ("Транспорт", nil),
            "метро": ("Транспорт", nil),
            "проезд": ("Транспорт", nil),
            "транспорт": ("Транспорт", nil),

            // Еда - синонимы
            "кафе": ("Еда", nil),
            "кофе": ("Еда", "Кофе"),
            "ресторан": ("Еда", nil),
            "обед": ("Еда", nil),
            "ужин": ("Еда", nil),
            "завтрак": ("Еда", nil),
            "еда": ("Еда", nil),
            "столовая": ("Еда", nil),
            "доставка": ("Еда", "Доставка"),
            "еда доставка": ("Еда", "Доставка"),

            // Продукты
            "продукты": ("Продукты", nil),
            "магазин": ("Покупки", nil),
            "супермаркет": ("Продукты", nil),
            "гипермаркет": ("Продукты", nil),

            // Покупки
            "покупка": ("Покупки", nil),
            "шопинг": ("Покупки", nil),
            "одежда": ("Покупки", "Одежда"),
            "обувь": ("Покупки", "Одежда"),

            // Развлечения
            "кино": ("Развлечения", nil),
            "театр": ("Развлечения", nil),
            "концерт": ("Развлечения", nil),
            "развлечения": ("Развлечения", nil),

            // Здоровье
            "аптека": ("Здоровье", "Аптека"),
            "лекарство": ("Здоровье", "Аптека"),
            "врач": ("Здоровье", "Врач"),
            "больница": ("Здоровье", "Врач"),
            "стоматолог": ("Здоровье", "Стоматолог"),

            // Коммунальные
            "коммунальные": ("Коммунальные", nil),
            "квартплата": ("Коммунальные", nil),
            "электричество": ("Коммунальные", "Электричество"),
            "вода": ("Коммунальные", "Вода"),
            "газ": ("Коммунальные", "Газ"),
            "интернет": ("Коммунальные", "Интернет"),
            "телефон": ("Коммунальные", "Телефон"),

            // Образование
            "образование": ("Образование", nil),
            "школа": ("Образование", nil),
            "университет": ("Образование", nil),
            "курсы": ("Образование", nil),

            // Зарплата (доход)
            "зарплата": ("Зарплата", nil),
            "зарплату": ("Зарплата", nil),
            "оклад": ("Зарплата", nil),
            "премия": ("Зарплата", nil),

            // Другое
            "услуги": ("Услуги", nil),
            "ремонт": ("Услуги", nil)
        ]

    /// Income keywords for entity detection — cached
    private lazy var incomeKeywords: [String] =
        ["пришло", "пришел", "пришла", "получил", "получила", "получил", "зачисление", "доход", "зарплата"]

    /// Expense keywords for entity detection — cached
    private lazy var expenseKeywords: [String] =
        ["потратил", "потратила", "купил", "купила", "оплатил", "оплатила", "расход", "списали"]

    // MARK: - Pre-compiled регулярные выражения для производительности

    private let amountRegexes: [NSRegularExpression] = {
        let patterns = [
            // Число с валютой перед числом
            #"(?:тенге|тг|₸|доллар|долларов|\$|usd|евро|eur|€|рубл|rub|₽)\s*(\d{1,3}(?:\s*\d{3})*(?:[.,]\d{1,2})?)"#,
            // Число с валютой после числа
            #"(\d{1,3}(?:\s*\d{3})*(?:[.,]\d{1,2})?)\s*(?:тенге|тг|₸|доллар|долларов|\$|usd|евро|eur|€|рубл|rub|₽)"#,
            // Просто число (ищем самое большое число)
            #"\b(\d{1,3}(?:\s*\d{3})*(?:[.,]\d{1,2})?)\b"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    private let accountPatternRegexes: [NSRegularExpression] = {
        let patterns = [
            #"со\s+счета\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"со\s+счёта\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"с\s+карты\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"с\s+([^,\s]+(?:\s+[^,\s]+)*)\s+счета"#,
            #"с\s+([^,\s]+(?:\s+[^,\s]+)*)\s+счёта"#,
            #"карта\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"счет\s+([^,\s]+(?:\s+[^,\s]+)*)"#,
            #"счёт\s+([^,\s]+(?:\s+[^,\s]+)*)"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()

    // Словарь замен для нормализации
    private let textReplacements: [String: String] = [
        // Варианты "со счета"
        "со счёта": "со счета",
        "с счета": "со счета",
        "с счёта": "со счета",
        // Варианты валюты
        "тэг": "тг",
        "тенга": "тг",
        "тенг": "тг",
        // Бренды/счета
        "каспи": "kaspi",
        "каспи банк": "kaspi",
        "kaspi bank": "kaspi",
        "халик": "halyk",
        "халик банк": "halyk",
        "halyk bank": "halyk",
        "алатау": "alatau",
        "алатау сити": "alatau",
        "alatau city": "alatau",
        "хом кредит": "home credit",
        "хомкредит": "home credit",
        "home credit bank": "home credit",
        "жусан": "jusan",
        "jusan bank": "jusan"
    ]
    
    // Алиасы для счетов
    private let accountAliases: [String: [String]] = [
        "kaspi": ["каспи", "kaspi", "каспи банк", "kaspi bank", "каспи карта"],
        "halyk": ["halyk", "халик", "halyk bank", "халик банк", "халик карта"],
        "alatau": ["alatau", "алатау", "alatau city", "алатау сити", "алатау карта"],
        "home credit": ["home credit", "хом кредит", "хомкредит", "home credit bank"],
        "jusan": ["jusan", "жусан", "jusan bank", "жусан банк"],
        "gold": ["gold", "голд", "gold card", "голд карта"]
    ]
    
    // Стоп-слова для поиска счета
    private let stopWords: Set<String> = ["с", "со", "счет", "счёта", "счета", "карта", "карты", "банк", "банка"]
    
    // Словарь для распознавания чисел словами
    private let numberWords: [String: Int] = [
        "ноль": 0, "нуль": 0,
        "один": 1, "одна": 1, "одно": 1,
        "два": 2, "две": 2,
        "три": 3,
        "четыре": 4,
        "пять": 5,
        "шесть": 6,
        "семь": 7,
        "восемь": 8,
        "девять": 9,
        "десять": 10,
        "одиннадцать": 11,
        "двенадцать": 12,
        "тринадцать": 13,
        "четырнадцать": 14,
        "пятнадцать": 15,
        "шестнадцать": 16,
        "семнадцать": 17,
        "восемнадцать": 18,
        "девятнадцать": 19,
        "двадцать": 20,
        "тридцать": 30,
        "сорок": 40,
        "пятьдесят": 50,
        "шестьдесят": 60,
        "семьдесят": 70,
        "восемьдесят": 80,
        "девяносто": 90,
        "сто": 100,
        "двести": 200,
        "триста": 300,
        "четыреста": 400,
        "пятьсот": 500,
        "шестьсот": 600,
        "семьсот": 700,
        "восемьсот": 800,
        "девятьсот": 900,
        "тысяча": 1000, "тысячи": 1000, "тысяч": 1000
    ]
    
    // MARK: - Initialization

    /// Initializes parser with live references to ViewModels
    /// - Parameters:
    ///   - categoriesViewModel: ViewModel managing categories and subcategories
    ///   - accountsViewModel: ViewModel managing accounts
    ///   - transactionsViewModel: ViewModel managing transactions (for smart defaults)
    init(
        categoriesViewModel: CategoriesViewModel,
        accountsViewModel: AccountsViewModel,
        transactionsViewModel: TransactionsViewModel
    ) {
        self.categoriesViewModel = categoriesViewModel
        self.accountsViewModel = accountsViewModel
        self.transactionsViewModel = transactionsViewModel
    }
    
    func parse(_ text: String) -> ParsedOperation {
        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif

        let normalizedText = normalizeText(text)

        // Compute default account once per parse() — avoids iterating all transactions multiple times
        cachedDefaultAccount = getSmartDefaultAccount()

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif

        var operation = ParsedOperation(note: text)
        
        // 1. Определяем дату
        operation.date = parseDate(from: normalizedText)
        
        // 2. Определяем тип операции
        operation.type = parseType(from: normalizedText)
        
        // 3. Извлекаем сумму
        operation.amount = parseAmount(from: normalizedText)
        
        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            if operation.amount != nil {
            } else {
            }
        }
        #endif

        // 4. Извлекаем валюту
        operation.currencyCode = parseCurrency(from: normalizedText)

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            if operation.currencyCode != nil {
            }
        }
        #endif

        // 5. Ищем счет
        let accountResult = findAccount(from: normalizedText)
        operation.accountId = accountResult.accountId

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            if let accountId = accountResult.accountId,
               let _ = liveAccounts.first(where: { $0.id == accountId }) {
                _ = accountId  // Debug log placeholder
            }
        }
        #endif

        // 6. Определяем категорию и подкатегории
        let (category, subcats) = parseCategory(from: normalizedText)
        operation.categoryName = category
        operation.subcategoryNames = subcats

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            _ = category ?? ""  // Debug log placeholder
        }
        #endif
        
        // Если валюта не найдена, используем валюту найденного счета или счета по умолчанию
        if operation.currencyCode == nil {
            if let accountId = operation.accountId,
               let account = liveAccounts.first(where: { $0.id == accountId }) {
                operation.currencyCode = account.currency
            } else if let cachedDefaultAccount = cachedDefaultAccount {
                operation.currencyCode = cachedDefaultAccount.currency
            } else {
                operation.currencyCode = "KZT" // По умолчанию тенге
            }
        }
        
        // Если счет не найден, используем счет по умолчанию
        if operation.accountId == nil {
            operation.accountId = cachedDefaultAccount?.id
        }
        
        return operation
    }
    
    // MARK: - Private Methods
    
    private func normalizeText(_ text: String) -> String {
        var normalized = text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Применяем замены
        for (from, to) in textReplacements {
            normalized = normalized.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }
        
        // Collapse spaces (убираем множественные пробелы)
        normalized = normalized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 1. Парсинг даты
    private func parseDate(from text: String) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        if text.contains("сегодня") {
            return today
        } else if text.contains("вчера") {
            return calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }
        
        return today
    }
    
    // 2. Парсинг типа операции
    private func parseType(from text: String) -> TransactionType {
        let expenseKeywords = [
            "потратил", "потратила", "потратили", "потратило",
            "заплатил", "заплатила", "заплатили", "заплатило",
            "купил", "купила", "купили", "купило",
            "расход", "расходы",
            "оплатил", "оплатила", "оплатили",
            "списал", "списала", "списали",
            "покупка", "покупки"
        ]
        let incomeKeywords = [
            "получил", "получила", "получили", "получило",
            "пришло", "пришла", "пришли",
            "заработал", "заработала", "заработали",
            "доход", "доходы",
            "пополнил", "пополнила", "пополнили",
            "пополнение", "пополнения",
            "начислил", "начислила", "начислили",
            "зарплата", "зарплату", "зарплаты",
            "оклад", "премия", "премию"
        ]
        
        for keyword in expenseKeywords {
            if text.contains(keyword) {
                return .expense
            }
        }
        
        for keyword in incomeKeywords {
            if text.contains(keyword) {
                return .income
            }
        }
        
        return .expense // По умолчанию расход
    }
    
    // 3. Парсинг суммы (с поддержкой слов)
    private func parseAmount(from text: String) -> Decimal? {
        // Структура для хранения найденных сумм с приоритетом
        struct AmountMatch {
            let amount: Decimal
            let priority: Int  // 0 = с валютой (высший), 1 = без валюты (низший)
            let position: Int  // Позиция в тексте для разрешения конфликтов
        }

        var foundAmounts: [AmountMatch] = []

        // Используем pre-compiled regex для производительности
        for (index, regex) in amountRegexes.enumerated() {
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))
            for match in matches {
                if match.numberOfRanges > 1,
                   let range = Range(match.range(at: 1), in: text) {
                    let amountString = String(text[range])
                        .replacingOccurrences(of: ",", with: ".")
                        .replacingOccurrences(of: " ", with: "") // Убираем пробелы в числах типа "10 000"
                        .trimmingCharacters(in: .whitespaces)

                    if let amount = Decimal(string: amountString) {
                        // Приоритет: паттерны с валютой (0-1) имеют больший приоритет, чем просто числа (2)
                        let priority = index <= 1 ? 0 : 1
                        let position = match.range(at: 1).location

                        // Фильтруем явно неправильные суммы (например, годы)
                        if amount >= VoiceInputConstants.minAmountValue && amount <= VoiceInputConstants.maxAmountValue {
                            // Годы обычно 2000-2099 и не имеют валюты
                            let looksLikeYear = amount >= 1900 && amount <= 2100 && priority == 1
                            if !looksLikeYear {
                                foundAmounts.append(AmountMatch(amount: amount, priority: priority, position: position))
                            }
                        }
                    }
                }
            }
        }

        // Сортируем: сначала по приоритету (меньше = лучше), потом по сумме (больше = лучше)
        foundAmounts.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }
            return lhs.amount > rhs.amount
        }

        // Берем лучший результат
        if let bestMatch = foundAmounts.first {
            let rounded = (bestMatch.amount as NSDecimalNumber).rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .plain,
                scale: 2,
                raiseOnExactness: false,
                raiseOnOverflow: false,
                raiseOnUnderflow: false,
                raiseOnDivideByZero: false
            ))

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif

            return rounded as Decimal
        }

        // Если не нашли через regex, пытаемся распознать словами
        return parseAmountFromWords(text)
    }
    
    // Парсинг суммы словами (до 9999)
    private func parseAmountFromWords(_ text: String) -> Decimal? {
        let words = text.components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
        
        var result = 0
        var currentNumber = 0
        var hasThousand = false
        
        for word in words {
            let lowercased = word.lowercased()
            
            if let number = numberWords[lowercased] {
                if number == 1000 {
                    if currentNumber > 0 {
                        result += currentNumber * 1000
                        currentNumber = 0
                    } else {
                        result += 1000
                    }
                    hasThousand = true
                } else if number >= 100 {
                    if currentNumber > 0 {
                        result += currentNumber
                    }
                    currentNumber = number
                } else if number >= 10 {
                    if currentNumber >= 100 {
                        currentNumber += number
                    } else {
                        if currentNumber > 0 {
                            result += currentNumber
                        }
                        currentNumber = number
                    }
                } else {
                    if currentNumber >= 10 {
                        currentNumber += number
                    } else {
                        currentNumber = currentNumber * 10 + number
                    }
                }
            } else if lowercased == "тысяч" || lowercased == "тысячи" || lowercased == "тысяча" {
                if currentNumber > 0 {
                    result += currentNumber * 1000
                    currentNumber = 0
                } else if result == 0 {
                    result = 1000
                }
                hasThousand = true
            }
        }
        
        if currentNumber > 0 {
            if hasThousand {
                result += currentNumber
            } else {
                result += currentNumber
            }
        }
        
        if result > 0 && result <= VoiceInputConstants.maxWordNumberValue {
            return Decimal(result)
        }

        return nil
    }
    
    // 4. Парсинг валюты
    private func parseCurrency(from text: String) -> String? {
        let currencyMap: [String: String] = [
            "тенге": "KZT",
            "тг": "KZT",
            "₸": "KZT",
            "доллар": "USD",
            "долларов": "USD",
            "usd": "USD",
            "$": "USD",
            "евро": "EUR",
            "eur": "EUR",
            "€": "EUR",
            "рубл": "RUB",
            "rub": "RUB"
        ]
        
        for (keyword, code) in currencyMap {
            if text.contains(keyword) {
                return code
            }
        }
        
        return nil
    }
    
    // Результат поиска счета
    private struct AccountSearchResult {
        let accountId: String?
        let reason: String
    }
    
    // 5. Поиск счета по тексту (с токенизацией и скорингом)
    private func findAccount(from text: String) -> AccountSearchResult {
        var accountName: String?

        // Используем pre-compiled regex для производительности
        for regex in accountPatternRegexes {
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text) {
                accountName = String(text[range]).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        
        // Токенизация текста (убираем стоп-слова)
        let textTokens = tokenize(text)
        
        // Скоринг счетов
        var accountScores: [(Account, Int, String)] = [] // (account, score, reason)

        for account in liveAccounts {
            let normalizedAccountName = normalizeText(account.name)
            let accountTokens = tokenize(normalizedAccountName)
            
            var score = 0
            var reason = ""
            
            // Проверяем алиасы
            for (key, aliases) in accountAliases {
                if normalizedAccountName.contains(key) {
                    for alias in aliases {
                        if text.contains(alias) {
                            score += VoiceInputConstants.accountAliasMatchScore
                            reason = "Найден по алиасу '\(alias)'"
                            break
                        }
                    }
                }
            }

            // Точное совпадение имени
            if text.contains(normalizedAccountName) {
                score += VoiceInputConstants.accountExactMatchScore
                if reason.isEmpty {
                    reason = "Точное совпадение имени"
                }
            }

            // Совпадение токенов
            let matchingTokens = accountTokens.filter { token in
                textTokens.contains(token) && !stopWords.contains(token)
            }
            if !matchingTokens.isEmpty {
                score += matchingTokens.count * VoiceInputConstants.accountTokenMatchScore
                if reason.isEmpty {
                    reason = "Совпадение токенов: \(matchingTokens.joined(separator: ", "))"
                }
            }

            // Если нашли по паттерну
            if let accountName = accountName, normalizedAccountName.contains(normalizeText(accountName)) {
                score += VoiceInputConstants.accountPatternMatchScore
                reason = "Найден по паттерну: '\(accountName)'"
            }
            
            if score > 0 {
                accountScores.append((account, score, reason))
            }
        }
        
        // Сортируем по скору
        accountScores.sort { $0.1 > $1.1 }
        
        // Если есть несколько кандидатов с близким скором, возвращаем nil для выбора на confirm
        if accountScores.count >= 2 {
            let bestScore = accountScores[0].1
            let secondScore = accountScores[1].1
            if bestScore - secondScore < VoiceInputConstants.accountScoreAmbiguityThreshold {
                return AccountSearchResult(
                    accountId: nil,
                    reason: "Несколько кандидатов с близким скором: \(accountScores[0].0.name) (\(bestScore)) vs \(accountScores[1].0.name) (\(secondScore))"
                )
            }
        }
        
        if let bestMatch = accountScores.first {
            return AccountSearchResult(accountId: bestMatch.0.id, reason: bestMatch.2)
        }
        
        return AccountSearchResult(accountId: nil, reason: "Счет не найден")
    }
    
    // Токенизация текста (удаление стоп-слов)
    private func tokenize(_ text: String) -> [String] {
        return text.components(separatedBy: CharacterSet.whitespaces.union(.punctuationCharacters))
            .map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !stopWords.contains($0) }
    }
    
    // 6. Парсинг категории и подкатегорий (сначала подкатегории, потом категории)
    private func parseCategory(from text: String) -> (category: String?, subcategories: [String]) {
        // Сначала ищем подкатегории, потом категории
        var foundSubcategories: [String] = []
        var foundCategory: String?
        
        for (keyword, (category, subcategory)) in categoryMap {
            if text.contains(keyword) {
                // Сначала проверяем подкатегорию
                if let subcategory = subcategory {
                    let matchingSubcategory = liveSubcategories.first { normalizeText($0.name) == normalizeText(subcategory) }
                    if let matchingSubcategory = matchingSubcategory {
                        foundSubcategories.append(matchingSubcategory.name)
                    }
                }
                
                // Затем категорию
                if foundCategory == nil {
                    let matchingCategory = liveCategories.first { normalizeText($0.name) == normalizeText(category) }
                    foundCategory = matchingCategory?.name ?? category
                }
                
                // Если нашли и подкатегорию и категорию, можно выйти
                if !foundSubcategories.isEmpty && foundCategory != nil {
                    break
                }
            }
        }
        
        // Если не нашли, возвращаем "Другое"
        if foundCategory == nil {
            let otherName = String(localized: "category.other")
            foundCategory = liveCategories.first { normalizeText($0.name) == normalizeText(otherName) }?.name ?? otherName
        }
        
        return (foundCategory, foundSubcategories)
    }

    // MARK: - Live Entity Recognition

    /// Parse entities from text in real-time for UI highlighting
    /// - Parameter text: Text to parse
    /// - Returns: Array of recognized entities with positions and confidence
    func parseEntitiesLive(from text: String) -> [RecognizedEntity] {
        var entities: [RecognizedEntity] = []
        let nsText = text as NSString

        // 1. Detect Amount
        if let amountEntity = detectAmountEntity(in: text, nsText: nsText) {
            entities.append(amountEntity)
        }

        // 2. Detect Currency
        if let currencyEntity = detectCurrencyEntity(in: text, nsText: nsText) {
            entities.append(currencyEntity)
        }

        // 3. Detect Category
        if let categoryEntity = detectCategoryEntity(in: text, nsText: nsText) {
            entities.append(categoryEntity)
        }

        // 4. Detect Account
        if let accountEntity = detectAccountEntity(in: text, nsText: nsText) {
            entities.append(accountEntity)
        }

        // 5. Detect Transaction Type (income/expense keywords)
        if let typeEntity = detectTransactionTypeEntity(in: text, nsText: nsText) {
            entities.append(typeEntity)
        }

        return entities
    }

    // MARK: - Entity Detection Methods

    private func detectAmountEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        // Try to find amount with currency first (high confidence)
        for regex in amountRegexes.prefix(2) { // First 2 patterns have currency
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let matchedText = nsText.substring(with: match.range)
                let hasCurrency = matchedText.lowercased().contains("тенге") ||
                                 matchedText.lowercased().contains("тг") ||
                                 matchedText.contains("₸")

                return RecognizedEntity(
                    type: .amount,
                    range: match.range,
                    value: matchedText,
                    confidence: hasCurrency ? 0.9 : 0.7
                )
            }
        }

        return nil
    }

    private func detectCurrencyEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        let currencyPattern = #"(тенге|тг|₸|доллар|евро|рубл)"#
        guard let regex = try? NSRegularExpression(pattern: currencyPattern, options: .caseInsensitive) else {
            return nil
        }

        if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
            return RecognizedEntity(
                type: .currency,
                range: match.range,
                value: nsText.substring(with: match.range),
                confidence: 0.95
            )
        }

        return nil
    }

    private func detectCategoryEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        let normalizedText = normalizeText(text)

        // Check categoryMap for known keywords
        for (keyword, categoryInfo) in categoryMap {
            if normalizedText.contains(keyword) {
                // Find position of keyword
                if let range = text.lowercased().range(of: keyword) {
                    let nsRange = NSRange(range, in: text)
                    return RecognizedEntity(
                        type: .category,
                        range: nsRange,
                        value: categoryInfo.category,
                        confidence: 0.8
                    )
                }
            }
        }

        return nil
    }

    private func detectAccountEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        // Try account patterns
        for regex in accountPatternRegexes {
            if let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) {
                let matchedText = nsText.substring(with: match.range)
                return RecognizedEntity(
                    type: .account,
                    range: match.range,
                    value: matchedText,
                    confidence: 0.75
                )
            }
        }

        return nil
    }

    private func detectTransactionTypeEntity(in text: String, nsText: NSString) -> RecognizedEntity? {
        let normalizedText = normalizeText(text)

        // Check for income keywords
        for keyword in incomeKeywords {
            if normalizedText.contains(keyword) {
                if let range = text.lowercased().range(of: keyword) {
                    let nsRange = NSRange(range, in: text)
                    return RecognizedEntity(
                        type: .transactionType,
                        range: nsRange,
                        value: "income",
                        confidence: 0.85
                    )
                }
            }
        }

        // Check for expense keywords
        for keyword in expenseKeywords {
            if normalizedText.contains(keyword) {
                if let range = text.lowercased().range(of: keyword) {
                    let nsRange = NSRange(range, in: text)
                    return RecognizedEntity(
                        type: .transactionType,
                        range: nsRange,
                        value: "expense",
                        confidence: 0.85
                    )
                }
            }
        }

        return nil
    }

    // MARK: - Smart Default Account Selection

    /// Get smart default account based on usage statistics
    /// - Returns: Account with highest usage score, or first account as fallback
    private func getSmartDefaultAccount() -> Account? {
        guard !liveAccounts.isEmpty else { return nil }

        // If no transactions, use first account
        guard !liveTransactions.isEmpty else {
            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
            return liveAccounts.first
        }

        // Use AccountUsageTracker to get smart default
        let tracker = AccountUsageTracker(transactions: liveTransactions, accounts: liveAccounts)
        let smartDefault = tracker.getSmartDefaultAccount()

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
            if smartDefault != nil {
            }
        }
        #endif

        return smartDefault
    }
}
