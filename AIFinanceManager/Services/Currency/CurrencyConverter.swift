//
//  CurrencyConverter.swift
//  AIFinanceManager
//
//  PURPOSE: Live / historical exchange-rate fetching from the National Bank of Kazakhstan.
//
//  RESPONSIBILITY SPLIT (do NOT confuse these two currency utilities):
//  ─────────────────────────────────────────────────────────────────────
//  CurrencyConverter  (THIS FILE)
//      • Async network requests to https://nationalbank.kz/rss/get_rates.cfm
//      • XML parsing of rate feed. 24-hour in-process cache for current rates.
//      • Separate historical rates cache keyed by date string.
//      • Used by: BalanceCalculationEngine for cross-currency account balance totals.
//
//  TransactionCurrencyService  (Services/Utilities/TransactionCurrencyService.swift)
//      • NO network calls. Reads the `convertedAmount` already stored on Transaction.
//      • O(1) lookup via in-memory cache, O(N) precompute pass.
//      • Used by: display layer (TransactionQueryService, InsightsService).
//  ─────────────────────────────────────────────────────────────────────
//
//  NOTE: `convertSync` only works after at least one successful async `getExchangeRate` call
//  has populated `cachedRates`. Do NOT call it on first launch without awaiting async load first.

import Foundation

nonisolated class CurrencyConverter: @unchecked Sendable {
    private static let baseURL = "https://nationalbank.kz/rss/get_rates.cfm"
    private static var cachedRates: [String: Double] = [:]
    private static var cacheDate: Date?
    private static let cacheValidityHours: TimeInterval = 24 * 60 * 60 // 24 часа

    // Кэш исторических курсов: [дата: [валюта: курс]]
    private static var historicalRatesCache: [String: [String: Double]] = [:]

    // Получить курс валюты к тенге на конкретную дату
    static func getExchangeRate(for currency: String, on date: Date? = nil) async -> Double? {
        // KZT всегда равен 1
        if currency == "KZT" {
            return 1.0
        }

        let targetDate = date ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let dateString = dateFormatter.string(from: targetDate)

        // Для текущей даты используем обычный кэш
        if date == nil || Calendar.current.isDateInToday(targetDate) {
            // Проверяем кэш
            if let cachedDate = cacheDate,
               Date().timeIntervalSince(cachedDate) < cacheValidityHours,
               let cachedRate = cachedRates[currency] {
                return cachedRate
            }
        } else {
            // Для исторической даты проверяем исторический кэш
            if let historicalRates = historicalRatesCache[dateString],
               let rate = historicalRates[currency] {
                return rate
            }
        }

        // Загружаем курсы с Нацбанка РК
        // API требует параметр fdate в формате DD.MM.YYYY
        guard let url = URL(string: "\(baseURL)?fdate=\(dateString)") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            // Парсим XML
            let parser = XMLParser(data: data)
            let delegate = ExchangeRateParserDelegate()
            parser.delegate = delegate
            parser.parse()

            // Обновляем соответствующий кэш
            if date == nil || Calendar.current.isDateInToday(targetDate) {
                cachedRates = delegate.rates
                cacheDate = Date()
            } else {
                historicalRatesCache[dateString] = delegate.rates
            }

            return delegate.rates[currency]
        } catch {
            // Для исторических данных: если не удалось загрузить, возвращаем nil
            // Для текущих данных: возвращаем кэшированное значение, если есть
            if date == nil || Calendar.current.isDateInToday(targetDate) {
                return cachedRates[currency]
            }
            return nil
        }
    }
    
    // Конвертировать сумму из одной валюты в другую на конкретную дату
    static func convert(amount: Double, from: String, to: String, on date: Date? = nil) async -> Double? {
        // Если валюты одинаковые, возвращаем сумму без изменений
        if from == to {
            return amount
        }

        // Получаем курсы обеих валют к тенге на указанную дату
        guard let fromRate = await getExchangeRate(for: from, on: date),
              let toRate = await getExchangeRate(for: to, on: date) else {
            return nil
        }

        // Конвертируем через тенге
        // Курсы показывают: 1 валюта = X KZT
        // Шаг 1: Конвертируем from в KZT: amount * fromRate
        // Шаг 2: Конвертируем KZT в to: amountInKZT / toRate
        // Итоговая формула: amount * fromRate / toRate
        let converted = amount * fromRate / toRate
        return converted
    }
    
    // Получить все доступные курсы
    static func getAllRates() async -> [String: Double] {
        _ = await getExchangeRate(for: "USD") // Загружаем курсы
        return cachedRates
    }
    
    // Синхронная конвертация через кэш (без сетевых запросов)
    // Используется в recalculateAccountBalances() для конвертации валют переводов
    static func convertSync(amount: Double, from: String, to: String) -> Double? {
        // Если валюты одинаковые, возвращаем сумму без изменений
        if from == to {
            return amount
        }

        // KZT всегда равен 1
        // Получаем курсы, проверяя наличие в кэше
        let fromRate: Double?
        if from == "KZT" {
            fromRate = 1.0
        } else {
            fromRate = cachedRates[from]
            // Если курса нет в кэше, возвращаем nil (нельзя конвертировать)
            if fromRate == nil {
                return nil
            }
        }

        let toRate: Double?
        if to == "KZT" {
            toRate = 1.0
        } else {
            toRate = cachedRates[to]
            // Если курса нет в кэше, возвращаем nil (нельзя конвертировать)
            if toRate == nil {
                return nil
            }
        }

        // Убеждаемся, что оба курса получены
        guard let fromRateValue = fromRate, let toRateValue = toRate else {
            return nil
        }

        // Конвертируем через тенге
        // Курсы показывают: 1 валюта = X KZT
        // Шаг 1: Конвертируем from в KZT: amount * fromRate
        // Шаг 2: Конвертируем KZT в to: amountInKZT / toRate
        // Итоговая формула: amount * fromRate / toRate
        let converted = amount * fromRateValue / toRateValue
        return converted
    }
}

// MARK: - XML Parser Delegate
private nonisolated class ExchangeRateParserDelegate: NSObject, XMLParserDelegate {
    var rates: [String: Double] = [:]
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentQuant = ""

    nonisolated func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        switch currentElement {
        case "title":
            currentTitle += trimmed
        case "description":
            currentDescription += trimmed
        case "quant":
            currentQuant += trimmed
        default:
            break
        }
    }

    nonisolated func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            // Парсим курс из title, description и quant
            // Формат: title содержит код валюты, description содержит курс, quant - количество единиц
            if !currentTitle.isEmpty && !currentDescription.isEmpty {
                // Ищем код валюты в title (например, "USD", "EUR")
                let currencyCodes = ["USD", "EUR", "RUB", "GBP", "CNY", "JPY", "KGS", "UZS"]
                for code in currencyCodes {
                    if currentTitle.uppercased().contains(code) {
                        if let rate = Double(currentDescription.replacingOccurrences(of: ",", with: ".")),
                           let quant = Double(currentQuant.isEmpty ? "1" : currentQuant) {
                            // Нормализуем курс: делим на количество единиц
                            // Например, для JPY (quant=1): rate = 3.23 / 1 = 3.23
                            // Для UZS (quant=100): rate = 4.21 / 100 = 0.0421 (за 1 UZS)
                            let normalizedRate = rate / quant
                            rates[code] = normalizedRate
                        }
                        break
                    }
                }
            }
            currentTitle = ""
            currentDescription = ""
            currentQuant = ""
        }
        currentElement = ""
    }
}
