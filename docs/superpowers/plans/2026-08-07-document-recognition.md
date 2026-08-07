# Document Recognition (Statements + Receipts) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-bank PDF parser with a bank-agnostic, on-device document recognition pipeline that handles both bank statements (PDF) and paper receipts (camera), using the iOS 26 Vision document APIs and Apple Intelligence, with zero third-party services and zero network calls.

**Architecture:** Three decoupled stages behind Sendable value types. **Acquisition** produces page images or a PDF text layer. **Extraction** turns pages into a `DocumentSnapshot` (tables as rectangular grids, paragraphs as lines, barcodes) via `Vision.RecognizeDocumentsRequest` on iOS 26, or via PDFKit real word coordinates when the PDF has a text layer. **Interpretation** turns a `DocumentSnapshot` into `ParsedTransaction` values. Interpretation is deterministic by default; Apple Intelligence (`FoundationModels`) is layered on top for *schema inference* on statements (which column is the date, which is the amount) and for *direct extraction* on receipts, and is always optional with a deterministic fallback.

**Tech Stack:** Swift 5 / Swift 6 patterns, SwiftUI, iOS 26 SDK. `Vision.RecognizeDocumentsRequest`, `Vision.DocumentObservation.Container.Table`, `FoundationModels` (`@Generable`, `@Guide`, `LanguageModelSession`, `SystemLanguageModel`), `VisionKit.VNDocumentCameraViewController`, `PDFKit`. swift-testing for tests.

## Global Constraints

- **iOS 26.0+ only.** Project already targets iOS 26.0. Every new API used here is iOS 26 or earlier. No `#available` fences are needed for `RecognizeDocumentsRequest`, `DocumentObservation`, `FoundationModels`, or `VNDocumentCameraViewController`.
- **No third-party dependencies. No network calls.** Everything runs on device.
- **FoundationModels is never a hard requirement.** `SystemLanguageModel.default.availability` can be `.unavailable(.deviceNotEligible)` (iPhone 14 and older), `.unavailable(.appleIntelligenceNotEnabled)`, or `.unavailable(.modelNotReady)`. Every path must produce a usable result without it.
- **Heavy work goes off MainActor.** Project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. Extraction and interpretation types must be declared `nonisolated` and operate on `Sendable` snapshot structs. See CLAUDE.md Red Flag #9 and `docs/concurrency.md`.
- **Money is never rendered without a canonical formatter.** UI must use `FormattedAmountText`, `InfoRow(... amount: currency:)`, or `Formatting.formatCurrencySmart(_:currency:)`. See CLAUDE.md Red Flag #7 and `docs/design-system.md` §6.
- **All new UI strings ship in 11 locales**: en, ru, de, es, fr, tr, pt-BR, it, uk, ja, ko. Add keys with `python3` using `io.open(encoding="utf-8")`, never `perl -CSD`. See CLAUDE.md Red Flag #13 and `docs/localization/README.md`.
- **No em dashes in any user-facing text** (UI strings, all locales). Use a comma, colon, or period.
- **Format specifiers**: if a translation reorders arguments it must use positional specifiers (`%1$@`, `%2$lld`) and must never mix positional and plain in one string. See CLAUDE.md Red Flag #14.
- **Xcode project uses `PBXFileSystemSynchronizedRootGroup`.** Creating or deleting `.swift` files needs no `project.pbxproj` edits.
- **Swift filenames must be unique within a target.** Do not reuse an existing filename in a different directory.
- **Amounts are `Double`** to match `Transaction.amount` in `Tenra/Models/Transaction.swift:101`.
- **The Import tab stays Pro-gated.** `OCRTab` in `Tenra/Views/Home/TabViews.swift:117` already gates on `premium.isPro`. Do not change the gate.

**Build command used throughout:**

```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```

**Test command used throughout:**

```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

Filter a single suite with `-only-testing:TenraTests/<TypeName>`. Method-level filtering silently runs zero tests.

---

## File Structure

**New files (Services):**

| File | Responsibility |
|---|---|
| `Tenra/Services/Import/DocumentSnapshot.swift` | `Sendable` value model of an extracted document: pages, tables as rectangular string grids, text lines, barcodes. The seam between extraction and interpretation, and the thing tests construct by hand. |
| `Tenra/Services/Import/DateTokenParser.swift` | Parses a date out of an arbitrary cell string across the formats real statements use. Returns canonical `yyyy-MM-dd`. |
| `Tenra/Services/Import/MoneyTokenParser.swift` | Parses an amount plus optional currency out of an arbitrary cell string. Handles thin/non-breaking spaces, comma and dot decimal separators, minus signs, parenthesised negatives, currency symbols and ISO codes. |
| `Tenra/Services/Import/VisionDocumentExtractor.swift` | `RecognizeDocumentsRequest` → `DocumentSnapshot`. Handles scanned PDFs and camera images. |
| `Tenra/Services/Import/PDFTextLayerExtractor.swift` | PDFKit text layer → `DocumentSnapshot` using real per-line character bounds, replacing the synthetic uniform word distribution. |
| `Tenra/Services/Import/ColumnRoleResolver.swift` | Maps table column indices to semantic roles (date, amount, currency, description, debit, credit) using header keywords and column content statistics. Deterministic, no ML. |
| `Tenra/Services/Import/StatementInterpreter.swift` | `DocumentSnapshot` + `ColumnRoles` → `[ParsedTransaction]`. Also owns `ParsedTransaction`, `ParsedStatement`, and the skipped-row diagnostics. |
| `Tenra/Services/Import/IntelligenceAvailability.swift` | Thin wrapper over `SystemLanguageModel.default.availability`, so the rest of the code and tests never touch `FoundationModels` directly. |
| `Tenra/Services/Import/IntelligentColumnRoleResolver.swift` | Apple Intelligence column-role inference. One small prompt per table, used only when the deterministic resolver is not confident. |
| `Tenra/Services/Import/ReceiptInterpreter.swift` | Receipt extraction: Apple Intelligence direct extraction with a deterministic fallback. Owns `ReceiptDraft`. |
| `Tenra/Services/Import/DocumentImportService.swift` | Orchestrator. Picks the extractor, runs interpretation off MainActor, returns `ImportOutcome`. Replaces the orchestration currently inlined in `PDFService`. |

**New files (Views):**

| File | Responsibility |
|---|---|
| `Tenra/Views/Import/DocumentScannerView.swift` | `UIViewControllerRepresentable` wrapper for `VNDocumentCameraViewController`. |
| `Tenra/Views/Import/ImportSourcePicker.swift` | Three-way source choice: PDF file, scan receipt, photo. |
| `Tenra/Views/Import/ImportDiagnosticsView.swift` | Shows recognized / skipped counts and the skipped rows, so silent data loss becomes visible. |

**Modified files:**

| File | Change |
|---|---|
| `Tenra/Services/Import/PDFService.swift:37-694` | Reduced to page rendering plus delegation to `DocumentImportService`. All table reconstruction heuristics deleted. |
| `Tenra/Views/Import/PDFImportCoordinator.swift:14-195` | Gains a source picker and the diagnostics sheet. |
| `Tenra/Views/Home/TabViews.swift:117-161` | `OCRTab` presents `ImportSourcePicker`. |
| `Tenra/Info.plist` | Adds `NSCameraUsageDescription`. |
| `Tenra/*.lproj/Localizable.strings` (11 files) | New keys. |

**Deleted at the end:**

| File | Reason |
|---|---|
| `Tenra/Services/Import/StatementTextParser.swift` | Replaced by `ColumnRoleResolver` + `StatementInterpreter`. Deleted only in Task 12, after parity. |

**New test files:** `TenraTests/Services/Import/DateTokenParserTests.swift`, `MoneyTokenParserTests.swift`, `ColumnRoleResolverTests.swift`, `StatementInterpreterTests.swift`, `ReceiptInterpreterTests.swift`.

---

### Task 1: DocumentSnapshot value model

The seam every later task depends on. It is a plain `Sendable` struct so tests can build documents by hand without Vision, a camera, or a PDF.

**Files:**
- Create: `Tenra/Services/Import/DocumentSnapshot.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `DocumentSnapshot`, `DocumentSnapshot.Page`, `DocumentSnapshot.Table`, `DocumentSnapshot.Barcode`, `DocumentSnapshot.allTables`, `DocumentSnapshot.allLines`, `DocumentSnapshot.Table.headerRow`, `DocumentSnapshot.Table.bodyRows`.

- [ ] **Step 1: Create the model file**

```swift
//
//  DocumentSnapshot.swift
//  Tenra
//
//  Sendable seam between document extraction (Vision / PDFKit) and
//  interpretation (statement / receipt parsing). Extraction produces one of
//  these; interpretation consumes only this. Tests build them by hand.
//

import Foundation

/// A fully extracted document, independent of how it was extracted.
struct DocumentSnapshot: Sendable, Equatable {

    /// A rectangular table. `rows` is always rectangular: every row has
    /// exactly `columnCount` entries, padded with "" where a cell is missing
    /// or spans. Cell text is already trimmed.
    struct Table: Sendable, Equatable {
        let rows: [[String]]
        let columnCount: Int

        init(rows: [[String]]) {
            let width = rows.map(\.count).max() ?? 0
            self.columnCount = width
            self.rows = rows.map { row in
                var padded = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                while padded.count < width { padded.append("") }
                return padded
            }
        }

        /// First row, by convention the header. `nil` for an empty table.
        var headerRow: [String]? { rows.first }

        /// Everything after the header row.
        var bodyRows: ArraySlice<[String]> { rows.dropFirst() }
    }

    struct Barcode: Sendable, Equatable {
        let payload: String
        /// Raw symbology identifier, e.g. "qr", "ean13". Free-form on purpose:
        /// interpretation only pattern-matches the payload.
        let symbology: String
    }

    struct Page: Sendable, Equatable {
        let index: Int
        let tables: [Table]
        /// Every text line on the page in reading order, table content included.
        /// This is the fallback when no table is detected.
        let lines: [String]
        let barcodes: [Barcode]
    }

    let pages: [Page]

    /// True when the document contained a machine-readable text layer, so no
    /// OCR ran. Used to decide whether to trust the text verbatim.
    let hadTextLayer: Bool

    var allTables: [Table] { pages.flatMap(\.tables) }
    var allLines: [String] { pages.flatMap(\.lines) }
    var allBarcodes: [Barcode] { pages.flatMap(\.barcodes) }

    /// Whole document as plain text, one line per line, pages separated by a
    /// blank line. Line breaks are preserved on purpose: the previous
    /// implementation joined OCR output with spaces and broke every
    /// line-oriented fallback downstream.
    var plainText: String {
        pages.map { $0.lines.joined(separator: "\n") }
            .joined(separator: "\n\n")
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output (no errors).

- [ ] **Step 3: Commit**

```bash
git add Tenra/Services/Import/DocumentSnapshot.swift
git commit -m "feat(import): add DocumentSnapshot value model as extraction/interpretation seam"
```

---

### Task 2: DateTokenParser

The current parser accepts exactly `DD.MM.YYYY` (`StatementTextParser.swift:484`). Every other bank format silently drops the row.

**Files:**
- Create: `Tenra/Services/Import/DateTokenParser.swift`
- Test: `TenraTests/Services/Import/DateTokenParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `DateTokenParser.parse(_ token: String) -> String?` returning canonical `"yyyy-MM-dd"`, and `DateTokenParser.looksLikeDate(_ token: String) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `TenraTests/Services/Import/DateTokenParserTests.swift`:

```swift
//
//  DateTokenParserTests.swift
//  TenraTests
//
//  Pins the statement date formats we accept. Every format here appeared in a
//  real bank statement; adding a bank means adding a case here first.
//

import Testing
@testable import Tenra

struct DateTokenParserTests {

    @Test("dotted day-first dates parse")
    func dottedDayFirst() {
        #expect(DateTokenParser.parse("08.01.2026") == "2026-01-08")
        #expect(DateTokenParser.parse("08.01.2026 17:19:46") == "2026-01-08")
        #expect(DateTokenParser.parse("8.1.2026") == "2026-01-08")
    }

    @Test("slashed and dashed dates parse")
    func slashedAndDashed() {
        #expect(DateTokenParser.parse("08/01/2026") == "2026-01-08")
        #expect(DateTokenParser.parse("2026-01-08") == "2026-01-08")
        #expect(DateTokenParser.parse("08-01-2026") == "2026-01-08")
    }

    @Test("two-digit years resolve into the 2000s")
    func twoDigitYear() {
        #expect(DateTokenParser.parse("08.01.26") == "2026-01-08")
    }

    @Test("unambiguous month-first dates parse day-second")
    func monthFirstDisambiguation() {
        // 13 cannot be a month, so this must be day-first.
        #expect(DateTokenParser.parse("13/01/2026") == "2026-01-13")
        // 31 cannot be a month either.
        #expect(DateTokenParser.parse("31.12.2025") == "2025-12-31")
    }

    @Test("invalid dates return nil rather than a wrong date")
    func invalidDates() {
        #expect(DateTokenParser.parse("") == nil)
        #expect(DateTokenParser.parse("Purchase") == nil)
        #expect(DateTokenParser.parse("2 500") == nil)
        #expect(DateTokenParser.parse("32.01.2026") == nil)
        #expect(DateTokenParser.parse("08.13.2026") == nil)
    }

    @Test("looksLikeDate agrees with parse")
    func looksLikeDateAgrees() {
        #expect(DateTokenParser.looksLikeDate("08.01.2026"))
        #expect(!DateTokenParser.looksLikeDate("YANDEX.GO"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/DateTokenParserTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: compile error, `cannot find 'DateTokenParser' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Tenra/Services/Import/DateTokenParser.swift`:

```swift
//
//  DateTokenParser.swift
//  Tenra
//
//  Parses a date out of an arbitrary statement cell. Deliberately regex +
//  arithmetic rather than DateFormatter: this runs once per cell over
//  thousands of cells, and DateFormatter.date(from:) costs ~13 µs per call
//  (see CLAUDE.md Red Flag #15 and Tenra/Utils/FastDateParser.swift).
//

import Foundation

nonisolated enum DateTokenParser {

    /// Matches d.m.y, d/m/y, d-m-y with 1-2 digit day and month, 2 or 4 digit year.
    private static let dayFirstPattern = /(\d{1,2})[.\/\-](\d{1,2})[.\/\-](\d{2,4})/

    /// Matches ISO yyyy-mm-dd.
    private static let isoPattern = /(\d{4})-(\d{1,2})-(\d{1,2})/

    /// Parses the first date found in `token`, returning canonical "yyyy-MM-dd".
    /// Returns nil when no valid calendar date is present.
    static func parse(_ token: String) -> String? {
        if let match = token.firstMatch(of: isoPattern) {
            let year = Int(match.1) ?? 0
            let month = Int(match.2) ?? 0
            let day = Int(match.3) ?? 0
            return canonical(year: year, month: month, day: day)
        }

        guard let match = token.firstMatch(of: dayFirstPattern) else { return nil }
        let first = Int(match.1) ?? 0
        let second = Int(match.2) ?? 0
        let year = normalizeYear(Int(match.3) ?? 0)

        // Day-first is the dominant convention in the statements we support
        // (EU, CIS, LATAM). Only fall back to month-first when day-first is
        // impossible, which happens for US-formatted MM/DD/YYYY where DD > 12.
        if let result = canonical(year: year, month: second, day: first) {
            return result
        }
        return canonical(year: year, month: first, day: second)
    }

    /// True when `token` contains a parseable date.
    static func looksLikeDate(_ token: String) -> Bool {
        parse(token) != nil
    }

    private static func normalizeYear(_ raw: Int) -> Int {
        raw < 100 ? 2000 + raw : raw
    }

    private static func canonical(year: Int, month: Int, day: Int) -> String? {
        guard year >= 1900, year <= 2200 else { return nil }
        guard month >= 1, month <= 12 else { return nil }
        guard day >= 1, day <= daysInMonth(month: month, year: year) else { return nil }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func daysInMonth(month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/DateTokenParserTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: 6 tests passed, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Import/DateTokenParser.swift TenraTests/Services/Import/DateTokenParserTests.swift
git commit -m "feat(import): add multi-format DateTokenParser replacing the DD.MM.YYYY-only regex"
```

---

### Task 3: MoneyTokenParser

The current parser accepts a five-currency whitelist and defaults everything else to `KZT` (`StatementTextParser.swift:302`, `:464`).

**Files:**
- Create: `Tenra/Services/Import/MoneyTokenParser.swift`
- Test: `TenraTests/Services/Import/MoneyTokenParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `MoneyTokenParser.ParsedMoney` (`amount: Double`, `currency: String?`, `isNegative: Bool`), `MoneyTokenParser.parse(_ token: String) -> ParsedMoney?`, `MoneyTokenParser.looksLikeMoney(_ token: String) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `TenraTests/Services/Import/MoneyTokenParserTests.swift`:

```swift
//
//  MoneyTokenParserTests.swift
//  TenraTests
//
//  Pins amount/currency extraction from raw statement and receipt cells.
//

import Testing
@testable import Tenra

struct MoneyTokenParserTests {

    @Test("plain and space-grouped amounts parse")
    func plainAmounts() {
        #expect(MoneyTokenParser.parse("2500")?.amount == 2500)
        #expect(MoneyTokenParser.parse("2 500")?.amount == 2500)
        // Non-breaking space (U+00A0) and thin space (U+2009) are what PDF
        // generators actually emit for digit grouping.
        #expect(MoneyTokenParser.parse("2\u{00A0}500,00")?.amount == 2500)
        #expect(MoneyTokenParser.parse("2\u{2009}500.00")?.amount == 2500)
    }

    @Test("both decimal separator conventions parse")
    func decimalSeparators() {
        #expect(MoneyTokenParser.parse("1234.56")?.amount == 1234.56)
        #expect(MoneyTokenParser.parse("1234,56")?.amount == 1234.56)
        #expect(MoneyTokenParser.parse("1,234.56")?.amount == 1234.56)
        #expect(MoneyTokenParser.parse("1.234,56")?.amount == 1234.56)
    }

    @Test("negative forms are detected without losing magnitude")
    func negatives() {
        let minus = MoneyTokenParser.parse("-1 200,00")
        #expect(minus?.amount == 1200)
        #expect(minus?.isNegative == true)

        // U+2212 MINUS SIGN, which banks use instead of ASCII hyphen.
        let unicodeMinus = MoneyTokenParser.parse("\u{2212}1200")
        #expect(unicodeMinus?.isNegative == true)

        let parens = MoneyTokenParser.parse("(1 200,00)")
        #expect(parens?.amount == 1200)
        #expect(parens?.isNegative == true)
    }

    @Test("ISO codes and symbols resolve to a currency")
    func currencies() {
        #expect(MoneyTokenParser.parse("2 500 KZT")?.currency == "KZT")
        #expect(MoneyTokenParser.parse("USD 40.00")?.currency == "USD")
        #expect(MoneyTokenParser.parse("$40.00")?.currency == "USD")
        #expect(MoneyTokenParser.parse("40,00 €")?.currency == "EUR")
        #expect(MoneyTokenParser.parse("¥1200")?.currency == "JPY")
        #expect(MoneyTokenParser.parse("₸2500")?.currency == "KZT")
        // No currency marker means no guess. The caller supplies a default.
        #expect(MoneyTokenParser.parse("2500")?.currency == nil)
    }

    @Test("non-money tokens return nil")
    func nonMoney() {
        #expect(MoneyTokenParser.parse("") == nil)
        #expect(MoneyTokenParser.parse("Purchase") == nil)
        #expect(MoneyTokenParser.parse("-") == nil)
        // A date must never be read as an amount.
        #expect(MoneyTokenParser.parse("08.01.2026") == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/MoneyTokenParserTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: compile error, `cannot find 'MoneyTokenParser' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Tenra/Services/Import/MoneyTokenParser.swift`:

```swift
//
//  MoneyTokenParser.swift
//  Tenra
//
//  Extracts an amount plus an optional currency from an arbitrary statement or
//  receipt cell. Replaces the five-currency whitelist and the hardcoded "KZT"
//  default in the old StatementTextParser.
//

import Foundation

nonisolated enum MoneyTokenParser {

    struct ParsedMoney: Sendable, Equatable {
        /// Always the absolute value. Direction lives in `isNegative`.
        let amount: Double
        /// ISO 4217 code when the token carried one, otherwise nil.
        let currency: String?
        let isNegative: Bool
    }

    /// Currency symbols that map unambiguously to one ISO code.
    private static let symbolToCode: [Character: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "¥": "JPY", "₸": "KZT",
        "₽": "RUB", "₴": "UAH", "₺": "TRY", "₩": "KRW", "₹": "INR",
        "₪": "ILS", "₫": "VND", "฿": "THB", "₦": "NGN", "₱": "PHP"
    ]

    /// All whitespace variants PDF generators use for digit grouping.
    private static let groupingSpaces: Set<Character> = [
        " ", "\u{00A0}", "\u{2009}", "\u{202F}", "\u{2007}", "'", "\u{2019}"
    ]

    static func parse(_ token: String) -> ParsedMoney? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A date is never an amount. Guard first so "08.01.2026" cannot become
        // 8.012026 through the grouping-separator logic below.
        if DateTokenParser.looksLikeDate(trimmed) { return nil }

        let isNegative = trimmed.hasPrefix("-")
            || trimmed.hasPrefix("\u{2212}")
            || (trimmed.hasPrefix("(") && trimmed.hasSuffix(")"))

        let currency = detectCurrency(in: trimmed)

        // Keep digits and the two separator characters; drop everything else.
        var digits = ""
        for character in trimmed {
            if character.isNumber || character == "." || character == "," {
                digits.append(character)
            } else if groupingSpaces.contains(character), !digits.isEmpty {
                // A grouping space inside a number is dropped silently.
                continue
            }
        }
        guard digits.contains(where: \.isNumber) else { return nil }

        guard let magnitude = Double(normalizeSeparators(digits)) else { return nil }
        return ParsedMoney(amount: magnitude, currency: currency, isNegative: isNegative)
    }

    static func looksLikeMoney(_ token: String) -> Bool {
        parse(token) != nil
    }

    /// Resolves which of "." and "," is the decimal separator, then strips the
    /// other. The last-occurring separator with 1-2 trailing digits wins; if
    /// both look like grouping, everything is grouping.
    private static func normalizeSeparators(_ digits: String) -> String {
        let lastDot = digits.lastIndex(of: ".")
        let lastComma = digits.lastIndex(of: ",")

        let decimalIndex: String.Index?
        switch (lastDot, lastComma) {
        case let (dot?, comma?):
            decimalIndex = dot > comma ? dot : comma
        case let (dot?, nil):
            decimalIndex = dot
        case let (nil, comma?):
            decimalIndex = comma
        case (nil, nil):
            return digits
        }

        guard let separatorIndex = decimalIndex else { return digits }
        let fractionDigits = digits.distance(from: digits.index(after: separatorIndex),
                                             to: digits.endIndex)
        // 1 or 2 trailing digits means a decimal separator. 3 means grouping
        // ("1.234" is one thousand two hundred thirty four, not 1.234).
        guard fractionDigits == 1 || fractionDigits == 2 else {
            return digits.filter(\.isNumber)
        }

        let integerPart = digits[digits.startIndex..<separatorIndex].filter(\.isNumber)
        let fractionPart = digits[digits.index(after: separatorIndex)...].filter(\.isNumber)
        return "\(integerPart).\(fractionPart)"
    }

    private static func detectCurrency(in token: String) -> String? {
        for character in token {
            if let code = symbolToCode[character] { return code }
        }
        // ISO code as a standalone uppercase 3-letter run.
        let uppercased = token.uppercased()
        for match in uppercased.matches(of: /\b([A-Z]{3})\b/) {
            let code = String(match.1)
            if isoCodes.contains(code) { return code }
        }
        return nil
    }

    /// ISO 4217 codes the app can actually hold. Kept in sync with the currency
    /// list in Tenra/Utils/ (see docs/domains/currency.md).
    private static let isoCodes: Set<String> = [
        "USD", "EUR", "GBP", "JPY", "CNY", "CHF", "CAD", "AUD", "NZD",
        "KZT", "RUB", "UAH", "TRY", "KRW", "INR", "BRL", "MXN", "ARS",
        "PLN", "CZK", "HUF", "SEK", "NOK", "DKK", "AED", "SAR", "ILS",
        "THB", "VND", "IDR", "MYR", "SGD", "HKD", "PHP", "NGN", "ZAR",
        "EGP", "GEL", "AMD", "AZN", "UZS", "KGS", "TJS", "BYN", "MDL"
    ]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/MoneyTokenParserTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: 5 tests passed, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Import/MoneyTokenParser.swift TenraTests/Services/Import/MoneyTokenParserTests.swift
git commit -m "feat(import): add MoneyTokenParser with multi-currency and multi-separator support"
```

---

### Task 4: ColumnRoleResolver

Decides what each table column means. This is what makes the importer bank-agnostic: instead of matching one bank's literal header text, it scores columns by header keyword *and* by what the column actually contains.

**Files:**
- Create: `Tenra/Services/Import/ColumnRoleResolver.swift`
- Test: `TenraTests/Services/Import/ColumnRoleResolverTests.swift`

**Interfaces:**
- Consumes: `DocumentSnapshot.Table` (Task 1), `DateTokenParser` (Task 2), `MoneyTokenParser` (Task 3).
- Produces: `ColumnRole` enum, `ColumnRoles` struct (`date`, `amount`, `debit`, `credit`, `currency`, `description`, `confidence`), `ColumnRoleResolver.resolve(table:) -> ColumnRoles?`.

- [ ] **Step 1: Write the failing test**

Create `TenraTests/Services/Import/ColumnRoleResolverTests.swift`:

```swift
//
//  ColumnRoleResolverTests.swift
//  TenraTests
//
//  Pins bank-agnostic column detection. Each test is a real statement layout.
//

import Testing
@testable import Tenra

struct ColumnRoleResolverTests {

    @Test("Russian header keywords resolve")
    func russianHeaders() {
        let table = DocumentSnapshot.Table(rows: [
            ["Дата", "Операция", "Детали", "Сумма", "Валюта"],
            ["08.01.2026", "Покупка", "YANDEX.GO", "2 500", "KZT"],
            ["09.01.2026", "Покупка", "MAGNUM", "7 300", "KZT"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 3)
        #expect(roles?.currency == 4)
        #expect(roles?.description == 2)
    }

    @Test("English header keywords resolve")
    func englishHeaders() {
        let table = DocumentSnapshot.Table(rows: [
            ["Date", "Description", "Amount", "Balance"],
            ["01/08/2026", "UBER TRIP", "-24.50", "1 200.00"],
            ["01/09/2026", "TESCO", "-13.20", "1 186.80"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.description == 1)
        #expect(roles?.amount == 2)
    }

    @Test("separate debit and credit columns are detected")
    func debitCreditColumns() {
        let table = DocumentSnapshot.Table(rows: [
            ["Datum", "Buchungstext", "Soll", "Haben"],
            ["08.01.2026", "REWE MARKT", "24,50", ""],
            ["09.01.2026", "GEHALT", "", "3 200,00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.debit == 2)
        #expect(roles?.credit == 3)
    }

    @Test("headerless tables resolve by column content")
    func contentBasedFallback() {
        // No recognizable header. Column 0 is all dates, column 2 is all money,
        // column 1 is all text. That is enough.
        let table = DocumentSnapshot.Table(rows: [
            ["08.01.2026", "YANDEX.GO", "2 500"],
            ["09.01.2026", "MAGNUM", "7 300"],
            ["10.01.2026", "WOLT", "3 100"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles?.date == 0)
        #expect(roles?.amount == 2)
        #expect(roles?.description == 1)
    }

    @Test("a table with no date column resolves to nil")
    func noDateColumn() {
        let table = DocumentSnapshot.Table(rows: [
            ["Account", "Holder"],
            ["KZ51998PB00009669873", "IVANOV I"]
        ])
        #expect(ColumnRoleResolver.resolve(table: table) == nil)
    }

    @Test("low-confidence resolution is reported as such")
    func lowConfidenceIsReported() {
        // Dates present but only one body row and an unrecognized header:
        // usable, but the caller should consider asking Apple Intelligence.
        let table = DocumentSnapshot.Table(rows: [
            ["Kol1", "Kol2", "Kol3"],
            ["08.01.2026", "SOMETHING", "2 500"]
        ])
        let roles = ColumnRoleResolver.resolve(table: table)
        #expect(roles != nil)
        #expect(roles!.confidence < 0.7)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/ColumnRoleResolverTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: compile error, `cannot find 'ColumnRoleResolver' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Tenra/Services/Import/ColumnRoleResolver.swift`:

```swift
//
//  ColumnRoleResolver.swift
//  Tenra
//
//  Maps table columns to semantic roles. Two signals, combined:
//    1. Header keywords, in the 11 languages the app ships in.
//    2. Column content statistics (how many cells parse as a date / as money).
//  Content wins over header, because content cannot be mistranslated.
//
//  When confidence is low the caller may escalate to
//  IntelligentColumnRoleResolver (Apple Intelligence). This type never does.
//

import Foundation

enum ColumnRole: Sendable, Equatable {
    case date
    case amount
    case debit
    case credit
    case currency
    case description
}

struct ColumnRoles: Sendable, Equatable {
    let date: Int
    /// Single signed amount column. Nil when the table uses debit/credit pairs.
    let amount: Int?
    /// Money-out column, used with `credit`.
    let debit: Int?
    /// Money-in column, used with `debit`.
    let credit: Int?
    let currency: Int?
    let description: Int?
    /// 0...1. Below 0.7 the caller should consider Apple Intelligence.
    let confidence: Double

    /// True when the table carries usable amount information in some shape.
    var hasAmountSignal: Bool {
        amount != nil || debit != nil || credit != nil
    }
}

nonisolated enum ColumnRoleResolver {

    /// Header keywords per role, lowercased, in the 11 shipped locales.
    /// Matching is substring-based so "Дата операции" matches "дата".
    private static let keywords: [ColumnRole: [String]] = [
        .date: ["date", "дата", "datum", "fecha", "data", "tarih", "日付", "날짜", "日期"],
        .amount: ["amount", "sum", "сумма", "betrag", "importe", "montant",
                  "valor", "importo", "tutar", "金額", "금액", "quantia"],
        .debit: ["debit", "withdrawal", "expense", "расход", "списание", "soll",
                 "belastung", "cargo", "débit", "debito", "addebito", "borç",
                 "saída", "出金", "출금"],
        .credit: ["credit", "deposit", "income", "приход", "поступление", "haben",
                  "gutschrift", "abono", "crédit", "credito", "accredito",
                  "alacak", "entrada", "入金", "입금"],
        .currency: ["currency", "валюта", "währung", "moneda", "devise", "moeda",
                    "valuta", "para birimi", "通貨", "통화"],
        .description: ["description", "details", "detail", "narrative", "merchant",
                       "payee", "operation", "описание", "детали", "операция",
                       "назначение", "получатель", "verwendungszweck", "buchungstext",
                       "beschreibung", "concepto", "descripción", "libellé",
                       "descrição", "descrizione", "açıklama", "内容", "摘要", "내용"]
    ]

    /// Fraction of body cells that must parse for a content-based role claim.
    private static let contentThreshold = 0.6

    static func resolve(table: DocumentSnapshot.Table) -> ColumnRoles? {
        guard table.columnCount > 0, !table.rows.isEmpty else { return nil }

        let header = table.headerRow.map { row in row.map { $0.lowercased() } }
        let headerIsRecognized = header.map { hasAnyKeyword($0) } ?? false

        // Score on body rows only. Including row 0 would dilute every column
        // score by one non-conforming cell whenever the table has a header,
        // recognized or not, and a 1-header + 1-data table would score 0.5 and
        // fall under the 0.6 threshold. A single-row table has no header to
        // strip, so it scores itself.
        let body = Array(table.bodyRows)
        let rows = body.isEmpty ? table.rows : body

        var dateScores: [Int: Double] = [:]
        var moneyScores: [Int: Double] = [:]
        var textScores: [Int: Double] = [:]

        for column in 0..<table.columnCount {
            let cells = rows.compactMap { $0.indices.contains(column) ? $0[column] : nil }
            let nonEmpty = cells.filter { !$0.isEmpty }
            guard !nonEmpty.isEmpty else { continue }

            let dateHits = Double(nonEmpty.filter { DateTokenParser.looksLikeDate($0) }.count)
            let moneyHits = Double(nonEmpty.filter { MoneyTokenParser.looksLikeMoney($0) }.count)
            let total = Double(nonEmpty.count)

            dateScores[column] = dateHits / total
            moneyScores[column] = moneyHits / total
            textScores[column] = (total - dateHits - moneyHits) / total
        }

        guard let dateColumn = dateScores
            .filter({ $0.value >= contentThreshold })
            .max(by: { $0.value < $1.value })?.key
        else { return nil }

        let currencyColumn = header.flatMap { columnMatching(.currency, in: $0) }

        let moneyColumns = moneyScores
            .filter { $0.value >= contentThreshold && $0.key != dateColumn && $0.key != currencyColumn }
            .keys
            .sorted()

        var amountColumn: Int?
        var debitColumn: Int?
        var creditColumn: Int?

        if let header {
            debitColumn = columnMatching(.debit, in: header).flatMap {
                moneyColumns.contains($0) ? $0 : nil
            }
            creditColumn = columnMatching(.credit, in: header).flatMap {
                moneyColumns.contains($0) ? $0 : nil
            }
            if debitColumn == nil, creditColumn == nil {
                amountColumn = columnMatching(.amount, in: header).flatMap {
                    moneyColumns.contains($0) ? $0 : nil
                }
            }
        }

        // Content fallback: no usable header signal, so pick money columns
        // positionally. Two adjacent money columns read as debit/credit.
        if amountColumn == nil, debitColumn == nil, creditColumn == nil {
            if moneyColumns.count >= 2,
               let last = moneyColumns.last,
               let secondLast = moneyColumns.dropLast().last,
               last - secondLast == 1 {
                debitColumn = secondLast
                creditColumn = last
            } else {
                amountColumn = moneyColumns.first
            }
        }

        let descriptionColumn = header.flatMap { columnMatching(.description, in: $0) }
            ?? textScores
                .filter { $0.value >= contentThreshold }
                .max(by: { $0.value < $1.value })?.key

        let confidence = confidenceScore(
            headerRecognized: headerIsRecognized,
            bodyRowCount: rows.count,
            dateScore: dateScores[dateColumn] ?? 0,
            hasAmount: amountColumn != nil || debitColumn != nil || creditColumn != nil,
            hasDescription: descriptionColumn != nil
        )

        return ColumnRoles(
            date: dateColumn,
            amount: amountColumn,
            debit: debitColumn,
            credit: creditColumn,
            currency: currencyColumn,
            description: descriptionColumn,
            confidence: confidence
        )
    }

    private static func hasAnyKeyword(_ header: [String]) -> Bool {
        keywords.values.contains { list in
            header.contains { cell in list.contains { cell.contains($0) } }
        }
    }

    private static func columnMatching(_ role: ColumnRole, in header: [String]) -> Int? {
        guard let list = keywords[role] else { return nil }
        return header.firstIndex { cell in list.contains { cell.contains($0) } }
    }

    private static func confidenceScore(
        headerRecognized: Bool,
        bodyRowCount: Int,
        dateScore: Double,
        hasAmount: Bool,
        hasDescription: Bool
    ) -> Double {
        var score = 0.0
        score += headerRecognized ? 0.35 : 0.0
        score += min(Double(bodyRowCount) / 5.0, 1.0) * 0.2
        score += dateScore * 0.25
        score += hasAmount ? 0.15 : 0.0
        score += hasDescription ? 0.05 : 0.0
        return min(score, 1.0)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/ColumnRoleResolverTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: 6 tests passed, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Import/ColumnRoleResolver.swift TenraTests/Services/Import/ColumnRoleResolverTests.swift
git commit -m "feat(import): add bank-agnostic ColumnRoleResolver with header and content signals"
```

---

### Task 5: StatementInterpreter

Turns a resolved table into transactions, and reports every row it could not use instead of dropping it silently.

**Files:**
- Create: `Tenra/Services/Import/StatementInterpreter.swift`
- Test: `TenraTests/Services/Import/StatementInterpreterTests.swift`

**Interfaces:**
- Consumes: `DocumentSnapshot` (Task 1), `DateTokenParser` (Task 2), `MoneyTokenParser` (Task 3), `ColumnRoles` / `ColumnRoleResolver` (Task 4).
- Produces: `ParsedTransaction` (`date: String`, `amount: Double`, `currency: String?`, `descriptionText: String`, `direction: TransactionDirection`), `TransactionDirection` (`.income`, `.expense`, `.transfer`), `SkippedRow` (`rowIndex: Int`, `cells: [String]`, `reason: String`), `ParsedStatement` (`transactions`, `skipped`, `resolvedRoles`), `StatementInterpreter.interpret(snapshot:roles:defaultCurrency:) -> ParsedStatement`, `StatementInterpreter.csvFile(from:) -> CSVFile`.

- [ ] **Step 1: Write the failing test**

Create `TenraTests/Services/Import/StatementInterpreterTests.swift`:

```swift
//
//  StatementInterpreterTests.swift
//  TenraTests
//
//  Pins table -> transactions. Also pins that unusable rows are REPORTED
//  rather than silently dropped, which was the old parser's worst failure mode.
//

import Testing
@testable import Tenra

struct StatementInterpreterTests {

    private func snapshot(_ rows: [[String]]) -> DocumentSnapshot {
        DocumentSnapshot(
            pages: [.init(index: 0,
                          tables: [DocumentSnapshot.Table(rows: rows)],
                          lines: [],
                          barcodes: [])],
            hadTextLayer: true
        )
    }

    @Test("single amount column with explicit currency parses")
    func singleAmountColumn() {
        let doc = snapshot([
            ["Дата", "Операция", "Детали", "Сумма", "Валюта"],
            ["08.01.2026", "Покупка", "YANDEX.GO", "2 500", "KZT"],
            ["09.01.2026", "Пополнение", "SALARY", "300 000", "KZT"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].date == "2026-01-08")
        #expect(result.transactions[0].amount == 2500)
        #expect(result.transactions[0].currency == "KZT")
        #expect(result.transactions[0].descriptionText == "YANDEX.GO")
        #expect(result.skipped.isEmpty)
    }

    @Test("negative amounts become expenses and positive become income")
    func signDrivesDirection() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["01/09/2026", "REFUND", "12.00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions[0].direction == .expense)
        #expect(result.transactions[0].amount == 24.50)
        #expect(result.transactions[1].direction == .income)
        // No currency in the cell, so the caller's default applies.
        #expect(result.transactions[0].currency == "EUR")
    }

    @Test("debit and credit columns drive direction")
    func debitCreditDirection() {
        let doc = snapshot([
            ["Datum", "Buchungstext", "Soll", "Haben"],
            ["08.01.2026", "REWE MARKT", "24,50", ""],
            ["09.01.2026", "GEHALT", "", "3 200,00"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].direction == .expense)
        #expect(result.transactions[0].amount == 24.50)
        #expect(result.transactions[1].direction == .income)
        #expect(result.transactions[1].amount == 3200.00)
    }

    @Test("unusable rows are reported, not dropped")
    func skippedRowsAreReported() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["Subtotal", "", "-24.50"],          // no date
            ["01/10/2026", "MYSTERY", ""]        // no amount
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")

        #expect(result.transactions.count == 1)
        #expect(result.skipped.count == 2)
        #expect(result.skipped.contains { $0.cells.contains("Subtotal") })
        #expect(result.skipped.contains { $0.cells.contains("MYSTERY") })
    }

    @Test("reference numbers are stripped from descriptions")
    func descriptionCleaning() {
        let doc = snapshot([
            ["Дата", "Операция", "Детали", "Сумма"],
            ["08.01.2026", "Покупка", "YANDEX.GO Референс: 600815665697 Код авторизации: 681997", "2 500"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "KZT")

        #expect(result.transactions[0].descriptionText == "YANDEX.GO")
    }

    @Test("csvFile output matches the existing CSV import contract")
    func csvFileShape() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "EUR")
        let csv = StatementInterpreter.csvFile(from: result)

        #expect(csv.headers.count == 8)
        #expect(csv.rows.count == 1)
        #expect(csv.rows[0][0] == "2026-01-08")
        #expect(csv.rows[0][1] == "expense")
        #expect(csv.rows[0][2] == "24.5")
        #expect(csv.rows[0][3] == "EUR")
        #expect(csv.rows[0][4] == "UBER TRIP")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/StatementInterpreterTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: compile error, `cannot find 'StatementInterpreter' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Tenra/Services/Import/StatementInterpreter.swift`:

```swift
//
//  StatementInterpreter.swift
//  Tenra
//
//  DocumentSnapshot + ColumnRoles -> transactions. Bank-agnostic: it knows
//  nothing about any specific institution, only about column roles.
//
//  Every row that cannot be used is recorded in `skipped` with a reason. The
//  previous implementation dropped such rows silently, so a user could import
//  20 of 60 operations and never learn about the other 40.
//

import Foundation

enum TransactionDirection: String, Sendable, Equatable {
    case income
    case expense
    case transfer
}

struct ParsedTransaction: Sendable, Equatable {
    let date: String            // canonical "yyyy-MM-dd"
    let amount: Double          // always positive; direction is separate
    let currency: String?       // nil means "use the caller's default"
    let descriptionText: String
    let direction: TransactionDirection
}

struct SkippedRow: Sendable, Equatable {
    let rowIndex: Int
    let cells: [String]
    /// Localization key describing why, e.g. "import.skip.noDate".
    let reason: String
}

struct ParsedStatement: Sendable, Equatable {
    let transactions: [ParsedTransaction]
    let skipped: [SkippedRow]
    let resolvedRoles: ColumnRoles?
}

nonisolated enum StatementInterpreter {

    /// Header layout of the CSV pipeline this feeds into. Must stay aligned
    /// with the existing CSV import flow (Tenra/Services/CSV/CSVImporter.swift).
    static let csvHeaders = [
        "Date", "Type", "Amount", "Currency", "Description", "Account", "Category", "Subcategory"
    ]

    static func interpret(
        snapshot: DocumentSnapshot,
        roles: ColumnRoles,
        defaultCurrency: String
    ) -> ParsedStatement {
        var transactions: [ParsedTransaction] = []
        var skipped: [SkippedRow] = []
        var rowIndex = 0

        for table in snapshot.allTables {
            // Re-resolving per table would be wrong: the caller resolved roles
            // for the table it chose. Only interpret tables of matching width.
            guard table.columnCount > roles.date else { continue }

            for row in table.rows {
                rowIndex += 1

                guard let date = cell(row, roles.date).flatMap(DateTokenParser.parse) else {
                    // A header row is expected to have no date; do not report it.
                    if !isLikelyHeader(row) {
                        skipped.append(SkippedRow(rowIndex: rowIndex,
                                                  cells: row,
                                                  reason: "import.skip.noDate"))
                    }
                    continue
                }

                guard let money = extractMoney(from: row, roles: roles) else {
                    skipped.append(SkippedRow(rowIndex: rowIndex,
                                              cells: row,
                                              reason: "import.skip.noAmount"))
                    continue
                }

                let explicitCurrency = cell(row, roles.currency)
                    .flatMap { MoneyTokenParser.parse($0)?.currency ?? normalizedISO($0) }

                transactions.append(ParsedTransaction(
                    date: date,
                    amount: money.amount,
                    currency: money.currency ?? explicitCurrency ?? defaultCurrency,
                    descriptionText: description(from: row, roles: roles),
                    direction: money.direction
                ))
            }
        }

        return ParsedStatement(transactions: transactions,
                               skipped: skipped,
                               resolvedRoles: roles)
    }

    /// Bridges into the existing CSV mapping UI, which every import path already
    /// funnels through. Amount is emitted unsigned; `Type` carries direction.
    static func csvFile(from statement: ParsedStatement) -> CSVFile {
        let rows = statement.transactions.map { transaction in
            [
                transaction.date,
                transaction.direction.rawValue,
                String(transaction.amount),
                transaction.currency ?? "",
                transaction.descriptionText,
                "",   // Account, filled during entity mapping
                "",   // Category, filled during entity mapping
                ""    // Subcategory, filled during entity mapping
            ]
        }
        return CSVFile(headers: csvHeaders, rows: rows, preview: Array(rows.prefix(5)))
    }

    // MARK: - Private

    private struct MoneyWithDirection {
        let amount: Double
        let currency: String?
        let direction: TransactionDirection
    }

    private static func extractMoney(from row: [String], roles: ColumnRoles) -> MoneyWithDirection? {
        // Debit/credit layout: whichever side is populated decides direction.
        if roles.debit != nil || roles.credit != nil {
            if let debitCell = cell(row, roles.debit),
               let parsed = MoneyTokenParser.parse(debitCell), parsed.amount > 0 {
                return MoneyWithDirection(amount: parsed.amount,
                                          currency: parsed.currency,
                                          direction: .expense)
            }
            if let creditCell = cell(row, roles.credit),
               let parsed = MoneyTokenParser.parse(creditCell), parsed.amount > 0 {
                return MoneyWithDirection(amount: parsed.amount,
                                          currency: parsed.currency,
                                          direction: .income)
            }
            return nil
        }

        // Single signed amount column.
        guard let amountCell = cell(row, roles.amount),
              let parsed = MoneyTokenParser.parse(amountCell) else { return nil }
        return MoneyWithDirection(amount: parsed.amount,
                                  currency: parsed.currency,
                                  direction: parsed.isNegative ? .expense : .income)
    }

    private static func description(from row: [String], roles: ColumnRoles) -> String {
        if let text = cell(row, roles.description), !text.isEmpty {
            return clean(text)
        }
        // No description column: join every cell that is neither the date nor
        // an amount, so the user still sees something recognizable.
        let structuralColumns = Set([roles.date, roles.amount, roles.debit,
                                     roles.credit, roles.currency].compactMap { $0 })
        let parts = row.enumerated()
            .filter { !structuralColumns.contains($0.offset) }
            .map(\.element)
            .filter { !$0.isEmpty }
        return clean(parts.joined(separator: " "))
    }

    /// Strips transport noise banks append to every line. Keep this list short:
    /// over-cleaning destroys merchant names.
    private static func clean(_ text: String) -> String {
        var cleaned = text
        let noisePatterns = [
            #"(?i)Референс:\s*\S+"#,
            #"(?i)Код авторизации:\s*\S+"#,
            #"(?i)Reference:\s*\S+"#,
            #"(?i)Auth(?:orization)? code:\s*\S+"#,
            #"(?i)Ref\.?\s*No\.?:?\s*\S+"#
        ]
        for pattern in noisePatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        cleaned = cleaned.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cell(_ row: [String], _ index: Int?) -> String? {
        guard let index, row.indices.contains(index) else { return nil }
        let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func normalizedISO(_ token: String) -> String? {
        let candidate = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return candidate.count == 3 && candidate.allSatisfy(\.isLetter) ? candidate : nil
    }

    /// A row with no date and no parseable money is almost certainly a header
    /// or a section label. Reporting those as "skipped" would be noise.
    private static func isLikelyHeader(_ row: [String]) -> Bool {
        !row.contains { MoneyTokenParser.looksLikeMoney($0) }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/StatementInterpreterTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: 6 tests passed, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tenra/Services/Import/StatementInterpreter.swift TenraTests/Services/Import/StatementInterpreterTests.swift
git commit -m "feat(import): add StatementInterpreter with skipped-row diagnostics"
```

---

### Task 6: VisionDocumentExtractor (iOS 26 RecognizeDocumentsRequest)

Replaces `performStructuredOCR`, `structureObservations`, and the whole coordinate-clustering apparatus in `PDFService.swift:150-621` with the system table extractor.

**Files:**
- Create: `Tenra/Services/Import/VisionDocumentExtractor.swift`

**Interfaces:**
- Consumes: `DocumentSnapshot` (Task 1).
- Produces: `VisionDocumentExtractor.extract(images:) async throws -> DocumentSnapshot`, `VisionDocumentExtractor.extract(image:pageIndex:) async throws -> DocumentSnapshot.Page`, `DocumentExtractionError`.

Verified against the iOS 26.5 SDK:
- `RecognizeDocumentsRequest.textRecognitionOptions` has `automaticallyDetectLanguage`, `recognitionLanguages: [Locale.Language]`, `useLanguageCorrection`, `customWords`.
- `RecognizeDocumentsRequest.barcodeDetectionOptions.enabled: Bool`.
- `try await request.perform(on: cgImage)` returns `[DocumentObservation]`.
- `DocumentObservation.document: Container`; `Container.tables: [Container.Table]`; `Table.columns: [[Cell]]`; `Table.rows: [[Cell]]`; `Table.cell(row:col:) -> Cell?`; `Cell.content: Container`; `Container.text: Container.Text`; `Text.transcript: String`; `Text.lines: [RecognizedTextObservation]`; `Container.barcodes: [BarcodeObservation]`.

- [ ] **Step 1: Write the implementation**

Create `Tenra/Services/Import/VisionDocumentExtractor.swift`:

```swift
//
//  VisionDocumentExtractor.swift
//  Tenra
//
//  iOS 26 document extraction. RecognizeDocumentsRequest returns a structured
//  document (tables as real grids, paragraphs, barcodes) instead of a bag of
//  text rectangles, which removes the need for the hand-rolled row/column
//  clustering the previous implementation used.
//
//  Language handling: automaticallyDetectLanguage replaces the hardcoded
//  ["ru-RU", "en-US"] list, so the 9 non-Russian locales the app ships in are
//  no longer second-class. useLanguageCorrection is OFF because statement and
//  receipt content is mostly numbers, merchant names, and reference codes,
//  where a language model "correcting" a token silently corrupts an amount.
//

import Foundation
import Vision
import CoreGraphics

enum DocumentExtractionError: LocalizedError {
    case noContentRecognized

    var errorDescription: String? {
        switch self {
        case .noContentRecognized:
            return String(localized: "import.error.noContentRecognized")
        }
    }
}

nonisolated struct VisionDocumentExtractor {

    /// Extra vocabulary that keeps common statement tokens from being mangled.
    private static let customWords = ["IBAN", "SWIFT", "BIC", "POS", "ATM", "P2P"]

    static func extract(images: [CGImage]) async throws -> DocumentSnapshot {
        var pages: [DocumentSnapshot.Page] = []
        for (index, image) in images.enumerated() {
            pages.append(try await extract(image: image, pageIndex: index))
        }
        guard pages.contains(where: { !$0.tables.isEmpty || !$0.lines.isEmpty }) else {
            throw DocumentExtractionError.noContentRecognized
        }
        return DocumentSnapshot(pages: pages, hadTextLayer: false)
    }

    static func extract(image: CGImage, pageIndex: Int) async throws -> DocumentSnapshot.Page {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.automaticallyDetectLanguage = true
        request.textRecognitionOptions.useLanguageCorrection = false
        request.textRecognitionOptions.customWords = customWords
        // Receipts print totals in small type; the default floor drops them.
        request.textRecognitionOptions.minimumTextHeightFraction = 0.008
        // Fiscal receipts in several markets carry a QR with the authoritative
        // total. Nothing reads it yet; it is collected because it is free here
        // and re-running extraction later would not be. Surfaced on
        // DocumentSnapshot.allBarcodes for a future fiscal-lookup path.
        request.barcodeDetectionOptions.enabled = true

        let observations = try await request.perform(on: image)
        guard let container = observations.first?.document else {
            return DocumentSnapshot.Page(index: pageIndex, tables: [], lines: [], barcodes: [])
        }

        return DocumentSnapshot.Page(
            index: pageIndex,
            tables: container.tables.map(snapshotTable(from:)),
            lines: lines(from: container),
            barcodes: container.barcodes.compactMap { barcode in
                guard let payload = barcode.payloadString else { return nil }
                return DocumentSnapshot.Barcode(
                    payload: payload,
                    symbology: String(describing: barcode.symbology)
                )
            }
        )
    }

    /// Flattens a Vision table into a rectangular grid of strings.
    /// `cell(row:col:)` is used rather than iterating `rows` directly because a
    /// merged cell appears in every row it spans, and the grid accessor already
    /// resolves that.
    private static func snapshotTable(
        from table: DocumentObservation.Container.Table
    ) -> DocumentSnapshot.Table {
        let columnCount = table.columns.count
        let rowCount = table.rows.count
        var grid: [[String]] = []
        grid.reserveCapacity(rowCount)

        for row in 0..<rowCount {
            var cells: [String] = []
            cells.reserveCapacity(columnCount)
            for column in 0..<columnCount {
                let text = table.cell(row: row, col: column)?.content.text.transcript ?? ""
                cells.append(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            grid.append(cells)
        }
        return DocumentSnapshot.Table(rows: grid)
    }

    /// Every text line on the page, in reading order. Line breaks are preserved
    /// deliberately: the previous implementation joined recognized strings with
    /// a single space, which destroyed every line-oriented fallback.
    private static func lines(from container: DocumentObservation.Container) -> [String] {
        container.text.lines
            .map { $0.transcript.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
```

- [ ] **Step 2: Verify the barcode payload accessor name against the SDK**

`BarcodeObservation`'s payload property name differs between the legacy `VNBarcodeObservation` and the iOS 26 `Vision.BarcodeObservation`. Confirm before building:

```bash
grep -n "public struct BarcodeObservation" -A 20 "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/Vision.framework/Modules/Vision.swiftmodule/arm64e-apple-ios.swiftinterface"
```
Expected: a list of properties. Use whichever of `payloadString` / `payloadStringValue` appears, and adjust the code above to match.

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output. If `import.error.noContentRecognized` triggers a missing-key warning, ignore it for now: Task 12 adds the string to all 11 locales.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Import/VisionDocumentExtractor.swift
git commit -m "feat(import): extract documents with iOS 26 RecognizeDocumentsRequest"
```

---

### Task 7: PDFTextLayerExtractor

Fixes the second structural defect: `PDFService.extractTextBlocksWithBoundingBoxes` (`PDFService.swift:230-335`) throws away real word positions and synthesizes evenly spaced ones, then `structurePDFTextBlocks` clusters columns from those synthetic gaps. This task uses real glyph bounds.

**Files:**
- Create: `Tenra/Services/Import/PDFTextLayerExtractor.swift`

**Interfaces:**
- Consumes: `DocumentSnapshot` (Task 1).
- Produces: `PDFTextLayerExtractor.extract(document:) -> DocumentSnapshot?` returning nil when the PDF has no usable text layer.

- [ ] **Step 1: Write the implementation**

Create `Tenra/Services/Import/PDFTextLayerExtractor.swift`:

```swift
//
//  PDFTextLayerExtractor.swift
//  Tenra
//
//  Text-layer PDFs (the large majority of bank statements) need no OCR at all:
//  PDFKit already holds exact glyph positions. This extractor uses
//  PDFPage.characterBounds(at:) to find real word boundaries and clusters
//  columns from real horizontal gaps.
//
//  The previous implementation divided each line's width evenly across its
//  words, discarding true positions, and then tried to infer columns from the
//  resulting uniform gaps. That is why long descriptions shifted columns.
//

import Foundation
import PDFKit
import CoreGraphics

nonisolated struct PDFTextLayerExtractor {

    private struct PositionedWord {
        let text: String
        let minX: CGFloat
        let maxX: CGFloat
    }

    /// Returns nil when the document has no text layer, so the caller can fall
    /// back to rendering pages and running VisionDocumentExtractor.
    static func extract(document: PDFDocument) -> DocumentSnapshot? {
        var pages: [DocumentSnapshot.Page] = []
        var sawText = false

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let pageText = page.string,
                  !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                pages.append(.init(index: pageIndex, tables: [], lines: [], barcodes: []))
                continue
            }
            sawText = true

            let lineWords = wordsPerLine(on: page)
            let lines = lineWords.map { words in
                words.map(\.text).joined(separator: " ")
            }
            let table = table(from: lineWords)

            pages.append(.init(
                index: pageIndex,
                tables: table.map { [$0] } ?? [],
                lines: lines,
                barcodes: []
            ))
        }

        guard sawText else { return nil }
        return DocumentSnapshot(pages: pages, hadTextLayer: true)
    }

    /// Splits each line into words carrying their real horizontal extent.
    private static func wordsPerLine(on page: PDFPage) -> [[PositionedWord]] {
        guard let fullSelection = page.selection(for: page.bounds(for: .mediaBox)) else {
            return []
        }

        var result: [[PositionedWord]] = []

        for lineSelection in fullSelection.selectionsByLine() {
            guard let lineText = lineSelection.string, !lineText.isEmpty else { continue }

            var words: [PositionedWord] = []
            var currentCharacters = ""
            var currentMinX: CGFloat = .greatestFiniteMagnitude
            var currentMaxX: CGFloat = -.greatestFiniteMagnitude

            // characterBounds(at:) is indexed within the selection's own string.
            for (offset, character) in lineText.enumerated() {
                let bounds = lineSelection.characterBounds(at: offset)

                if character.isWhitespace {
                    if !currentCharacters.isEmpty {
                        words.append(PositionedWord(text: currentCharacters,
                                                    minX: currentMinX,
                                                    maxX: currentMaxX))
                        currentCharacters = ""
                        currentMinX = .greatestFiniteMagnitude
                        currentMaxX = -.greatestFiniteMagnitude
                    }
                    continue
                }

                currentCharacters.append(character)
                currentMinX = min(currentMinX, bounds.minX)
                currentMaxX = max(currentMaxX, bounds.maxX)
            }

            if !currentCharacters.isEmpty {
                words.append(PositionedWord(text: currentCharacters,
                                            minX: currentMinX,
                                            maxX: currentMaxX))
            }
            if !words.isEmpty { result.append(words) }
        }

        return result
    }

    /// Groups words into columns using real inter-word gaps. A gap wider than
    /// `gapThreshold` starts a new column. The threshold is derived from the
    /// page's own typography rather than a fixed page-width fraction, so it
    /// adapts to dense and sparse statements alike.
    private static func table(from lineWords: [[PositionedWord]]) -> DocumentSnapshot.Table? {
        let allGaps: [CGFloat] = lineWords.flatMap { words -> [CGFloat] in
            guard words.count > 1 else { return [] }
            return (0..<(words.count - 1)).map { words[$0 + 1].minX - words[$0].maxX }
        }
        guard !allGaps.isEmpty else { return nil }

        let sortedGaps = allGaps.sorted()
        // Median gap approximates a single space at this font size. A column
        // break is a gap several times wider than that.
        let medianGap = sortedGaps[sortedGaps.count / 2]
        let gapThreshold = max(medianGap * 3.0, 6.0)

        var rows: [[String]] = []
        for words in lineWords {
            var cells: [String] = []
            var current: [String] = []

            for (index, word) in words.enumerated() {
                if index > 0 {
                    let gap = word.minX - words[index - 1].maxX
                    if gap > gapThreshold, !current.isEmpty {
                        cells.append(current.joined(separator: " "))
                        current = []
                    }
                }
                current.append(word.text)
            }
            if !current.isEmpty { cells.append(current.joined(separator: " ")) }
            rows.append(cells)
        }

        // A table needs at least two columns somewhere, otherwise this page is
        // prose and the caller should use `lines`.
        guard rows.contains(where: { $0.count >= 2 }) else { return nil }
        return DocumentSnapshot.Table(rows: rows)
    }
}
```

- [ ] **Step 2: Verify `characterBounds(at:)` is available on PDFSelection**

`characterBounds(at:)` exists on `PDFPage`, and on `PDFSelection` only in newer SDKs. Confirm which receiver to use:

```bash
grep -rn "characterBounds" "$(xcrun --sdk iphoneos --show-sdk-path)/System/Library/Frameworks/PDFKit.framework/Headers/"*.h
```
Expected: a declaration on `PDFPage` and possibly `PDFSelection`. If it only exists on `PDFPage`, change `lineSelection.characterBounds(at: offset)` to compute the offset within the page's full string and call `page.characterBounds(at: pageOffset)`; track the running page offset while walking `selectionsByLine()`.

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Import/PDFTextLayerExtractor.swift
git commit -m "fix(import): use real PDF glyph bounds for column detection instead of uniform word spacing"
```

---

### Task 8: IntelligenceAvailability + IntelligentColumnRoleResolver

Apple Intelligence is applied where it is genuinely better than heuristics and cheap in context: inferring **what the columns mean**, from a header row plus two sample rows. It is deliberately *not* used to read every transaction. Per-row extraction would be slow, would risk hallucinated amounts, and would blow the model's context window on a 200-row statement.

**Files:**
- Create: `Tenra/Services/Import/IntelligenceAvailability.swift`
- Create: `Tenra/Services/Import/IntelligentColumnRoleResolver.swift`

**Interfaces:**
- Consumes: `DocumentSnapshot.Table` (Task 1), `ColumnRoles` (Task 4).
- Produces: `IntelligenceAvailability.status` returning `IntelligenceStatus` (`.available`, `.deviceNotEligible`, `.notEnabled`, `.modelNotReady`), `IntelligenceAvailability.isAvailable: Bool`, `IntelligentColumnRoleResolver.resolve(table:) async -> ColumnRoles?`.

- [ ] **Step 1: Write the availability wrapper**

Create `Tenra/Services/Import/IntelligenceAvailability.swift`:

```swift
//
//  IntelligenceAvailability.swift
//  Tenra
//
//  Single place that touches SystemLanguageModel availability, so the rest of
//  the import pipeline never imports FoundationModels and stays testable.
//
//  Apple Intelligence is unavailable on iPhone 14 and older, when the user has
//  not enabled it, and while assets are still downloading. Every one of those
//  is a normal state, not an error: the deterministic path handles them.
//

import Foundation
import FoundationModels

enum IntelligenceStatus: Sendable, Equatable {
    case available
    case deviceNotEligible
    case notEnabled
    case modelNotReady

    /// Localization key for the UI hint explaining reduced capability.
    var explanationKey: String? {
        switch self {
        case .available: return nil
        case .deviceNotEligible: return "import.intelligence.deviceNotEligible"
        case .notEnabled: return "import.intelligence.notEnabled"
        case .modelNotReady: return "import.intelligence.modelNotReady"
        }
    }
}

nonisolated enum IntelligenceAvailability {

    static var status: IntelligenceStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            return .notEnabled
        case .unavailable(.modelNotReady):
            return .modelNotReady
        @unknown default:
            return .modelNotReady
        }
    }

    static var isAvailable: Bool { status == .available }
}
```

- [ ] **Step 2: Write the intelligent resolver**

Create `Tenra/Services/Import/IntelligentColumnRoleResolver.swift`:

```swift
//
//  IntelligentColumnRoleResolver.swift
//  Tenra
//
//  Apple Intelligence column-role inference, used ONLY when
//  ColumnRoleResolver's confidence is low. One small prompt per table:
//  the header row plus two sample rows in, a column-index mapping out.
//
//  Why schema inference and not per-row extraction: a 200-row statement does
//  not fit the on-device model's context window, per-row generation would be
//  slow, and an LLM re-typing amounts can hallucinate digits. Inferring the
//  layout once and then parsing every row deterministically keeps the numbers
//  exact while still handling a bank we have never seen.
//

import Foundation
import FoundationModels

/// Structured output schema. Column indices are 0-based; -1 means "absent".
@Generable
struct InferredColumnLayout {
    @Guide(description: "0-based index of the column holding the transaction date. Use -1 if there is none.")
    var dateColumn: Int

    @Guide(description: "0-based index of the column holding a single signed transaction amount. Use -1 if the table instead has separate money-out and money-in columns.")
    var amountColumn: Int

    @Guide(description: "0-based index of the money-out (debit) column. Use -1 if absent.")
    var debitColumn: Int

    @Guide(description: "0-based index of the money-in (credit) column. Use -1 if absent.")
    var creditColumn: Int

    @Guide(description: "0-based index of the currency code column. Use -1 if absent.")
    var currencyColumn: Int

    @Guide(description: "0-based index of the column describing the merchant or counterparty. Use -1 if absent.")
    var descriptionColumn: Int
}

nonisolated struct IntelligentColumnRoleResolver {

    private static let instructions = """
    You analyse bank statement tables. Given a table's header row and a few \
    sample rows, you identify which column index holds which kind of \
    information. You only report column indices. You never invent or restate \
    the values themselves. Column indices are 0-based. When a role is not \
    present in the table, report -1 for it.
    """

    /// Returns nil when Apple Intelligence is unavailable or the model could
    /// not produce a usable layout. Callers must always have a fallback.
    static func resolve(table: DocumentSnapshot.Table) async -> ColumnRoles? {
        guard IntelligenceAvailability.isAvailable else { return nil }
        guard table.columnCount > 0, !table.rows.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = buildPrompt(for: table)

        do {
            let response = try await session.respond(
                to: prompt,
                generating: InferredColumnLayout.self,
                options: GenerationOptions(sampling: .greedy)
            )
            return columnRoles(from: response.content, columnCount: table.columnCount)
        } catch {
            // Every FoundationModels failure mode (exceededContextWindowSize,
            // assetsUnavailable, guardrailViolation, rateLimited, ...) means the
            // same thing here: fall back to the deterministic resolver.
            return nil
        }
    }

    private static func buildPrompt(for table: DocumentSnapshot.Table) -> String {
        // Three rows is enough signal and keeps the prompt far inside the
        // context window regardless of statement length.
        let sample = table.rows.prefix(3).enumerated().map { index, row in
            let cells = row.enumerated()
                .map { "[\($0.offset)] \($0.element)" }
                .joined(separator: " | ")
            return "Row \(index): \(cells)"
        }.joined(separator: "\n")

        return """
        The table has \(table.columnCount) columns, indexed 0 to \(table.columnCount - 1).

        \(sample)

        Identify the column index for each role.
        """
    }

    private static func columnRoles(
        from layout: InferredColumnLayout,
        columnCount: Int
    ) -> ColumnRoles? {
        func validate(_ index: Int) -> Int? {
            (0..<columnCount).contains(index) ? index : nil
        }

        guard let dateColumn = validate(layout.dateColumn) else { return nil }

        let amount = validate(layout.amountColumn)
        let debit = validate(layout.debitColumn)
        let credit = validate(layout.creditColumn)
        guard amount != nil || debit != nil || credit != nil else { return nil }

        return ColumnRoles(
            date: dateColumn,
            amount: amount,
            debit: debit,
            credit: credit,
            currency: validate(layout.currencyColumn),
            description: validate(layout.descriptionColumn),
            // Model-resolved layouts are trusted, but never above a confidently
            // header-matched deterministic result.
            confidence: 0.8
        )
    }
}
```

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add Tenra/Services/Import/IntelligenceAvailability.swift Tenra/Services/Import/IntelligentColumnRoleResolver.swift
git commit -m "feat(import): infer statement column layout with on-device Apple Intelligence"
```

---

### Task 9: DocumentImportService orchestrator + PDFService reduction

Wires acquisition, extraction, and interpretation together off the MainActor, and strips `PDFService` down to page rendering.

**Files:**
- Create: `Tenra/Services/Import/DocumentImportService.swift`
- Modify: `Tenra/Services/Import/PDFService.swift` (replace lines 37-694 wholesale; keep `PDFError`)

**Interfaces:**
- Consumes: everything from Tasks 1 and 4-8.
- Produces: `ImportOutcome` (`csvFile: CSVFile`, `statement: ParsedStatement`, `intelligenceStatus: IntelligenceStatus`), `DocumentImportService.importStatement(from url: URL, defaultCurrency: String, progress: (@Sendable (Int, Int) -> Void)?) async throws -> ImportOutcome`, `DocumentImportService.importStatement(images: [CGImage], defaultCurrency: String) async throws -> ImportOutcome`, `PDFService.renderPages(of:scale:) -> [CGImage]`.

- [ ] **Step 1: Write the orchestrator**

Create `Tenra/Services/Import/DocumentImportService.swift`:

```swift
//
//  DocumentImportService.swift
//  Tenra
//
//  Orchestrates acquisition -> extraction -> interpretation. Runs entirely off
//  the MainActor over Sendable values (CLAUDE.md Red Flag #9): a 40-page
//  statement must not stall the UI.
//
//  Extraction strategy: text-layer PDFs go through PDFKit (exact, fast, no OCR).
//  Scanned PDFs and camera images go through Vision. Interpretation strategy:
//  deterministic ColumnRoleResolver first; escalate to Apple Intelligence only
//  when confidence is low and the model is available.
//

import Foundation
import PDFKit
import CoreGraphics

struct ImportOutcome: Sendable {
    let csvFile: CSVFile
    let statement: ParsedStatement
    let intelligenceStatus: IntelligenceStatus
}

/// Below this, escalate column resolution to Apple Intelligence.
private let confidenceEscalationThreshold = 0.7

nonisolated struct DocumentImportService {

    static func importStatement(
        from url: URL,
        defaultCurrency: String,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> ImportOutcome {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }

        guard let document = PDFDocument(url: url)
            ?? (try? Data(contentsOf: url)).flatMap(PDFDocument.init(data:))
        else {
            throw PDFError.invalidDocument
        }

        let snapshot: DocumentSnapshot
        if let textLayer = PDFTextLayerExtractor.extract(document: document) {
            progress?(document.pageCount, document.pageCount)
            snapshot = textLayer
        } else {
            let images = PDFService.renderPages(of: document, scale: 3.5) { current, total in
                progress?(current, total)
            }
            snapshot = try await VisionDocumentExtractor.extract(images: images)
        }

        return try await interpret(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    static func importStatement(
        images: [CGImage],
        defaultCurrency: String
    ) async throws -> ImportOutcome {
        let snapshot = try await VisionDocumentExtractor.extract(images: images)
        return try await interpret(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    // MARK: - Private

    private static func interpret(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) async throws -> ImportOutcome {
        guard let table = bestTable(in: snapshot) else {
            throw PDFError.noTextFound
        }

        var roles = ColumnRoleResolver.resolve(table: table)

        if (roles?.confidence ?? 0) < confidenceEscalationThreshold {
            if let inferred = await IntelligentColumnRoleResolver.resolve(table: table) {
                roles = inferred
            }
        }

        guard let resolvedRoles = roles else { throw PDFError.noTextFound }

        let statement = StatementInterpreter.interpret(
            snapshot: snapshot,
            roles: resolvedRoles,
            defaultCurrency: defaultCurrency
        )

        guard !statement.transactions.isEmpty else { throw PDFError.noTextFound }

        return ImportOutcome(
            csvFile: StatementInterpreter.csvFile(from: statement),
            statement: statement,
            intelligenceStatus: IntelligenceAvailability.status
        )
    }

    /// A statement page can hold several tables (account summary, fees,
    /// transactions). The transaction table is the one with the most rows that
    /// also resolves to a usable set of roles.
    private static func bestTable(in snapshot: DocumentSnapshot) -> DocumentSnapshot.Table? {
        snapshot.allTables
            .filter { ColumnRoleResolver.resolve(table: $0)?.hasAmountSignal == true }
            .max { $0.rows.count < $1.rows.count }
            ?? snapshot.allTables.max { $0.rows.count < $1.rows.count }
    }
}
```

- [ ] **Step 2: Replace PDFService with a page renderer**

Replace the entire contents of `Tenra/Services/Import/PDFService.swift` with:

```swift
//
//  PDFService.swift
//  Tenra
//
//  Page rasterisation only. Extraction moved to VisionDocumentExtractor /
//  PDFTextLayerExtractor; orchestration moved to DocumentImportService.
//

import Foundation
import PDFKit
import UIKit

nonisolated enum PDFService {

    /// Renders each page to a CGImage for OCR.
    ///
    /// `scale` 3.5 puts an A4 page at roughly 250 dpi. The previous 2.0 gave
    /// about 144 dpi, below what small statement type needs.
    static func renderPages(
        of document: PDFDocument,
        scale: CGFloat,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> [CGImage] {
        var images: [CGImage] = []
        let pageCount = document.pageCount

        for pageIndex in 0..<pageCount {
            progress?(pageIndex + 1, pageCount)
            guard let page = document.page(at: pageIndex) else { continue }

            let pageRect = page.bounds(for: .mediaBox)
            let size = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            let renderer = UIGraphicsImageRenderer(size: size)

            let image = renderer.image { context in
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: size.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
            if let cgImage = image.cgImage { images.append(cgImage) }
        }
        return images
    }
}

enum PDFError: LocalizedError {
    case invalidDocument
    case noTextFound
    case unsupportedFormat
    case ocrError(String)

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return String(localized: "pdf.error.invalidDocument")
        case .noTextFound:
            return String(localized: "pdf.error.noTextFound")
        case .unsupportedFormat:
            return String(localized: "pdf.error.unsupportedFormat")
        case .ocrError(let message):
            return String(localized: "pdf.error.ocr \(message)")
        }
    }
}
```

- [ ] **Step 3: Update the call site in PDFImportCoordinator**

In `Tenra/Views/Import/PDFImportCoordinator.swift`, replace the body of `analyzePDF(url:)` (currently calling `PDFService.shared.extractText`) with:

```swift
    private func analyzePDF(url: URL) async {
        ocrProgress = nil
        do {
            let baseCurrency = transactionsViewModel.baseCurrency
            let outcome = try await DocumentImportService.importStatement(
                from: url,
                defaultCurrency: baseCurrency
            ) { current, total in
                Task { @MainActor in
                    ocrProgress = (current: current, total: total)
                }
            }
            importOutcome = outcome
            parsedCSVFile = outcome.csvFile
            showingCSVPreview = true
        } catch {
            importError = error.localizedDescription
        }
        ocrProgress = nil
    }
```

Add the supporting state near the other `@State` declarations (around `PDFImportCoordinator.swift:20-26`):

```swift
    @State private var importOutcome: ImportOutcome? = nil
    @State private var importError: String? = nil
```

Then remove the now-unused `recognizedText`, `structuredRows`, and `showingRecognizedText` state and the `recognizedTextSheet` they feed, along with the `.sheet(isPresented: $showingRecognizedText)` modifier.

Confirm the base-currency property name before writing it:

```bash
grep -rn "var baseCurrency" --include="*.swift" Tenra/ViewModels | head -5
```
Use whatever name that returns. If `TransactionsViewModel` does not expose it, read it from the settings service the same way another view model does.

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output. Fix any reference to the deleted `PDFService.shared`, `OCRResult`, `TextObservation`, or `PDFTextBlock` types by removing it.

- [ ] **Step 5: Run the full test target**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -aE "Test case .* failed|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: `** TEST SUCCEEDED **`. A single `** TEST FAILED **` with zero failing test-case lines is a known harness flake; re-run once.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Services/Import/DocumentImportService.swift Tenra/Services/Import/PDFService.swift Tenra/Views/Import/PDFImportCoordinator.swift
git commit -m "refactor(import): route statement import through DocumentImportService"
```

---

### Task 10: Receipt scanning (camera + interpretation)

The app currently has no receipt path at all: `DocumentPicker` defaults to `[.pdf]` (`DocumentPicker.swift:16`) and nothing opens a camera. This task adds one.

**Files:**
- Create: `Tenra/Views/Import/DocumentScannerView.swift`
- Create: `Tenra/Services/Import/ReceiptInterpreter.swift`
- Modify: `Tenra/Info.plist`
- Test: `TenraTests/Services/Import/ReceiptInterpreterTests.swift`

**Interfaces:**
- Consumes: `DocumentSnapshot` (Task 1), `MoneyTokenParser` (Task 3), `DateTokenParser` (Task 2), `IntelligenceAvailability` (Task 8).
- Produces: `DocumentScannerView` (SwiftUI view with `onScan: ([CGImage]) -> Void` and `onCancel: () -> Void`), `ReceiptDraft` (`merchant: String`, `total: Double`, `currency: String?`, `date: String?`), `ReceiptInterpreter.interpret(snapshot:defaultCurrency:) async -> ReceiptDraft?`, `ReceiptInterpreter.heuristicDraft(snapshot:defaultCurrency:) -> ReceiptDraft?`.

- [ ] **Step 1: Write the failing test for the deterministic path**

Create `TenraTests/Services/Import/ReceiptInterpreterTests.swift`:

```swift
//
//  ReceiptInterpreterTests.swift
//  TenraTests
//
//  Pins the deterministic receipt fallback. The Apple Intelligence path cannot
//  be unit-tested (it needs an eligible device and a downloaded model), so the
//  heuristic path is the one that must be provably correct.
//

import Testing
@testable import Tenra

struct ReceiptInterpreterTests {

    private func receipt(_ lines: [String]) -> DocumentSnapshot {
        DocumentSnapshot(
            pages: [.init(index: 0, tables: [], lines: lines, barcodes: [])],
            hadTextLayer: false
        )
    }

    @Test("total is taken from the line labelled as total")
    func totalFromLabel() {
        let snapshot = receipt([
            "MAGNUM CASH & CARRY",
            "Milk 1L            450",
            "Bread              320",
            "Subtotal           770",
            "TOTAL            2 500",
            "08.01.2026 17:19"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.total == 2500)
        #expect(draft?.date == "2026-01-08")
    }

    @Test("merchant is the first substantial non-numeric line")
    func merchantFromFirstLine() {
        let snapshot = receipt([
            "MAGNUM CASH & CARRY",
            "TOTAL            2 500"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "KZT")
        #expect(draft?.merchant == "MAGNUM CASH & CARRY")
    }

    @Test("without a total label the largest amount wins")
    func largestAmountFallback() {
        let snapshot = receipt([
            "CAFE",
            "Espresso   1 200",
            "Cake       2 400",
            "3 600"
        ])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "EUR")
        #expect(draft?.total == 3600)
    }

    @Test("a receipt with no amount yields nil")
    func noAmount() {
        let snapshot = receipt(["THANK YOU", "COME AGAIN"])
        #expect(ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "EUR") == nil)
    }

    @Test("currency from the receipt overrides the default")
    func currencyFromReceipt() {
        let snapshot = receipt(["CAFE", "TOTAL  12,50 €"])
        let draft = ReceiptInterpreter.heuristicDraft(snapshot: snapshot, defaultCurrency: "USD")
        #expect(draft?.currency == "EUR")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/ReceiptInterpreterTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: compile error, `cannot find 'ReceiptInterpreter' in scope`.

- [ ] **Step 3: Write the receipt interpreter**

Create `Tenra/Services/Import/ReceiptInterpreter.swift`:

```swift
//
//  ReceiptInterpreter.swift
//  Tenra
//
//  Receipts are the case where Apple Intelligence direct extraction is the
//  right tool: the payload is tiny (one merchant, one total, one date), the
//  layout is wildly inconsistent across the world, and the whole receipt fits
//  comfortably in the model's context window.
//
//  The heuristic path below is the guaranteed floor for the roughly half of
//  the install base without Apple Intelligence.
//

import Foundation
import FoundationModels

struct ReceiptDraft: Sendable, Equatable {
    let merchant: String
    let total: Double
    let currency: String?
    /// Canonical "yyyy-MM-dd", nil when the receipt showed no date.
    let date: String?
}

/// Structured output schema for the Apple Intelligence path.
@Generable
struct ExtractedReceipt {
    @Guide(description: "The shop or restaurant name printed on the receipt, without address or tax identifiers.")
    var merchant: String

    @Guide(description: "The final total paid, as a positive number. Not the subtotal, not the tax, not the cash tendered.")
    var total: Double

    @Guide(description: "ISO 4217 currency code such as USD, EUR, KZT. Empty string if the receipt shows none.")
    var currency: String

    @Guide(description: "Purchase date as yyyy-MM-dd. Empty string if the receipt shows none.")
    var date: String
}

nonisolated struct ReceiptInterpreter {

    private static let instructions = """
    You read the raw text of a shop receipt and report the merchant name, the \
    final total paid, the currency, and the purchase date. You copy values \
    exactly as printed. You never estimate or compute a total that is not \
    printed on the receipt. If a field is not present, you report an empty \
    string for it.
    """

    /// Apple Intelligence first, deterministic heuristics as the fallback.
    static func interpret(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) async -> ReceiptDraft? {
        if IntelligenceAvailability.isAvailable,
           let draft = await intelligentDraft(snapshot: snapshot, defaultCurrency: defaultCurrency) {
            return draft
        }
        return heuristicDraft(snapshot: snapshot, defaultCurrency: defaultCurrency)
    }

    // MARK: - Apple Intelligence path

    private static func intelligentDraft(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) async -> ReceiptDraft? {
        let text = snapshot.plainText
        guard !text.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Receipt text:\n\n\(text)",
                generating: ExtractedReceipt.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let extracted = response.content
            guard extracted.total > 0 else { return nil }

            return ReceiptDraft(
                merchant: extracted.merchant.trimmingCharacters(in: .whitespacesAndNewlines),
                total: extracted.total,
                currency: extracted.currency.isEmpty ? defaultCurrency : extracted.currency,
                date: extracted.date.isEmpty ? nil : DateTokenParser.parse(extracted.date)
            )
        } catch {
            return nil
        }
    }

    // MARK: - Deterministic path

    /// Total-line keywords in the 11 shipped locales, lowercased.
    private static let totalKeywords = [
        "total", "итого", "всего", "к оплате", "сумма", "gesamt", "summe",
        "gesamtbetrag", "total a pagar", "importe total", "montant total",
        "totale", "toplam", "genel toplam", "合計", "합계", "총액", "valor total"
    ]

    /// Lines that carry an amount but are never the final total.
    private static let excludedKeywords = [
        "subtotal", "подытог", "промежуточн", "zwischensumme", "sous-total",
        "subtotale", "ara toplam", "tax", "vat", "ндс", "мwst", "iva", "tva",
        "kdv", "change", "сдача", "rückgeld", "cambio", "monnaie", "tip", "чаевые"
    ]

    static func heuristicDraft(
        snapshot: DocumentSnapshot,
        defaultCurrency: String
    ) -> ReceiptDraft? {
        let lines = snapshot.allLines.filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let total = totalFromLabelledLine(lines) ?? largestAmount(lines)
        guard let total else { return nil }

        return ReceiptDraft(
            merchant: merchant(from: lines),
            total: total.amount,
            currency: total.currency ?? defaultCurrency,
            date: lines.compactMap(DateTokenParser.parse).first
        )
    }

    private static func totalFromLabelledLine(
        _ lines: [String]
    ) -> MoneyTokenParser.ParsedMoney? {
        // Search from the bottom: the final total is the last one printed.
        for line in lines.reversed() {
            let lowered = line.lowercased()
            guard totalKeywords.contains(where: { lowered.contains($0) }) else { continue }
            guard !excludedKeywords.contains(where: { lowered.contains($0) }) else { continue }
            if let money = lastAmount(in: line), money.amount > 0 { return money }
        }
        return nil
    }

    private static func largestAmount(_ lines: [String]) -> MoneyTokenParser.ParsedMoney? {
        lines
            .filter { line in
                let lowered = line.lowercased()
                return !excludedKeywords.contains { lowered.contains($0) }
            }
            .compactMap(lastAmount(in:))
            .max { $0.amount < $1.amount }
    }

    /// The amount on a receipt line is the rightmost number, since the label
    /// sits on the left.
    private static func lastAmount(in line: String) -> MoneyTokenParser.ParsedMoney? {
        let tokens = line.split(separator: " ").map(String.init)
        for token in tokens.reversed() {
            if let money = MoneyTokenParser.parse(token), money.amount > 0 { return money }
        }
        // Fall back to parsing the whole line, which catches "TOTAL 2 500"
        // where the amount itself contains a grouping space.
        return MoneyTokenParser.parse(line)
    }

    private static func merchant(from lines: [String]) -> String {
        // The shop name is printed at the top, above any amount or date.
        for line in lines.prefix(5) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3 else { continue }
            guard !MoneyTokenParser.looksLikeMoney(trimmed) else { continue }
            guard !DateTokenParser.looksLikeDate(trimmed) else { continue }
            guard trimmed.contains(where: \.isLetter) else { continue }
            return trimmed
        }
        return lines.first ?? ""
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/ReceiptInterpreterTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: 5 tests passed, `** TEST SUCCEEDED **`.

- [ ] **Step 5: Add the camera usage description**

In `Tenra/Info.plist`, next to the existing `NSMicrophoneUsageDescription` at line 45, add:

```xml
	<key>NSCameraUsageDescription</key>
	<string>Tenra uses the camera to scan paper receipts so you do not have to type them in by hand.</string>
```

- [ ] **Step 6: Write the scanner view**

Create `Tenra/Views/Import/DocumentScannerView.swift`:

```swift
//
//  DocumentScannerView.swift
//  Tenra
//
//  VisionKit document camera. It handles edge detection, perspective
//  correction, and multi-page capture for us, which is exactly the
//  preprocessing OCR quality depends on most.
//

import SwiftUI
import VisionKit
import CoreGraphics

struct DocumentScannerView: UIViewControllerRepresentable {
    let onScan: ([CGImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController,
                                context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan, onCancel: onCancel)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        private let onScan: ([CGImage]) -> Void
        private let onCancel: () -> Void

        init(onScan: @escaping ([CGImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onScan = onScan
            self.onCancel = onCancel
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            var images: [CGImage] = []
            for pageIndex in 0..<scan.pageCount {
                if let cgImage = scan.imageOfPage(at: pageIndex).cgImage {
                    images.append(cgImage)
                }
            }
            onScan(images)
        }

        func documentCameraViewControllerDidCancel(
            _ controller: VNDocumentCameraViewController
        ) {
            onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: any Error
        ) {
            onCancel()
        }
    }
}
```

- [ ] **Step 7: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output.

- [ ] **Step 8: Commit**

```bash
git add Tenra/Services/Import/ReceiptInterpreter.swift Tenra/Views/Import/DocumentScannerView.swift Tenra/Info.plist TenraTests/Services/Import/ReceiptInterpreterTests.swift
git commit -m "feat(import): add receipt scanning with VisionKit camera and receipt interpretation"
```

---

### Task 11: Import source picker and diagnostics UI

Makes both new capabilities reachable and makes skipped rows visible.

**Files:**
- Create: `Tenra/Views/Import/ImportSourcePicker.swift`
- Create: `Tenra/Views/Import/ImportDiagnosticsView.swift`
- Modify: `Tenra/Views/Import/PDFImportCoordinator.swift`

**Interfaces:**
- Consumes: `DocumentScannerView` (Task 10), `ReceiptInterpreter` (Task 10), `DocumentImportService` / `ImportOutcome` (Task 9), `ParsedStatement` / `SkippedRow` (Task 5).
- Produces: `ImportSourcePicker` (`onPickPDF: () -> Void`, `onScanReceipt: () -> Void`), `ImportDiagnosticsView(statement: ParsedStatement, intelligenceStatus: IntelligenceStatus)`.

- [ ] **Step 1: Write the source picker**

Create `Tenra/Views/Import/ImportSourcePicker.swift`:

```swift
//
//  ImportSourcePicker.swift
//  Tenra
//
//  Two entry points for the Import tab: a PDF statement, or a paper receipt.
//  Reuses FinanceCard and the shared row components rather than hand-rolling
//  card shells (see docs/design-system.md).
//

import SwiftUI

struct ImportSourcePicker: View {
    let onPickPDF: () -> Void
    let onScanReceipt: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            sourceButton(
                icon: "doc.text.viewfinder",
                title: String(localized: "import.source.statement.title"),
                subtitle: String(localized: "import.source.statement.subtitle"),
                action: onPickPDF
            )

            sourceButton(
                icon: "camera.viewfinder",
                title: String(localized: "import.source.receipt.title"),
                subtitle: String(localized: "import.source.receipt.subtitle"),
                action: onScanReceipt
            )
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private func sourceButton(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.light()
            action()
        } label: {
            HStack(spacing: AppSpacing.md) {
                IconView(
                    source: .system(icon),
                    style: .circle(size: .xxl,
                                   tint: .monochrome(AppColors.accent),
                                   backgroundColor: AppColors.accent.opacity(0.15))
                )

                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title)
                        .font(AppTypography.bodyMedium)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: AppIconSize.sm, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .cardStyle()
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}
```

Verify the exact `IconView` style API and `cardStyle()` availability before building:

```bash
grep -rn "static func circle\|case system" --include="*.swift" Tenra/Views/Components/Icons/ | head -10
```
Adjust the call to match the real signatures.

- [ ] **Step 2: Write the diagnostics view**

Create `Tenra/Views/Import/ImportDiagnosticsView.swift`:

```swift
//
//  ImportDiagnosticsView.swift
//  Tenra
//
//  Makes skipped rows visible. The previous importer silently discarded any
//  row it could not parse, so a user could import 20 of 60 operations and never
//  find out. Everything the parser rejected is listed here with its reason.
//

import SwiftUI

struct ImportDiagnosticsView: View {
    let statement: ParsedStatement
    let intelligenceStatus: IntelligenceStatus

    var body: some View {
        List {
            Section {
                LabeledContent(
                    String(localized: "import.diagnostics.recognized"),
                    value: "\(statement.transactions.count)"
                )
                LabeledContent(
                    String(localized: "import.diagnostics.skipped"),
                    value: "\(statement.skipped.count)"
                )
            }

            if let explanationKey = intelligenceStatus.explanationKey {
                Section {
                    Text(String(localized: String.LocalizationValue(explanationKey)))
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !statement.skipped.isEmpty {
                Section(String(localized: "import.diagnostics.skippedRows")) {
                    ForEach(statement.skipped, id: \.rowIndex) { row in
                        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                            Text(row.cells.filter { !$0.isEmpty }.joined(separator: "  "))
                                .font(AppTypography.caption)
                                .lineLimit(2)
                            Text(String(localized: String.LocalizationValue(row.reason)))
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "import.diagnostics.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 3: Wire both into PDFImportCoordinator**

In `Tenra/Views/Import/PDFImportCoordinator.swift`, replace `importButton` with `ImportSourcePicker`, add scanner and diagnostics state, and add the receipt handler:

```swift
    @State private var showingScanner = false
    @State private var showingDiagnostics = false
    @State private var receiptDraft: ReceiptDraft? = nil
```

Replace the `importButton` computed property with:

```swift
    private var sourcePicker: some View {
        ImportSourcePicker(
            onPickPDF: { showingFilePicker = true },
            onScanReceipt: { showingScanner = true }
        )
    }
```

Add these modifiers to `body`:

```swift
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScannerView(
                    onScan: { images in
                        showingScanner = false
                        Task { await analyzeReceipt(images: images) }
                    },
                    onCancel: { showingScanner = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingDiagnostics) {
                if let outcome = importOutcome {
                    NavigationStack {
                        ImportDiagnosticsView(
                            statement: outcome.statement,
                            intelligenceStatus: outcome.intelligenceStatus
                        )
                    }
                }
            }
```

And add the receipt handler next to `analyzePDF(url:)`:

```swift
    private func analyzeReceipt(images: [CGImage]) async {
        do {
            let snapshot = try await VisionDocumentExtractor.extract(images: images)
            let baseCurrency = transactionsViewModel.baseCurrency
            receiptDraft = await ReceiptInterpreter.interpret(
                snapshot: snapshot,
                defaultCurrency: baseCurrency
            )
            if receiptDraft == nil {
                importError = String(localized: "import.error.receiptNotRecognized")
            }
        } catch {
            importError = error.localizedDescription
        }
    }
```

Present `receiptDraft` through the app's existing add-transaction sheet, prefilled with `merchant`, `total`, `currency`, and `date`. Find the correct entry point first:

```bash
grep -rn "struct AddTransactionView\|struct TransactionEditView" --include="*.swift" Tenra/Views/Transactions | head -5
```
Use that view's initializer, passing the draft values as its prefill parameters. Money shown in that sheet must go through `FormattedAmountText` or `InfoRow(... amount: currency:)`, never a raw interpolation.

- [ ] **Step 4: Update OCRTab**

In `Tenra/Views/Home/TabViews.swift`, the `PDFImportCoordinator(...)` call at line 152 now renders the source picker itself. Change the surrounding copy so the tab no longer says "import a PDF statement" exclusively: replace the `Text(String(localized: "accessibility.importStatementHint"))` subtitle with `Text(String(localized: "import.tab.subtitle"))`.

- [ ] **Step 5: Build to verify it compiles**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add Tenra/Views/Import/ImportSourcePicker.swift Tenra/Views/Import/ImportDiagnosticsView.swift Tenra/Views/Import/PDFImportCoordinator.swift Tenra/Views/Home/TabViews.swift
git commit -m "feat(import): add import source picker and skipped-row diagnostics UI"
```

---

### Task 12: Localization, legacy removal, and documentation

**Files:**
- Create: `docs/domains/import.md`
- Modify: `Tenra/*.lproj/Localizable.strings` (11 files)
- Modify: `CLAUDE.md` (trigger table row)
- Delete: `Tenra/Services/Import/StatementTextParser.swift`

**Interfaces:**
- Consumes: every localization key referenced in Tasks 6, 8, 10, 11.
- Produces: nothing consumed by code.

The complete set of new keys:

| Key | English value |
|---|---|
| `import.source.statement.title` | `Bank statement` |
| `import.source.statement.subtitle` | `Import a PDF statement from your bank` |
| `import.source.receipt.title` | `Scan a receipt` |
| `import.source.receipt.subtitle` | `Point the camera at a paper receipt` |
| `import.tab.subtitle` | `Add transactions from a statement or a receipt instead of typing them in` |
| `import.diagnostics.title` | `Import report` |
| `import.diagnostics.recognized` | `Recognized` |
| `import.diagnostics.skipped` | `Skipped` |
| `import.diagnostics.skippedRows` | `Skipped rows` |
| `import.skip.noDate` | `No date found in this row` |
| `import.skip.noAmount` | `No amount found in this row` |
| `import.error.noContentRecognized` | `Nothing could be recognized in this document` |
| `import.error.receiptNotRecognized` | `Could not read a total from this receipt. Try again with better lighting.` |
| `import.intelligence.deviceNotEligible` | `This iPhone does not support Apple Intelligence, so unfamiliar statement layouts may need manual column mapping.` |
| `import.intelligence.notEnabled` | `Turn on Apple Intelligence in Settings to recognize unfamiliar statement layouts automatically.` |
| `import.intelligence.modelNotReady` | `Apple Intelligence is still downloading. Recognition will improve once it finishes.` |

- [ ] **Step 1: Write the key-insertion script**

Create `/private/tmp/claude-501/-Users-dauletkydrali-Documents-GitHub-Tenra/scratchpad/add_import_keys.py`:

```python
import io
import os

BASE = "Tenra"

# Translations per locale. No em dashes anywhere (see CLAUDE.md Don't list).
TRANSLATIONS = {
    "en": {
        "import.source.statement.title": "Bank statement",
        "import.source.statement.subtitle": "Import a PDF statement from your bank",
        "import.source.receipt.title": "Scan a receipt",
        "import.source.receipt.subtitle": "Point the camera at a paper receipt",
        "import.tab.subtitle": "Add transactions from a statement or a receipt instead of typing them in",
        "import.diagnostics.title": "Import report",
        "import.diagnostics.recognized": "Recognized",
        "import.diagnostics.skipped": "Skipped",
        "import.diagnostics.skippedRows": "Skipped rows",
        "import.skip.noDate": "No date found in this row",
        "import.skip.noAmount": "No amount found in this row",
        "import.error.noContentRecognized": "Nothing could be recognized in this document",
        "import.error.receiptNotRecognized": "Could not read a total from this receipt. Try again with better lighting.",
        "import.intelligence.deviceNotEligible": "This iPhone does not support Apple Intelligence, so unfamiliar statement layouts may need manual column mapping.",
        "import.intelligence.notEnabled": "Turn on Apple Intelligence in Settings to recognize unfamiliar statement layouts automatically.",
        "import.intelligence.modelNotReady": "Apple Intelligence is still downloading. Recognition will improve once it finishes.",
    },
    "ru": {
        "import.source.statement.title": "Банковская выписка",
        "import.source.statement.subtitle": "Импортируйте PDF-выписку из банка",
        "import.source.receipt.title": "Сканировать чек",
        "import.source.receipt.subtitle": "Наведите камеру на бумажный чек",
        "import.tab.subtitle": "Добавляйте операции из выписки или чека, не вводя их вручную",
        "import.diagnostics.title": "Отчёт об импорте",
        "import.diagnostics.recognized": "Распознано",
        "import.diagnostics.skipped": "Пропущено",
        "import.diagnostics.skippedRows": "Пропущенные строки",
        "import.skip.noDate": "В строке не найдена дата",
        "import.skip.noAmount": "В строке не найдена сумма",
        "import.error.noContentRecognized": "В этом документе ничего не распознано",
        "import.error.receiptNotRecognized": "Не удалось прочитать итог на чеке. Попробуйте при лучшем освещении.",
        "import.intelligence.deviceNotEligible": "Этот iPhone не поддерживает Apple Intelligence, поэтому незнакомые форматы выписок могут потребовать ручной разметки колонок.",
        "import.intelligence.notEnabled": "Включите Apple Intelligence в Настройках, чтобы незнакомые форматы выписок распознавались автоматически.",
        "import.intelligence.modelNotReady": "Apple Intelligence ещё загружается. Распознавание улучшится после завершения.",
    },
    # The implementing engineer fills in de, es, fr, tr, pt-BR, it, uk, ja, ko
    # with the same key set. Rules: no em dashes; keep any format specifiers in
    # the same order as English, or switch the whole string to positional
    # specifiers (see CLAUDE.md Red Flag #14). None of these keys take
    # arguments, so plain text is fine.
}

for locale, entries in TRANSLATIONS.items():
    path = os.path.join(BASE, "%s.lproj" % locale, "Localizable.strings")
    with io.open(path, "r", encoding="utf-8") as handle:
        content = handle.read()

    additions = []
    for key, value in entries.items():
        if '"%s"' % key in content:
            continue
        escaped = value.replace('"', '\\"')
        additions.append('"%s" = "%s";' % (key, escaped))

    if not additions:
        print("%s: nothing to add" % locale)
        continue

    with io.open(path, "a", encoding="utf-8") as handle:
        handle.write("\n\n/* MARK: - Document import */\n")
        handle.write("\n".join(additions))
        handle.write("\n")
    print("%s: added %d keys" % (locale, len(additions)))
```

- [ ] **Step 2: Fill in the nine remaining locales, then run the script**

Add `de`, `es`, `fr`, `tr`, `pt-BR`, `it`, `uk`, `ja`, `ko` blocks to `TRANSLATIONS` with the same 16 keys, then:

```bash
cd /Users/dauletkydrali/Documents/GitHub/Tenra && python3 /private/tmp/claude-501/-Users-dauletkydrali-Documents-GitHub-Tenra/scratchpad/add_import_keys.py
```
Expected: 11 lines, each reading `<locale>: added 16 keys`.

- [ ] **Step 3: Verify key parity across all locales**

Run:
```bash
cd /Users/dauletkydrali/Documents/GitHub/Tenra && for L in ru de es fr tr pt-BR it uk ja ko; do echo "--- $L ---"; diff <(grep -oE '^"[^"]+"' Tenra/en.lproj/Localizable.strings | sort) <(grep -oE '^"[^"]+"' Tenra/$L.lproj/Localizable.strings | sort); done
```
Expected: each `--- <locale> ---` header followed by no diff output.

- [ ] **Step 4: Verify non-ASCII locales did not get mojibake**

Run:
```bash
cd /Users/dauletkydrali/Documents/GitHub/Tenra && grep -A1 "import.source.receipt.title" Tenra/ru.lproj/Localizable.strings Tenra/ja.lproj/Localizable.strings
```
Expected: readable Cyrillic and Japanese, not `Ð¡ÐºÐ°Ð½` style bytes.

- [ ] **Step 5: Verify no em dashes were introduced**

Run:
```bash
cd /Users/dauletkydrali/Documents/GitHub/Tenra && grep -n "—" Tenra/*.lproj/Localizable.strings | grep "import\." | head
```
Expected: no output.

- [ ] **Step 6: Delete the legacy parser**

Run:
```bash
cd /Users/dauletkydrali/Documents/GitHub/Tenra && grep -rn "StatementTextParser" --include="*.swift" Tenra TenraTests
```
Expected: no output. If anything still references it, remove that reference first. Then:

```bash
rm Tenra/Services/Import/StatementTextParser.swift
```

- [ ] **Step 7: Write the domain doc**

Create `docs/domains/import.md`:

```markdown
# Document Import

Bank statements (PDF) and paper receipts (camera) both land in the same
three-stage pipeline. Read this before touching anything in
`Tenra/Services/Import/`.

## Pipeline

| Stage | Types | Notes |
|---|---|---|
| Acquisition | `DocumentPicker`, `DocumentScannerView` | PDF file or VisionKit camera scan. |
| Extraction | `PDFTextLayerExtractor`, `VisionDocumentExtractor` | Both produce `DocumentSnapshot`. Text-layer PDFs skip OCR entirely. |
| Interpretation | `ColumnRoleResolver`, `IntelligentColumnRoleResolver`, `StatementInterpreter`, `ReceiptInterpreter` | Consume only `DocumentSnapshot`. |

`DocumentImportService` is the single orchestrator. `PDFService` is now only a
page rasteriser.

## Rules

1. **`DocumentSnapshot` is the seam.** Nothing in interpretation may import
   Vision, PDFKit, or UIKit. This is what makes the parsers unit-testable.
2. **Apple Intelligence is never required.** Every path must produce a result
   when `IntelligenceAvailability.status` is not `.available`. Roughly half the
   install base has no Apple Intelligence.
3. **Apple Intelligence infers layout, not values, for statements.** It receives
   the header plus two sample rows and returns column indices. All amounts are
   then parsed deterministically. Do not switch to per-row LLM extraction: a
   200-row statement exceeds the context window, and a model re-typing amounts
   can corrupt them.
4. **Receipts are the opposite case.** The payload is small and layouts vary
   wildly, so `ReceiptInterpreter` asks the model for the values directly, with
   `heuristicDraft` as the guaranteed floor.
5. **Never drop a row silently.** Anything the interpreter cannot use goes into
   `ParsedStatement.skipped` with a localized reason and is shown in
   `ImportDiagnosticsView`.
6. **No hardcoded bank, currency, or date format.** `ColumnRoleResolver`,
   `DateTokenParser`, and `MoneyTokenParser` carry every format assumption, and
   each is pinned by tests. Supporting a new bank means adding a test case
   there, not a branch elsewhere.
7. **`useLanguageCorrection` stays off.** Statement and receipt content is
   mostly numbers, merchant names, and reference codes; language correction
   silently rewrites them.

## Tests

`TenraTests/Services/Import/` covers `DateTokenParser`, `MoneyTokenParser`,
`ColumnRoleResolver`, `StatementInterpreter`, and `ReceiptInterpreter`'s
deterministic path. The Vision and Apple Intelligence paths are not unit
testable (device and model dependent); they are covered by the fact that both
degrade into the tested deterministic paths.
```

- [ ] **Step 8: Add the doc to the CLAUDE.md trigger table**

In `CLAUDE.md`, in the "When to Read Which Doc" table, add after the `domains/csv.md` row:

```markdown
| `Services/Import/**`, statement/receipt recognition, Vision documents, Apple Intelligence parsing | [domains/import.md](docs/domains/import.md) |
```

And add to the "Reference Docs Index" table:

```markdown
| [domains/import.md](docs/domains/import.md) | Statement + receipt recognition pipeline, DocumentSnapshot seam, Apple Intelligence policy |
```

- [ ] **Step 9: Full build and test**

Run:
```bash
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | grep -E "error:" | head -30
```
Expected: no output.

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -aE "Test case .* failed|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: `** TEST SUCCEEDED **` with no failing test-case lines.

- [ ] **Step 10: Commit**

```bash
git add Tenra/*.lproj/Localizable.strings docs/domains/import.md CLAUDE.md
git rm Tenra/Services/Import/StatementTextParser.swift
git commit -m "feat(import): localize import strings, remove legacy StatementTextParser, document the pipeline"
```

---

### Task 13: Column-level date order detection

**Execute this immediately after Task 5, before Task 6.** It resolves a defect found during Task 2: `DD/MM/YYYY` and `MM/DD/YYYY` are indistinguishable per token, so a US statement's `01/08/2026` (8 January) was silently read as 1 August. A single token cannot be disambiguated, but a whole column can: if any token in the column has a first component above 12 the column is day-first, and if any has a second component above 12 it is month-first.

**Files:**
- Create: `Tenra/Services/Import/DateOrderDetector.swift`
- Modify: `Tenra/Services/Import/DateTokenParser.swift`
- Modify: `Tenra/Services/Import/StatementInterpreter.swift`
- Test: `TenraTests/Services/Import/DateOrderDetectorTests.swift`
- Test: `TenraTests/Services/Import/DateTokenParserTests.swift` (add cases)

**Interfaces:**
- Consumes: `DateTokenParser` (Task 2), `ColumnRoles` (Task 4), `StatementInterpreter` (Task 5), `DocumentSnapshot` (Task 1).
- Produces: `DateOrder` enum (`.dayFirst`, `.monthFirst`), `DateOrderDetector.detect(tokens: [String]) -> DateOrder`, `DateTokenParser.parse(_ token: String, order: DateOrder) -> String?`, and an order-agnostic `DateTokenParser.looksLikeDate(_ token: String) -> Bool`.

Three behaviours must hold together, so read all three before writing code:

1. `looksLikeDate` becomes **order-agnostic**: it returns true when the token is a valid date under *either* order. Without this, `ColumnRoleResolver` (Task 4) scores a US date column below its 0.6 threshold and never identifies it as the date column at all.
2. `parse(_:)` without an order keeps its current day-first behaviour, so every existing Task 2 test stays green and unchanged.
3. `parse(_:order:)` applies the given order, falling back to the other order only when the given one yields no valid date.

- [ ] **Step 1: Write the failing tests**

Create `TenraTests/Services/Import/DateOrderDetectorTests.swift`:

```swift
//
//  DateOrderDetectorTests.swift
//  TenraTests
//
//  A single token cannot tell DD/MM from MM/DD. A column can: one token with a
//  component above 12 pins the order for every other token in that column.
//

import Testing
@testable import Tenra

struct DateOrderDetectorTests {

    @Test("a day above 12 anywhere in the column pins day-first")
    func dayFirstEvidence() {
        let tokens = ["01/08/2026", "13/08/2026", "05/09/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .dayFirst)
    }

    @Test("a month position above 12 anywhere in the column pins month-first")
    func monthFirstEvidence() {
        let tokens = ["01/08/2026", "01/25/2026", "02/03/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .monthFirst)
    }

    @Test("a fully ambiguous column defaults to day-first")
    func ambiguousDefaultsToDayFirst() {
        let tokens = ["01/08/2026", "02/09/2026", "03/10/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .dayFirst)
    }

    @Test("ISO tokens carry no ambiguity and do not sway the verdict")
    func isoTokensIgnored() {
        let tokens = ["2026-01-08", "2026-08-13", "01/25/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .monthFirst)
    }

    @Test("conflicting evidence favours day-first, the dominant world convention")
    func conflictingEvidence() {
        // A column cannot really be both. Real cause is OCR noise, so prefer
        // the convention used by more of the app's markets rather than
        // rejecting the whole column.
        let tokens = ["13/08/2026", "01/25/2026"]
        #expect(DateOrderDetector.detect(tokens: tokens) == .dayFirst)
    }

    @Test("an empty or dateless column defaults to day-first")
    func noDates() {
        #expect(DateOrderDetector.detect(tokens: []) == .dayFirst)
        #expect(DateOrderDetector.detect(tokens: ["Purchase", "Total"]) == .dayFirst)
    }
}
```

Append these cases to the existing `DateTokenParserTests` struct in `TenraTests/Services/Import/DateTokenParserTests.swift`. Do not modify any existing case in that file:

```swift
    @Test("looksLikeDate is order-agnostic so US date columns are still detected")
    func looksLikeDateIsOrderAgnostic() {
        // Invalid day-first, valid month-first. ColumnRoleResolver must still
        // count this cell towards the date-column score.
        #expect(DateTokenParser.looksLikeDate("08.13.2026"))
        #expect(DateTokenParser.looksLikeDate("12/25/2026"))
        // Valid under neither order.
        #expect(!DateTokenParser.looksLikeDate("13/25/2026"))
        #expect(!DateTokenParser.looksLikeDate("YANDEX.GO"))
    }

    @Test("explicit month-first order reads US dates correctly")
    func explicitMonthFirst() {
        #expect(DateTokenParser.parse("01/08/2026", order: .monthFirst) == "2026-01-08")
        #expect(DateTokenParser.parse("12/25/2026", order: .monthFirst) == "2026-12-25")
    }

    @Test("explicit day-first order reads EU dates correctly")
    func explicitDayFirst() {
        #expect(DateTokenParser.parse("01/08/2026", order: .dayFirst) == "2026-08-01")
        #expect(DateTokenParser.parse("13/08/2026", order: .dayFirst) == "2026-08-13")
    }

    @Test("an explicit order falls back to the other order when its own reading is invalid")
    func explicitOrderFallsBack() {
        // Told month-first, but 25 is not a month, so day-first is the only
        // valid reading. Better a correct date than a dropped row.
        #expect(DateTokenParser.parse("25/12/2026", order: .monthFirst) == "2026-12-25")
    }

    @Test("ISO tokens ignore the order parameter")
    func isoIgnoresOrder() {
        #expect(DateTokenParser.parse("2026-01-08", order: .monthFirst) == "2026-01-08")
        #expect(DateTokenParser.parse("2026-01-08", order: .dayFirst) == "2026-01-08")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/DateOrderDetectorTests 2>&1 | grep -aE "error:|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: compile error, `cannot find 'DateOrderDetector' in scope`.

- [ ] **Step 3: Create DateOrderDetector**

Create `Tenra/Services/Import/DateOrderDetector.swift`:

```swift
//
//  DateOrderDetector.swift
//  Tenra
//
//  "01/08/2026" is 8 January on a US statement and 1 August on a European one.
//  No amount of cleverness resolves that from one token. A column resolves it:
//  a single "13/08/2026" proves the column is day-first, a single "01/25/2026"
//  proves it is month-first.
//

import Foundation

enum DateOrder: Sendable, Equatable {
    case dayFirst
    case monthFirst
}

nonisolated enum DateOrderDetector {

    /// Two 1-2 digit components followed by a 2-4 digit year, with a separator
    /// that carries no ordering information. ISO dates are excluded by
    /// requiring the year last.
    private static let ambiguousPattern = /\b(\d{1,2})[.\/\-](\d{1,2})[.\/\-](\d{2,4})\b/

    /// Day-first is the default: it is the convention in every market the app
    /// ships in except the United States, and it is what the previous importer
    /// assumed, so an ambiguous column behaves as it always has.
    static func detect(tokens: [String]) -> DateOrder {
        var dayFirstEvidence = 0
        var monthFirstEvidence = 0

        for token in tokens {
            guard let match = token.firstMatch(of: ambiguousPattern) else { continue }
            guard let first = Int(match.1), let second = Int(match.2) else { continue }

            // Only a component above 12 is evidence. Anything 1...12 is
            // consistent with both orders and tells us nothing.
            if first > 12 { dayFirstEvidence += 1 }
            if second > 12 { monthFirstEvidence += 1 }
        }

        // Conflicting evidence means OCR noise or a mixed column. Prefer
        // day-first rather than rejecting the column outright.
        if dayFirstEvidence > 0 { return .dayFirst }
        if monthFirstEvidence > 0 { return .monthFirst }
        return .dayFirst
    }
}
```

- [ ] **Step 4: Extend DateTokenParser**

In `Tenra/Services/Import/DateTokenParser.swift`, replace `parse(_:)` and `looksLikeDate(_:)` with:

```swift
    /// Parses the first date found in `token`, returning canonical "yyyy-MM-dd".
    /// Assumes day-first ordering. Callers that know the column's ordering
    /// should use `parse(_:order:)` instead.
    static func parse(_ token: String) -> String? {
        parse(token, order: .dayFirst)
    }

    /// Parses using a known column ordering, falling back to the opposite
    /// ordering when the given one yields no valid calendar date. The fallback
    /// is safe here in a way it is not for a lone token: the order came from
    /// evidence across the whole column, so the fallback only fires on the
    /// outliers that contradict it.
    static func parse(_ token: String, order: DateOrder) -> String? {
        if let match = token.firstMatch(of: isoPattern) {
            return canonical(year: Int(match.1) ?? 0,
                             month: Int(match.2) ?? 0,
                             day: Int(match.3) ?? 0)
        }

        guard let match = token.firstMatch(of: dayFirstPattern) else { return nil }
        let first = Int(match.1) ?? 0
        let second = Int(match.2) ?? 0
        let year = normalizeYear(Int(match.3) ?? 0)

        switch order {
        case .dayFirst:
            return canonical(year: year, month: second, day: first)
                ?? canonical(year: year, month: first, day: second)
        case .monthFirst:
            return canonical(year: year, month: first, day: second)
                ?? canonical(year: year, month: second, day: first)
        }
    }

    /// True when `token` is a valid date under EITHER ordering.
    ///
    /// Order-agnostic on purpose: ColumnRoleResolver uses this to score which
    /// column holds dates, and that scoring happens before any ordering is
    /// known. A day-first-only check would score a US date column below the
    /// detection threshold and the column would never be found.
    static func looksLikeDate(_ token: String) -> Bool {
        parse(token, order: .dayFirst) != nil || parse(token, order: .monthFirst) != nil
    }
```

Note that `parse(_:)` now inherits the fallback through `parse(_:order:)`, so `parse("08.13.2026")` returns `"2026-08-13"` rather than nil. Update the one existing assertion in `DateTokenParserTests.invalidDates()` accordingly: remove `#expect(DateTokenParser.parse("08.13.2026") == nil)` and add to the same test `#expect(DateTokenParser.parse("13/25/2026") == nil)`, which is invalid under both orderings and is the honest test of "no valid calendar date". Leave every other assertion in that file untouched.

- [ ] **Step 5: Wire the order into StatementInterpreter**

In `Tenra/Services/Import/StatementInterpreter.swift`, inside `interpret(snapshot:roles:defaultCurrency:)`, detect the order once per table before the row loop and use it for every row.

Immediately after the `guard table.columnCount > roles.date else { continue }` line, add:

```swift
            // Detect the column's date ordering once, from every cell in it.
            // Per-row detection would be worthless: ambiguity only resolves
            // when the whole column is in view.
            let dateOrder = DateOrderDetector.detect(
                tokens: table.rows.compactMap { row in
                    row.indices.contains(roles.date) ? row[roles.date] : nil
                }
            )
```

Then change the date guard inside the row loop from:

```swift
                guard let date = cell(row, roles.date).flatMap(DateTokenParser.parse) else {
```

to:

```swift
                guard let date = cell(row, roles.date)
                    .flatMap({ DateTokenParser.parse($0, order: dateOrder) }) else {
```

- [ ] **Step 6: Add a StatementInterpreter test for US ordering**

Append this case to the existing `StatementInterpreterTests` struct. Do not modify existing cases:

```swift
    @Test("a US-ordered date column is read month-first across every row")
    func usDateOrdering() {
        let doc = snapshot([
            ["Date", "Description", "Amount"],
            ["01/08/2026", "UBER TRIP", "-24.50"],
            ["01/25/2026", "TESCO", "-13.20"]
        ])
        let roles = ColumnRoleResolver.resolve(table: doc.allTables[0])!
        let result = StatementInterpreter.interpret(snapshot: doc, roles: roles, defaultCurrency: "USD")

        // 01/25 can only be month-first, which pins the whole column, so
        // 01/08 must read as 8 January and not 1 August.
        #expect(result.transactions.count == 2)
        #expect(result.transactions[0].date == "2026-01-08")
        #expect(result.transactions[1].date == "2026-01-25")
    }
```

- [ ] **Step 7: Run all affected suites**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests/DateOrderDetectorTests -only-testing:TenraTests/DateTokenParserTests -only-testing:TenraTests/StatementInterpreterTests -only-testing:TenraTests/ColumnRoleResolverTests 2>&1 | grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: all tests pass, `** TEST SUCCEEDED **`. `ColumnRoleResolverTests` is included because `looksLikeDate` changed underneath it and its scoring must be unaffected.

- [ ] **Step 8: Run the full test target**

Run:
```bash
xcodebuild test -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TenraTests 2>&1 | grep -aE "Test case .* failed|\*\* TEST (SUCCEEDED|FAILED)"
```
Expected: `** TEST SUCCEEDED **` with no failing test-case lines.

- [ ] **Step 9: Commit**

```bash
git add Tenra/Services/Import/DateOrderDetector.swift Tenra/Services/Import/DateTokenParser.swift Tenra/Services/Import/StatementInterpreter.swift TenraTests/Services/Import/DateOrderDetectorTests.swift TenraTests/Services/Import/DateTokenParserTests.swift TenraTests/Services/Import/StatementInterpreterTests.swift
git commit -m "fix(import): detect date ordering per column so US statements read month-first"
```

---

## Manual verification (device required)

Automated tests cover the deterministic layers. These four checks need a real device and cannot be scripted here. Run them on the physical iPhone (`Dkicekeeper 17`), building with `-destination 'platform=iOS,name=Dkicekeeper 17'`. A Simulator build never reaches the device.

1. **Text-layer PDF, known bank.** Import an Alatau City Bank statement. Every transaction the old parser found must still be found, and the diagnostics screen must show 0 skipped.
2. **Text-layer PDF, unknown bank.** Import a statement from any other bank, ideally in a non-Russian language. This is the case that returned zero transactions before.
3. **Scanned PDF.** Import a photographed or scanned statement to exercise `VisionDocumentExtractor`.
4. **Receipt, both paths.** Scan a paper receipt on an Apple Intelligence device, then on an ineligible one (or with Apple Intelligence turned off in Settings) to confirm the heuristic fallback produces a usable draft.

The Simulator has no camera, so the receipt path can only be verified on device.

## Notes on scope

Tasks 1-9 are self-contained: they deliver bank-agnostic statement import and can ship without the receipt work. Tasks 10-11 add receipts. If this needs to be split into two shipping units, split there.
