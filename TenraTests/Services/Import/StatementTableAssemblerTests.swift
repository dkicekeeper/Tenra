//
//  StatementTableAssemblerTests.swift
//  TenraTests
//
//  Hand-built word geometry modelled on two real Kazakh statements (anonymized):
//  a Kaspi-style layout (top-aligned cells, steady 16pt pitch, account summary above
//  the header, a footnote under the last row, no header on page 2) and a
//  Freedom-style layout (vertically centered cells, 12.7pt wrap pitch, a "Детали"
//  header centered far right of its text, a record broken by the page end).
//

import Testing
@testable import Tenra

struct StatementTableAssemblerTests {

    private typealias Word = StatementTableAssembler.Word

    /// Words of `text` laid out from `x`, 5pt per character and 3pt spaces,
    /// on a line centered at `y` (8pt glyph height).
    private func words(_ text: String, x: Double, y: Double) -> [Word] {
        var cursor = x
        return text.split(separator: " ").map { part in
            let width = Double(part.count) * 5
            defer { cursor += width + 3 }
            return Word(text: String(part), minX: cursor, maxX: cursor + width, minY: y - 4, maxY: y + 4)
        }
    }

    /// Right-aligned variant: the text ends at `right`.
    private func words(_ text: String, right: Double, y: Double) -> [Word] {
        let parts = text.split(separator: " ")
        let width = Double(parts.reduce(0) { $0 + $1.count }) * 5 + Double(parts.count - 1) * 3
        return words(text, x: right - width, y: y)
    }

    private func line(_ parts: [Word]...) -> StatementTableAssembler.Line {
        parts.flatMap { $0 }.sorted { $0.minX < $1.minX }
    }

    // MARK: - Kaspi-style

    private func kaspiPages() -> [[StatementTableAssembler.Line]] {
        func row(_ y: Double, _ date: String, _ amount: String, _ operation: String, _ details: String) -> StatementTableAssembler.Line {
            line(words(date, x: 52, y: y), words(amount, right: 190, y: y),
                 words(operation, right: 292, y: y), words(details, x: 311, y: y))
        }
        let page1: [StatementTableAssembler.Line] = [
            line(words("ВЫПИСКА по карте за период с 24.08.26 по 24.09.26", x: 40, y: 800)),
            line(words("Доступно на 24.09.26:", x: 43, y: 760), words("+ 12 345,67 ₸", right: 300, y: 760),
                 words("Валюта счета: тенге", x: 320, y: 760)),
            line(words("Дата", x: 59, y: 700), words("Сумма", x: 134, y: 700),
                 words("Операция", x: 243, y: 700), words("Детали", x: 311, y: 700)),
            row(684, "24.09.26", "- 995,00 ₸", "Покупка", "MAGNUM"),
            row(668, "22.09.26", "+ 25 000,00 ₸", "Пополнение", "С карты другого банка"),
            row(652, "04.09.26", "- 41 500,00 ₸", "Перевод на свой", "Оплата кредита"),
            line(words("счет", right: 292, y: 636)),
            row(620, "20.09.26", "- 3 000,00 ₸", "Перевод", "Асан Б."),
            line(words("- Сумма заблокирована. Банк ожидает подтверждения от платежной системы.", x: 49, y: 600)),
            line(words("АО Банк, БИК TESTKZKA, www.bank.kz", x: 39, y: 30))
        ]
        let page2: [StatementTableAssembler.Line] = [
            line(words("Приложение к Справке №1 от 24 сентября 2026", x: 40, y: 812)),
            row(786, "02.09.26", "+ 12 480,50 ₸", "Поступление со", "С депозита"),
            line(words("своего счета", right: 292, y: 770)),
            row(754, "01.09.26", "- 60 000,00 ₸", "Перевод", "Ержан Д."),
            line(words("АО Банк, БИК TESTKZKA, www.bank.kz", x: 39, y: 30))
        ]
        return [page1, page2]
    }

    @Test func kaspiStyleRowsKeepDetailsAndWrappedOperation() throws {
        let tables = try #require(StatementTableAssembler.assemble(pages: kaspiPages()))
        #expect(tables.count == 2)

        let first = try #require(tables[0].first)
        #expect(first.rows == [
            ["Дата", "Сумма", "Операция", "Детали"],
            ["24.09.26", "- 995,00 ₸", "Покупка", "MAGNUM"],
            ["22.09.26", "+ 25 000,00 ₸", "Пополнение", "С карты другого банка"],
            ["04.09.26", "- 41 500,00 ₸", "Перевод на свой счет", "Оплата кредита"],
            ["20.09.26", "- 3 000,00 ₸", "Перевод", "Асан Б."]
        ])
    }

    @Test func kaspiStyleHeaderlessPageReusesColumnsAndSkipsPreamble() throws {
        let tables = try #require(StatementTableAssembler.assemble(pages: kaspiPages()))
        let second = try #require(tables[1].first)
        #expect(second.rows == [
            ["Дата", "Сумма", "Операция", "Детали"],
            ["02.09.26", "+ 12 480,50 ₸", "Поступление со своего счета", "С депозита"],
            ["01.09.26", "- 60 000,00 ₸", "Перевод", "Ержан Д."]
        ])
    }

    @Test func summaryBlockAndFootnoteNeverBecomeRows() throws {
        let tables = try #require(StatementTableAssembler.assemble(pages: kaspiPages()))
        let cells = tables.flatMap { $0 }.flatMap(\.rows).flatMap { $0 }
        #expect(!cells.contains { $0.contains("Доступно") })
        #expect(!cells.contains { $0.contains("заблокирована") })
        #expect(!cells.contains { $0.contains("Приложение") })
    }

    // MARK: - Freedom-style

    private func freedomPages() -> [[StatementTableAssembler.Line]] {
        func anchor(_ y: Double, _ date: String, _ amount: String, _ operation: String?, _ details: String?) -> StatementTableAssembler.Line {
            var parts = [words(date, x: 70, y: y), words(amount, right: 248, y: y), words("KZT", x: 273, y: y)]
            if let operation { parts.append(words(operation, x: 310, y: y)) }
            if let details { parts.append(words(details, x: 384, y: y)) }
            return parts.flatMap { $0 }.sorted { $0.minX < $1.minX }
        }
        let page1: [StatementTableAssembler.Line] = [
            line(words("Дата", x: 83, y: 630), words("Сумма", x: 223, y: 630), words("Валюта", x: 265, y: 630),
                 words("Операция", x: 321, y: 630), words("Детали", x: 451, y: 630)),
            // Pending purchase: the operation cell wraps around the date line.
            line(words("Сумма в", x: 309, y: 613)),
            anchor(606.6, "20.09.2026", "-18,400.00 ₸", nil, "MAGNUM ALMATY KZ"),
            line(words("обработке", x: 309, y: 600.3)),
            // Transfer: five detail lines centered on the date line.
            line(words("Плательщик: Тестов Тест", x: 384, y: 580.8)),
            line(words("Назначение: ФИО: Асан Б.. Мобильный:", x: 384, y: 568.1)),
            anchor(555.4, "20.09.2026", "-30,000.00 ₸", "Перевод", "77000000000. Референс: FBK1-"),
            line(words("abc. БИК: TESTKZKA.", x: 384, y: 542.7)),
            line(words("COMTYPE: C2C.", x: 384, y: 530.0)),
            // Deposit to card: a details line that starts with a date.
            line(words("Перевод вклада по Договору", x: 384, y: 510.5)),
            anchor(498, "19.09.2026", "+50,000.00 ₸", "Пополнение", "№KZ00000A0000000000 от"),
            line(words("19.09.2026. Вкладчик: Тестов Т.", x: 384, y: 485)),
            // First line of a record the page end breaks.
            line(words("Перевод вклада по Договору", x: 384, y: 465.5)),
            line(words("Подлинность справки можете проверить", x: 164, y: 57))
        ]
        let page2: [StatementTableAssembler.Line] = [
            anchor(704, "18.09.2026", "+50,000.00 ₸", "Пополнение", "№KZ00000A0000000000 от"),
            line(words("18.09.2026. Вкладчик: Тестов Т.", x: 384, y: 692)),
            anchor(669, "18.09.2026", "-3,920.00 ₸", "Покупка", "YANDEX.GO ALMATY KZ"),
            line(words("Подлинность справки можете проверить", x: 164, y: 57))
        ]
        return [page1, page2]
    }

    @Test func freedomStyleCenteredCellsJoinTheirRecord() throws {
        let tables = try #require(StatementTableAssembler.assemble(pages: freedomPages()))
        let first = try #require(tables[0].first)
        #expect(first.rows == [
            ["Дата", "Сумма", "Валюта", "Операция", "Детали"],
            ["20.09.2026", "-18,400.00 ₸", "KZT", "Сумма в обработке", "MAGNUM ALMATY KZ"],
            ["20.09.2026", "-30,000.00 ₸", "KZT", "Перевод",
             "Плательщик: Тестов Тест Назначение: ФИО: Асан Б.. Мобильный: 77000000000. Референс: FBK1- abc. БИК: TESTKZKA. COMTYPE: C2C."],
            ["19.09.2026", "+50,000.00 ₸", "KZT", "Пополнение",
             "Перевод вклада по Договору №KZ00000A0000000000 от 19.09.2026. Вкладчик: Тестов Т."]
        ])
    }

    @Test func freedomStyleRecordBrokenByPageEndIsRejoined() throws {
        let tables = try #require(StatementTableAssembler.assemble(pages: freedomPages()))
        let second = try #require(tables[1].first)
        #expect(second.rows == [
            ["Дата", "Сумма", "Валюта", "Операция", "Детали"],
            ["18.09.2026", "+50,000.00 ₸", "KZT", "Пополнение",
             "Перевод вклада по Договору №KZ00000A0000000000 от 18.09.2026. Вкладчик: Тестов Т."],
            ["18.09.2026", "-3,920.00 ₸", "KZT", "Покупка", "YANDEX.GO ALMATY KZ"]
        ])
    }

    // MARK: - Fallback

    @Test func documentWithoutHeaderIsLeftToTheGapSplitTables() {
        let pages = [[
            line(words("01.01.2026", x: 20, y: 700), words("150.00", x: 300, y: 700)),
            line(words("just a note", x: 20, y: 680))
        ]]
        #expect(StatementTableAssembler.assemble(pages: pages) == nil)
    }

    // MARK: - End to end through the interpreter

    private func snapshot(_ pages: [[StatementTableAssembler.Line]]) throws -> DocumentSnapshot {
        let tables = try #require(StatementTableAssembler.assemble(pages: pages))
        return DocumentSnapshot(pages: tables.enumerated().map {
            DocumentSnapshot.Page(index: $0.offset, tables: $0.element, lines: [], barcodes: [])
        }, hadTextLayer: true)
    }

    @Test func assembledTablesParseIntoLabeledTransactions() throws {
        let kaspi = try snapshot(kaspiPages())
        let freedom = try snapshot(freedomPages())

        let kaspiTable = try #require(kaspi.allTables.first)
        let kaspiRoles = try #require(ColumnRoleResolver.resolve(table: kaspiTable))
        #expect(kaspiRoles.description == 3)
        #expect(kaspiRoles.operation == 2)
        let kaspiResult = StatementInterpreter.interpret(snapshot: kaspi, roles: kaspiRoles, defaultCurrency: "KZT")
        #expect(kaspiResult.skipped.isEmpty)
        #expect(kaspiResult.transactions.map(\.descriptionText) == [
            "MAGNUM",
            "Пополнение · С карты другого банка",
            "Перевод на свой счет · Оплата кредита",
            "Перевод · Асан Б.",
            "Поступление со своего счета · С депозита",
            "Перевод · Ержан Д."
        ])
        #expect(kaspiResult.transactions.map(\.amount) == [995, 25_000, 41_500, 3_000, 12_480.5, 60_000])

        let freedomTable = try #require(freedom.allTables.first)
        let freedomRoles = try #require(ColumnRoleResolver.resolve(table: freedomTable))
        let freedomResult = StatementInterpreter.interpret(snapshot: freedom, roles: freedomRoles, defaultCurrency: "KZT")
        #expect(freedomResult.skipped.isEmpty)
        #expect(freedomResult.transactions.map(\.descriptionText) == [
            "MAGNUM ALMATY KZ",
            "Перевод · Асан Б.",
            "Пополнение · Перевод вклада по Договору от 19.09.2026. Вкладчик: Тестов Т.",
            "Пополнение · Перевод вклада по Договору от 18.09.2026. Вкладчик: Тестов Т.",
            "YANDEX.GO ALMATY KZ"
        ])
        #expect(freedomResult.transactions.map(\.operation) == [
            "Сумма в обработке", "Перевод", "Пополнение", "Пополнение", "Покупка"
        ])
    }
}
