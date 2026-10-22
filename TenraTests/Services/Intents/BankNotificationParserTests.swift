//
//  BankNotificationParserTests.swift
//  TenraTests
//
//  Pins the bank-agnostic reading of bank notifications (LogBankNotificationIntent):
//  the layouts of two Kazakh banks (Kaspi: "Операция: сумма", the person on the next
//  line; Freedom: the merchant in the title, a signed amount, the card's mask), other
//  languages, and what is never recorded. Every value is invented.
//

import Testing
@testable import Tenra

struct BankNotificationParserTests {

    private func parse(_ title: String, _ body: String = "") -> BankNotification? {
        BankNotificationParser.parse(title: title, body: body)
    }

    // MARK: - Kaspi-style layout

    @Test("A transfer: the amount after the operation word, the person on the next line, then the balance")
    func transferToPerson() throws {
        let operation = try #require(parse("Перевод: 2 350 ₸", "Иван П.\nДоступно: 10 000,50 ₸"))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 2_350)
        #expect(operation.currencyCode == "KZT")
        #expect(operation.counterparty == "Иван П.")
        #expect(operation.cardDigits == nil)
    }

    @Test("The same notification with the app's name as its title")
    func appNameAsTitle() throws {
        let operation = try #require(parse("Kaspi.kz", "Перевод: 2 350 ₸\nИван П.\nДоступно: 10 000,50 ₸"))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 2_350)
        #expect(operation.counterparty == "Иван П.")
    }

    @Test("The operation word alone on the title, the amount on the next line")
    func operationWordAlone() throws {
        let operation = try #require(parse("Перевод", "2 350 ₸\nИван П.\nДоступно: 900 ₸"))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 2_350)
        #expect(operation.counterparty == "Иван П.")
    }

    @Test("A purchase names the shop on the next line")
    func purchase() throws {
        let operation = try #require(parse("Покупка: 3 200 ₸", "В Магазине на Kaspi.kz\nДоступно: 7 000 ₸"))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 3_200)
        #expect(operation.counterparty == "В Магазине на Kaspi.kz")
    }

    @Test("A top-up is an income from the person named")
    func topUp() throws {
        let operation = try #require(parse("Пополнение: 60 000 ₸", "Мария С.\nДоступно: 70 000 ₸"))
        #expect(operation.kind == .income)
        #expect(operation.amount == 60_000)
        #expect(operation.counterparty == "Мария С.")
    }

    @Test("A fee is added to what leaves the account, never taken for the amount")
    func feeAdded() throws {
        let operation = try #require(parse(
            "Перевод: 100 000 ₸",
            "Иван П., Freedom Bank\nКомиссия: 100 ₸\nДоступно: 5 000 ₸"
        ))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 100_100)
        #expect(operation.counterparty == "Иван П., Freedom Bank")
    }

    @Test("Money from the user's own deposit is a transfer between own accounts")
    func fromOwnDeposit() throws {
        let operation = try #require(parse("Пополнение: 200 000 ₸", "С Kaspi Депозита D-007\nДоступно: 250 000 ₸"))
        #expect(operation.kind == .ownTransfer)
        #expect(operation.amount == 200_000)
    }

    @Test("A balance on the same line ends the shop's name")
    func oneLine() throws {
        let operation = try #require(parse("Kaspi.kz", "Покупка: 3 200 ₸ В Магазине. Доступно: 900 ₸"))
        #expect(operation.amount == 3_200)
        #expect(operation.counterparty == "В Магазине.")
    }

    @Test("Non-breaking spaces group the digits too")
    func nonBreakingSpaces() throws {
        let operation = try #require(parse("Покупка: 1\u{00A0}500\u{00A0}₸", "MAGNUM\nДоступно: 900 ₸"))
        #expect(operation.amount == 1_500)
        #expect(operation.counterparty == "MAGNUM")
    }

    // MARK: - Freedom-style layout

    @Test("A purchase: the merchant in the title, a signed amount, the card's last digits")
    func signedPurchase() throws {
        let operation = try #require(parse(
            "Покупка Coffee Point",
            "-1 500 ₸\nДоступно 12 345,67 ₸\nСписано с Deposit Card **1234"
        ))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 1_500)
        #expect(operation.currencyCode == "KZT")
        #expect(operation.counterparty == "Coffee Point")
        #expect(operation.cardDigits == "1234")
    }

    @Test("A purchase in another currency keeps the purchase's currency")
    func foreignPurchase() throws {
        let operation = try #require(parse(
            "Покупка Example Cloud",
            "-5 $\nДоступно 8 000 ₸\nСписано с Deposit Card **1234"
        ))
        #expect(operation.kind == .expense)
        #expect(operation.amount == 5)
        #expect(operation.currencyCode == "USD")
    }

    @Test("A top-up from a person: the preposition goes")
    func signedTopUp() throws {
        let operation = try #require(parse(
            "Пополнение от А",
            "+50 000 ₸\nДоступно 60 000 ₸\nПополнено Deposit Card **1234"
        ))
        #expect(operation.kind == .income)
        #expect(operation.amount == 50_000)
        #expect(operation.counterparty == "А")
        #expect(operation.cardDigits == "1234")
    }

    @Test("A transfer between own accounts is told apart from an income")
    func betweenOwnAccounts() throws {
        let operation = try #require(parse(
            "Перевод между своими счетами",
            "+10 000 ₸\nДоступно 20 000 ₸\nПополнено Deposit Card · KZT **5678"
        ))
        #expect(operation.kind == .ownTransfer)
        #expect(operation.cardDigits == "5678")
    }

    // MARK: - Other languages

    @Test("Other banks' wording: the merchant after a preposition, the currency before or after")
    func otherLanguages() throws {
        let paid = try #require(parse("", "You paid €4.50 at Pret A Manger"))
        #expect(paid.kind == .expense)
        #expect(paid.amount == 4.5)
        #expect(paid.currencyCode == "EUR")
        #expect(paid.counterparty == "Pret A Manger")

        let charged = try #require(parse("", "Card ending 4321 was charged $25.00 at STARBUCKS"))
        #expect(charged.amount == 25)
        #expect(charged.currencyCode == "USD")
        #expect(charged.counterparty == "STARBUCKS")
        #expect(charged.cardDigits == "4321")

        let german = try #require(parse("Zahlung von 12,50 € an REWE"))
        #expect(german.amount == 12.5)
        #expect(german.counterparty == "REWE")

        let grouped = try #require(parse("", "Payment of 1,234.56 USD to ACME"))
        #expect(grouped.amount == 1_234.56)
        #expect(grouped.counterparty == "ACME")

        let brazil = try #require(parse("", "R$ 35,90 compra aprovada em PADARIA"))
        #expect(brazil.currencyCode == "BRL")
        #expect(brazil.amount == 35.9)
        #expect(brazil.counterparty == "PADARIA")

        let turkish = try #require(parse("", "Kartınızdan 150,00 TL harcama yapılmıştır."))
        #expect(turkish.kind == .expense)
        #expect(turkish.currencyCode == "TRY")
        #expect(turkish.counterparty == "")
    }

    @Test("A transfer from someone is an income, a refund too")
    func incomingWords() throws {
        #expect(try #require(parse("Перевод от Ивана: 5 000 ₸")).kind == .income)
        #expect(try #require(parse("", "Возврат: 3 000 ₸\nMAGNUM\nДоступно: 900 ₸")).kind == .income)
    }

    @Test("Cash from an ATM is not spending; a cafe whose name starts like ATM is")
    func cash() throws {
        #expect(try #require(parse("Снятие наличных: 20 000 ₸", "ATM\nДоступно: 1 000 ₸")).kind == .cashWithdrawal)
        let cafe = try #require(parse("Покупка: 2 000 ₸", "ATMOSPHERE CAFE\nДоступно: 1 000 ₸"))
        #expect(cafe.kind == .expense)
        #expect(cafe.counterparty == "ATMOSPHERE CAFE")
    }

    // MARK: - Never recorded

    @Test("Codes, declined payments, cashback, balances and promos are not operations")
    func notOperations() {
        #expect(parse("Код подтверждения: 1234. Никому не сообщайте") == nil)
        #expect(parse("", "Оплата отклонена: недостаточно средств. 5 000 ₸") == nil)
        #expect(parse("Кешбэк за покупку", "+45 ₸\nCOFFEE POINT\nКешбэк в обработке") == nil)
        #expect(parse("", "Ваш баланс: 10 000 ₸") == nil)
        #expect(parse("Получите 1 000 ₸ на покупку", "Только до конца недели") == nil)
        #expect(parse("Скидка 20% на всё") == nil)
    }

    @Test("An amount needs a currency and something that marks an operation")
    func needsEvidence() {
        #expect(parse("Покупка: 2 000", "MAGNUM") == nil)
        #expect(parse("", "$5 Uber") == nil)
        #expect(parse("", "") == nil)
    }

    // MARK: - Card key

    @Test("The card key is the bank's app with the card's last digits")
    func cardName() {
        #expect(BankNotificationParser.cardName(app: "Freedom", digits: "1234") == "Freedom •• 1234")
        #expect(BankNotificationParser.cardName(app: " Kaspi.kz ", digits: nil) == "Kaspi.kz")
        #expect(BankNotificationParser.cardName(app: "", digits: "1234") == "•• 1234")
    }
}
