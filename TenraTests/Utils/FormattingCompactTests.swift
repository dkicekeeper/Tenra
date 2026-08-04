//
//  FormattingCompactTests.swift
//  TenraTests
//
//  Pins `Formatting.formatCurrencyCompact` — the fallback `FormattedAmountText`
//  renders when the full amount does not fit its container.
//
//  The point of using the system's compact notation instead of a hand-rolled K/M
//  table is locale correctness: ja/ko group by 10 000 (万 / 억), and a "hundreds of
//  millions" currency is exactly where a hard-coded table would be wrong.
//

import Testing
import Foundation
@testable import Tenra

@Suite("Formatting.formatCurrencyCompact")
struct FormattingCompactTests {

    private func compact(
        _ amount: Double,
        _ localeID: String,
        currency: String = "KZT",
        digits: Int = 1
    ) -> String {
        Formatting.formatCurrencyCompact(
            amount,
            currency: currency,
            maxFractionDigits: digits,
            locale: Locale(identifier: localeID)
        )
    }

    // MARK: - Localized unit names

    @Test("English abbreviates with K / M")
    func english() {
        #expect(compact(1_234_567, "en_US").contains("M"))
        #expect(compact(12_000, "en_US").contains("K"))
    }

    @Test("Russian abbreviates with млн / тыс")
    func russian() {
        #expect(compact(1_234_567, "ru_RU").contains("млн"))
        #expect(compact(12_000, "ru_RU").contains("тыс"))
    }

    @Test("German abbreviates with Mio")
    func german() {
        #expect(compact(1_234_567, "de_DE").contains("Mio"))
    }

    @Test("Japanese and Korean group by 10 000, not 1 000")
    func cjkGrouping() {
        // 120 000 000 is 1.2億 / 1.2억 — a hard-coded "M" table would print 120M here.
        #expect(compact(120_000_000, "ja_JP").contains("億"))
        #expect(compact(120_000_000, "ko_KR").contains("억"))
    }

    // MARK: - Shape

    @Test("Currency symbol is appended, same as the full formatter")
    func carriesCurrencySymbol() {
        #expect(compact(1_234_567, "en_US", currency: "KZT").hasSuffix("₸"))
        #expect(compact(1_234_567, "en_US", currency: "USD").hasSuffix("$"))
    }

    @Test("maxFractionDigits: 0 drops the fraction")
    func zeroFractionDigits() {
        let oneDigit = compact(1_234_567, "en_US", digits: 1)
        let noDigits = compact(1_234_567, "en_US", digits: 0)
        #expect(oneDigit.contains("1.2"))
        #expect(!noDigits.contains("1.2"))
        #expect(noDigits.count < oneDigit.count)
    }

    @Test("Small amounts are left alone by the compact style")
    func smallAmountsUnchanged() {
        #expect(compact(999, "en_US").hasPrefix("999"))
    }

    // MARK: - Why FormattedAmountText guards the swap

    @Test("A compact string can be LONGER than the full one")
    func compactCanBeLonger() {
        // "10 тыс. ₸" vs "10 000 ₸" — this is why `FormattedAmountText.candidate(digits:)`
        // falls back to the full text instead of blindly offering the abbreviation.
        let full = Formatting.formatCurrencySmart(10_000, currency: "KZT")
        let short = compact(10_000, "ru_RU")
        #expect(short.count >= full.count)
    }
}
