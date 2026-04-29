//
//  NationalBankKZProvider.swift
//  Tenra
//
//  Legacy fallback provider — National Bank of Kazakhstan RSS/XML feed.
//  Kept as the last-resort source for KZT-resident users in case both the
//  jsDelivr CDN and its Cloudflare mirror are unreachable.
//
//  Endpoint: https://nationalbank.kz/rss/get_rates.cfm?fdate=DD.MM.YYYY
//  Format:   RSS-like XML with <item><title>USD</title><description>442.5</description><quant>1</quant></item>
//  Pivot:    KZT (rates are quoted as "X KZT per 1 unit of currency").
//  Coverage: 8 currencies — USD, EUR, RUB, GBP, CNY, JPY, KGS, UZS.
//

import Foundation
import os

nonisolated final class NationalBankKZProvider: CurrencyRateProvider {
    let name = "nbk"

    private let urlSession: URLSession
    private static let logger = Logger(subsystem: "Tenra", category: "NationalBankKZProvider")
    private static let baseURL = "https://nationalbank.kz/rss/get_rates.cfm"

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func fetchRates(on date: Date?) async throws -> ExchangeRates {
        let target = date ?? Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"
        let dateString = dateFormatter.string(from: target)

        guard let url = URL(string: "\(Self.baseURL)?fdate=\(dateString)") else {
            throw CurrencyProviderError.invalidURL
        }

        do {
            let (data, response) = try await urlSession.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                Self.logger.debug("nbk non-2xx: \(http.statusCode, privacy: .public)")
                throw CurrencyProviderError.invalidResponse
            }

            let parser = XMLParser(data: data)
            let delegate = NBKRateParserDelegate()
            parser.delegate = delegate
            parser.parse()

            if delegate.rates.isEmpty {
                throw CurrencyProviderError.parseError("nbk feed contained no rates")
            }

            return ExchangeRates(
                pivot: "KZT",
                rates: delegate.rates,
                date: target,
                providerName: "nbk"
            )
        } catch let error as CurrencyProviderError {
            throw error
        } catch {
            throw CurrencyProviderError.networkError(error)
        }
    }
}

// MARK: - XML Parser

/// Parses NBK's RSS-style feed. `nonisolated` because XMLParser drives delegate
/// callbacks synchronously on whatever queue the parser was started on.
private nonisolated final class NBKRateParserDelegate: NSObject, XMLParserDelegate {
    var rates: [String: Double] = [:]
    private var currentElement = ""
    private var currentTitle = ""
    private var currentDescription = ""
    private var currentQuant = ""

    /// NBK feed currency codes (kept identical to the legacy converter for
    /// behavioural parity).
    private let currencyCodes: Set<String> = [
        "USD", "EUR", "RUB", "GBP", "CNY", "JPY", "KGS", "UZS"
    ]

    nonisolated func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
    }

    nonisolated func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }

        switch currentElement {
        case "title":       currentTitle += trimmed
        case "description": currentDescription += trimmed
        case "quant":       currentQuant += trimmed
        default: break
        }
    }

    nonisolated func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "item" {
            if !currentTitle.isEmpty && !currentDescription.isEmpty {
                let upperTitle = currentTitle.uppercased()
                for code in currencyCodes where upperTitle.contains(code) {
                    if let rate = Double(currentDescription.replacingOccurrences(of: ",", with: ".")),
                       let quant = Double(currentQuant.isEmpty ? "1" : currentQuant),
                       quant > 0 {
                        // Normalize: rate per 1 unit (e.g. UZS quant=100 → divide).
                        rates[code] = rate / quant
                    }
                    break
                }
            }
            currentTitle = ""
            currentDescription = ""
            currentQuant = ""
        }
        currentElement = ""
    }
}
