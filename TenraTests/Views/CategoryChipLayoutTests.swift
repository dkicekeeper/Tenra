//
//  CategoryChipLayoutTests.swift
//  TenraTests
//
//  How a category name is laid out on its chip: never split inside a word.
//

import Testing
@testable import Tenra

struct CategoryChipLayoutTests {

    @Test(arguments: [
        ("Транспорт", "Транспорт"),                            // short: one line
        ("Коммунальные", "Коммунальные"),                      // one long word: shrinks on one line
        ("Кафе и рестораны", "Кафе и\nрестораны"),             // two lines at a word boundary
        ("Коммунальные платежи", "Коммунальные\nплатежи"),
        ("Образование и курсы", "Образование\nи курсы"),
        ("Dienstleistungen", "Dienstleistungen")
    ])
    func namesBreakOnlyBetweenWords(name: String, expected: String) {
        #expect(CategoryChip.displayLines(name) == expected)
    }
}
