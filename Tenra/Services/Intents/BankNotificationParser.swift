//
//  BankNotificationParser.swift
//  Tenra
//
//  Reads an operation out of a bank app's push notification, for
//  LogBankNotificationIntent (the iOS 27 notification automation). Bank-agnostic:
//  no bank's format is coded here (docs/plan-notification-capture.md §3-§5). Every
//  bank writes the same parts, in its own words and order:
//
//  • the amount with its currency ("1 500 ₸", "-5 $", "€4.50", "150,00 TL"), signed or not;
//  • the balance after it ("Доступно: 12 345 ₸", "Available", "Bakiye"), never the amount;
//  • a fee ("Комиссия: 100 ₸"), added to what leaves the account;
//  • a card mask ("**1234"), which tells the account;
//  • an operation word ("Покупка", "Пополнение", "Перевод", "paid"), which gives the
//    direction when the amount has no sign;
//  • the merchant or the person: what follows the operation word, else the next line.
//
//  What reads as no operation (a code, a declined payment, cashback, a promo, an amount
//  with no currency, nothing that marks an operation) returns nil: nothing recorded
//  beats a wrong record. Pure, so every rule is pinned by BankNotificationParserTests on
//  invented texts.
//

import Foundation

/// One operation read from a bank notification.
nonisolated struct BankNotification: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case expense
        case income
        /// Between two of the user's own accounts: the notification shows one side only.
        case ownTransfer
        /// Cash from an ATM: spent and logged later.
        case cashWithdrawal
    }

    let kind: Kind
    /// What left or reached the account, a fee included. Always positive.
    let amount: Double
    /// ISO 4217.
    let currencyCode: String
    /// The merchant, the sender or the recipient; "" when the notification names none.
    let counterparty: String
    /// The last four digits of the card or account, when the notification shows them.
    let cardDigits: String?
    /// Money came into this bank's account: an income, or the receiving side of a transfer
    /// between own accounts (OwnTransferMatcher pairs it with the sending side).
    var isIncoming: Bool = false
}

nonisolated enum BankNotificationParser {

    /// The operation in a notification's title, subtitle and text, or nil when there is none.
    static func parse(title: String, subtitle: String = "", body: String) -> BankNotification? {
        let lines = [title, subtitle, body]
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n").lowercased()
        guard !lines.isEmpty, !mentions(text, any: notAnOperation) else { return nil }

        // Every amount, told apart by the words in front of it on its line.
        var operations: [Money] = []
        var fees: [Money] = []
        var hasBalance = false
        for (index, line) in lines.enumerated() {
            var segmentStart = line.startIndex
            for money in moneyValues(in: line, line: index) {
                let before = line[segmentStart..<money.range.lowerBound].lowercased()
                segmentStart = money.range.upperBound
                if mentions(before, any: balanceWords) {
                    hasBalance = true
                } else if mentions(before, any: feeWords) {
                    fees.append(money)
                } else {
                    operations.append(money)
                }
            }
        }

        let money: Money
        var extraFees = fees
        if let operation = operations.first(where: { $0.sign != nil }) ?? operations.first {
            money = operation
        } else if let fee = fees.first {
            // A notification about a fee alone.
            money = fee
            extraFees.removeFirst()
        } else {
            return nil
        }

        let word = operationWord(in: lines)
        let digits = cardDigits(in: lines)

        let kind: BankNotification.Kind
        if word?.kind == .cash {
            kind = .cashWithdrawal
        } else if word?.kind != .expense,
                  StatementOperationKind.classify(operation: nil, details: text) == .ownAccountTransfer {
            kind = .ownTransfer
        } else if money.sign == "-" {
            kind = .expense
        } else if money.sign == "+" {
            kind = .income
        } else if let word {
            // An unsigned amount needs something that marks an operation, so a promo
            // naming a sum is not recorded.
            guard hasBalance || digits != nil || word.index < 3 || word.line == money.line else { return nil }
            switch word.kind {
            case .expense, .cash: kind = .expense
            case .income: kind = .income
            case .transfer: kind = isIncoming(lines[word.line]) ? .income : .expense
            }
        } else {
            return nil
        }

        let amount = kind == .expense
            ? extraFees.filter { $0.currency == money.currency }.reduce(money.amount) { $0 + $1.amount }
            : money.amount
        let party = kind == .expense || kind == .income ? counterpartyName(in: lines, word: word) : ""
        // Which way the money went: the sign, else the word ("Пополнение", "from …").
        let incoming: Bool
        if money.sign == "+" {
            incoming = true
        } else if money.sign == "-" {
            incoming = false
        } else if let word {
            incoming = word.kind == .income || (word.kind == .transfer && isIncoming(lines[word.line]))
        } else {
            incoming = kind == .income
        }
        return BankNotification(
            kind: kind,
            amount: amount,
            currencyCode: money.currency,
            counterparty: party,
            cardDigits: digits,
            isIncoming: kind == .income || (kind == .ownTransfer && incoming)
        )
    }

    /// The card key for CardAccountMemory: the bank app, with the card's last digits when
    /// the notification shows them ("Freedom •• 1234"), so each card of a bank can have
    /// its own account.
    static func cardName(app: String, digits: String?) -> String {
        let app = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let digits else { return app }
        return app.isEmpty ? "•• \(digits)" : "\(app) •• \(digits)"
    }

    // MARK: - Money

    private struct Money {
        let amount: Double
        let currency: String
        /// "-" or "+" when the amount carries a sign.
        let sign: Character?
        let line: Int
        let range: Range<String.Index>
    }

    /// Sign, currency before the number, the number (grouped with spaces, dots, commas or
    /// apostrophes, up to two decimals), currency after it.
    private static let moneyPattern = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}])([+\-\x{2212}])?\s?(R\$|\p{Sc}|[A-Z]{3}(?=\s?\d))?\s?(\d{1,3}(?:[ \x{00A0}\x{202F}\x{2009}'.,]\d{3})+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)(?!\d)(?:\s?(R\$|\p{Sc}|\p{L}{1,5}\.?)(?!\p{L}))?"#
    )

    /// Amounts with a currency on one line. A number without one (a card number, a time,
    /// a percentage, a deposit's number) is not money.
    private static func moneyValues(in line: String, line index: Int) -> [Money] {
        let nsRange = NSRange(line.startIndex..., in: line)
        return moneyPattern.matches(in: line, range: nsRange).compactMap { match in
            func group(_ number: Int) -> Range<String.Index>? {
                Range(match.range(at: number), in: line)
            }
            guard let numberRange = group(3), let whole = group(0),
                  let amount = MoneyTokenParser.parse(String(line[numberRange]))?.amount, amount > 0 else {
                return nil
            }
            // A currency in front ends the amount at its number: the word after it is the
            // merchant ("$5 Uber"), not a currency.
            let currency: String
            let end: String.Index
            if let prefix = group(2), let code = currencyCode(for: String(line[prefix])) {
                currency = code
                end = numberRange.upperBound
            } else if let suffix = group(4), let code = currencyCode(for: String(line[suffix])) {
                currency = code
                end = whole.upperBound
            } else {
                return nil
            }
            let sign = group(1).map { line[$0] == "+" ? Character("+") : Character("-") }
            return Money(amount: amount, currency: currency, sign: sign, line: index, range: whole.lowerBound..<end)
        }
    }

    /// Symbols MoneyTokenParser does not know.
    private static let extraSymbols: [String: String] = [
        "R$": "BRL", "₾": "GEL", "֏": "AMD", "₼": "AZN"
    ]

    /// Local abbreviations written after the number.
    private static let currencyWords: [String: String] = [
        "тг": "KZT", "тнг": "KZT", "тенге": "KZT", "теңге": "KZT",
        "руб": "RUB", "р": "RUB", "грн": "UAH", "tl": "TRY",
        "zł": "PLN", "zl": "PLN", "kč": "CZK", "ft": "HUF",
        "сум": "UZS", "сом": "KGS", "лари": "GEL", "円": "JPY", "원": "KRW"
    ]

    private static func currencyCode(for token: String) -> String? {
        if let code = extraSymbols[token] { return code }
        let word = token.hasSuffix(".") ? String(token.dropLast()) : token
        if let code = currencyWords[word.lowercased()] { return code }
        if word.count == 3, word.allSatisfy({ $0.isASCII && $0.isLetter }) {
            let upper = word.uppercased()
            return MoneyTokenParser.parse("1 \(upper)")?.currency == upper ? upper : nil
        }
        guard word.count == 1 else { return nil }
        return MoneyTokenParser.parse("1\(word)")?.currency
    }

    // MARK: - Card

    private static let maskPattern = try! NSRegularExpression(
        pattern: #"(?:[*•∙…]+\s?|(?i:ending(?:\s+in)?|оканчива\p{L}*\s+на)\s+)(\d{4})(?!\d)"#
    )

    private static func cardDigits(in lines: [String]) -> String? {
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = maskPattern.firstMatch(in: line, range: range),
               let digits = Range(match.range(at: 1), in: line) {
                return String(line[digits])
            }
        }
        return nil
    }

    private static func hasMask(_ line: String) -> Bool {
        maskPattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    // MARK: - Operation word

    private enum WordKind {
        case expense, income, transfer, cash
    }

    private struct OperationWord {
        let kind: WordKind
        let line: Int
        /// The word's position on its line.
        let index: Int
        /// nil for a word found inside a run of Japanese or Korean text.
        let range: Range<String.Index>?
    }

    /// The first operation word, line by line: the line it is on names the operation
    /// ("Покупка Coffee Point"), later lines are details ("Списано с … **1234").
    private static func operationWord(in lines: [String]) -> OperationWord? {
        let lexicon: [(WordKind, [String])] = [
            (.cash, cashWords), (.transfer, transferWords), (.income, incomeWords), (.expense, expenseWords)
        ]
        for (lineIndex, line) in lines.enumerated() {
            for (wordIndex, word) in words(in: line).enumerated() {
                for (kind, markers) in lexicon where markers.contains(where: { matches(word.text, $0) }) {
                    return OperationWord(kind: kind, line: lineIndex, index: wordIndex, range: word.range)
                }
            }
            for (kind, markers) in lexicon where markers.contains(where: { isUnspaced($0) && line.contains($0) }) {
                return OperationWord(kind: kind, line: lineIndex, index: 0, range: nil)
            }
        }
        return nil
    }

    /// A transfer that came in: "Перевод от Ивана", "Incoming transfer".
    private static func isIncoming(_ line: String) -> Bool {
        mentions(line.lowercased(), any: incomingWords)
    }

    // MARK: - Counterparty

    /// What follows the operation word on its line ("Покупка Coffee Point"), else the first
    /// line after it that is not a detail (balance, fee, card).
    private static func counterpartyName(in lines: [String], word: OperationWord?) -> String {
        if let word, let range = word.range {
            let after = clean(String(lines[word.line][range.upperBound...]))
            if after.contains(where: \.isLetter) { return after }
        }
        let start = word.map { $0.line + 1 } ?? 0
        for line in lines.dropFirst(start) {
            let lowered = line.lowercased()
            guard !hasMask(line), !mentions(lowered, any: balanceWords), !mentions(lowered, any: feeWords) else {
                continue
            }
            let candidate = clean(line)
            if candidate.contains(where: \.isLetter) { return candidate }
        }
        return ""
    }

    /// The text up to its balance or fee, without amounts and card masks, punctuation and a
    /// leading preposition ("от А" → "А", "at Pret" → "Pret") trimmed.
    private static func clean(_ text: String) -> String {
        var text = text
        if let detail = words(in: text).first(where: { word in
            (balanceWords + feeWords).contains { !isUnspaced($0) && matches(word.text, $0) }
        }) {
            text = String(text[..<detail.range.lowerBound])
        }
        var result = ""
        var cursor = text.startIndex
        for money in moneyValues(in: text, line: 0) {
            result += text[cursor..<money.range.lowerBound]
            result += " "
            cursor = money.range.upperBound
        }
        result += text[cursor...]
        let nsRange = NSRange(result.startIndex..., in: result)
        result = maskPattern.stringByReplacingMatches(in: result, range: nsRange, withTemplate: " ")
        result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")

        let leading = CharacterSet(charactersIn: " :;,.-–—·•*|")
        let trailing = CharacterSet(charactersIn: " :;,-–—·•*|")
        var scalars = String.UnicodeScalarView(result.unicodeScalars.drop { leading.contains($0) })
        while let last = scalars.last, trailing.contains(last) {
            scalars.removeLast()
        }
        result = String(scalars)
        while let space = result.firstIndex(of: " "),
              prepositions.contains(result[..<space].lowercased()) {
            result = String(result[result.index(after: space)...])
        }
        // Nothing but a filler word left ("yapılmıştır.").
        if prepositions.contains(result.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            return ""
        }
        return result
    }

    // MARK: - Words

    private static func words(in line: String) -> [(text: String, range: Range<String.Index>)] {
        var result: [(text: String, range: Range<String.Index>)] = []
        var start: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character.isLetter || character.isNumber || character == "-" {
                if start == nil { start = index }
            } else if let wordStart = start {
                result.append((line[wordStart..<index].lowercased(), wordStart..<index))
                start = nil
            }
            index = line.index(after: index)
        }
        if let wordStart = start {
            result.append((line[wordStart...].lowercased(), wordStart..<line.endIndex))
        }
        return result
    }

    /// Markers of four letters and more match the start of a word ("покупк" → "Покупка"),
    /// shorter ones the whole word ("atm", not "atmosphere").
    private static func matches(_ word: String, _ marker: String) -> Bool {
        marker.count >= 4 ? word.hasPrefix(marker) : word == marker
    }

    /// Japanese and Korean markers: their words are not separated by spaces.
    private static func isUnspaced(_ marker: String) -> Bool {
        (marker.unicodeScalars.first?.value ?? 0) >= 0x3000
    }

    /// `text` is lowercased.
    private static func mentions(_ text: String, any markers: [String]) -> Bool {
        let tokens = words(in: text).map(\.text)
        return markers.contains { marker in
            isUnspaced(marker) ? text.contains(marker) : tokens.contains { matches($0, marker) }
        }
    }

    // MARK: - Lexicon (the app's 11 languages and Kazakh; arrays, so a repeated word is harmless)

    /// Never an operation to record: codes, declined payments, cashback, promos.
    private static let notAnOperation = [
        "код", "кода", "коду", "коды", "кодом", "code", "codes", "kod", "kodu", "пароль", "пароля",
        "password", "passwort", "одноразов", "отклон", "відхил", "declin", "rejected", "abgelehnt",
        "rechaz", "refus", "rifiutat", "recusad", "reddedil", "недостаточно", "insufficient",
        "кешбэк", "кэшбэк", "кешбек", "cashback", "скидк", "знижк", "акци", "розыгрыш",
        "промокод", "получите", "успейте", "выиграйте", "дарим", "подарок", "отримайте", "discount",
        "promo", "offer", "earn", "認証", "인증", "거절"
    ]

    private static let balanceWords = [
        "доступн", "баланс", "остаток", "залишок", "available", "avl", "bal", "balance",
        "verfügbar", "kontostand", "saldo", "disponible", "disponibile", "disponível", "kalan",
        "bakiye", "kullanılabilir", "қалдық", "қолжетімді", "残高", "잔액"
    ]

    private static let feeWords = [
        "комисси", "комісі", "fee", "fees", "commission", "gebühr", "entgelt", "comisión",
        "frais", "commissione", "tarifa", "taxa", "ücret", "komisyon", "手数料", "수수료"
    ]

    private static let cashWords = [
        "снятие", "снятия", "зняття", "withdrawal", "atm", "bargeld", "geldautomat", "abhebung",
        "retiro", "retrait", "prelievo", "saque", "nakit", "引出", "인출"
    ]

    private static let transferWords = [
        "перевод", "переказ", "transfer", "überweisung", "virement", "bonifico", "havale",
        "аударым", "振込", "送金", "송금", "이체"
    ]

    private static let incomeWords = [
        "пополнен", "зачислен", "поступлен", "поступил", "возврат", "входящ", "получен", "зарплат",
        "поповнен", "зарахуван", "надходжен", "повернен", "отриман", "received", "credited",
        "refund", "incoming", "top-up", "topup", "salary", "gutschrift", "eingang", "erstattung",
        "einzahlung", "recibid", "abono", "reembolso", "ingreso", "devoluci", "reçu",
        "remboursement", "versement", "crédité", "ricevut", "accredit", "rimborso", "recebid",
        "estorno", "gelen", "iade", "yatırıl", "толықтыр", "入金", "返金", "입금", "환불"
    ]

    private static let expenseWords = [
        "покупк", "оплат", "списан", "платеж", "платёж", "расход", "потрачен", "комисси",
        "купівл", "платіж", "комісі", "purchase", "paid", "spent", "spend", "payment", "charged",
        "debited", "kauf", "zahlung", "bezahlt", "abbuchung", "belastung", "lastschrift", "compra",
        "pago", "pagad", "cargo", "achat", "paiement", "payé", "acquisto", "pagament", "pagat",
        "addebit", "débito", "harcama", "ödeme", "alışveriş", "сатып", "төлем", "支払", "決済",
        "결제", "승인"
    ]

    /// A transfer with one of these came in.
    private static let incomingWords = [
        "от", "from", "von", "від", "входящ", "incoming", "received", "gelen", "recibid", "reçu",
        "ricevut", "recebid", "отриман", "получен"
    ]

    /// Dropped in front of a merchant or a person: prepositions, and the words a bank puts
    /// between the operation and the merchant ("compra aprovada em PADARIA").
    private static let prepositions: Set<String> = [
        "от", "у", "для", "из", "від", "of", "from", "at", "to", "for", "von", "bei", "an", "chez",
        "à", "para", "en", "em", "in", "da", "presso", "успешно", "approved", "aprovada", "aprovado",
        "realizada", "realizado", "yapılmıştır", "yapıldı", "gerçekleşti"
    ]
}
