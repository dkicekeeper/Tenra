//
//  ECBCurrencyProvider.swift
//  Tenra
//
//  European Central Bank euro reference rates: about 30 currencies (USD, JPY, GBP, KRW, TRY,
//  BRL, CNY, …), published every working day around 16:00 CET. No tenge, rouble or hryvnia.
//  Used through `OfficialRatesProvider`, which puts the table into tenge, the store's pivot.
//
//  Endpoints:
//      Latest:     https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml
//      Historical: https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml (90 days)
//
//  Format: `<Cube time="YYYY-MM-DD"><Cube currency="USD" rate="1.0845"/>…</Cube>`, the rate in
//  units of the currency per 1 EUR. Inverted into convention A (`rates[X] = EUR per 1 X`).
//  No rates on weekends and TARGET holidays: a date takes the last working day on or before it.
//

import Foundation
import os

nonisolated final class ECBCurrencyProvider: CurrencyRateProvider {
    let name = "ecb"

    private let urlSession: URLSession
    private static let logger = Logger(subsystem: "Tenra", category: "ECBCurrencyProvider")
    static let dailyURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!
    static let historyURL = URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist-90d.xml")!
    /// How far back the 90-day file is asked for, with a margin.
    static let historyDays = 85

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchRates(on date: Date?) async throws -> ExchangeRates {
        let historical = date.flatMap { Calendar.current.isDateInToday($0) ? nil : $0 }
        if let historical, historical < Date().addingTimeInterval(-Double(Self.historyDays) * 86_400) {
            throw CurrencyProviderError.rateNotFound
        }
        let data: Data
        do {
            let (body, response) = try await urlSession.data(from: historical == nil ? Self.dailyURL : Self.historyURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                Self.logger.debug("ecb non-2xx: \(http.statusCode, privacy: .public)")
                throw CurrencyProviderError.invalidResponse
            }
            data = body
        } catch let error as CurrencyProviderError {
            throw error
        } catch {
            throw CurrencyProviderError.networkError(error)
        }
        return try Self.parse(data: data, on: historical)
    }

    /// The table of `date` (the latest one when nil), or of the last working day before it.
    static func parse(data: Data, on date: Date?) throws -> ExchangeRates {
        let parser = XMLParser(data: data)
        let delegate = ECBRateParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw CurrencyProviderError.parseError("ecb feed is not valid XML")
        }
        let wanted = date.map { CurrencyConverter.dateKey(for: $0) }
        guard let day = delegate.days.keys.filter({ key in wanted.map { key <= $0 } ?? true }).max(),
              let table = delegate.days[day],
              let dayDate = DateFormatters.rateDateFormatter.date(from: day) else {
            throw CurrencyProviderError.parseError("ecb feed has no rates on or before the date")
        }
        var rates: [String: Double] = [:]
        for (code, perEuro) in table where perEuro > 0 && code != "EUR" {
            rates[code] = 1.0 / perEuro
        }
        if rates.isEmpty {
            throw CurrencyProviderError.parseError("ecb feed contained no rates")
        }
        return ExchangeRates(pivot: "EUR", rates: rates, date: dayDate, providerName: "ecb")
    }
}

// MARK: - XML Parser

/// Collects every `<Cube time>` block of the feed: the daily file has one, the 90-day file
/// one per working day.
private nonisolated final class ECBRateParserDelegate: NSObject, XMLParserDelegate {
    /// "YYYY-MM-DD" → currency → units per 1 EUR.
    var days: [String: [String: Double]] = [:]
    private var day: String?

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "Cube" else { return }
        if let time = attributeDict["time"] {
            day = time
        } else if let day, let code = attributeDict["currency"], let raw = attributeDict["rate"], let rate = Double(raw) {
            days[day, default: [:]][code.uppercased()] = rate
        }
    }
}
