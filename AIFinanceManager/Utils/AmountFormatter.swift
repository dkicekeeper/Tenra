//
//  AmountFormatter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

struct AmountFormatter {
    // Кэшированный форматтер для производительности
    private static let cachedFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        return formatter
    }()
    
    // Форматирует Decimal для отображения: "1 234 567.89"
    static func format(_ value: Decimal) -> String {
        return cachedFormatter.string(from: value as NSDecimalNumber) ?? "0.00"
    }
    
    // Парсит строку в Decimal, убирая пробелы и заменяя запятую на точку
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US"))
    }
    
    // Валидирует ввод: только цифры, пробелы, точка или запятая
    static func isValidInput(_ text: String) -> Bool {
        let allowedCharacters = CharacterSet(charactersIn: "0123456789 .,+-×÷")
        return text.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
    
    // Форматирует при вводе с сохранением позиции курсора
    static func formatForInput(_ text: String, caretPosition: inout Int) -> String {
        // Убираем все пробелы для парсинга
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        
        // Если строка пустая или содержит операторы, не форматируем
        if cleaned.isEmpty || cleaned.contains(where: { "+-×÷".contains($0) }) {
            return text
        }
        
        // Парсим в Decimal
        guard let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US")) else {
            return text
        }
        
        // Форматируем
        let formatted = format(decimal)
        
        // Пересчитываем позицию курсора
        // Подсчитываем количество символов (цифры + точка) до позиции курсора в исходной строке
        let textBeforeCaret = text.prefix(caretPosition)
        let cleanedBeforeCaret = textBeforeCaret.replacingOccurrences(of: " ", with: "")
        let digitCountBeforeCaret = cleanedBeforeCaret.filter { $0.isNumber || $0 == "." }.count
        
        // Находим позицию в отформатированной строке
        var newPosition = 0
        var digitCount = 0
        for (index, char) in formatted.enumerated() {
            if char.isNumber || char == "." {
                if digitCount == digitCountBeforeCaret {
                    newPosition = index + 1
                    break
                }
                digitCount += 1
            }
        }
        
        // Если не нашли точную позицию, ставим в конец
        if newPosition == 0 && digitCountBeforeCaret > 0 {
            newPosition = formatted.count
        }
        
        caretPosition = min(newPosition, formatted.count)
        return formatted
    }
    
    // Простая версия форматирования без сохранения позиции (для обратной совместимости)
    static func formatForInput(_ text: String) -> String {
        let cleaned = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        
        guard let decimal = Decimal(string: cleaned, locale: Locale(identifier: "en_US")) else {
            return text
        }
        
        return format(decimal)
    }
    
    // Валидация: максимум 2 знака после десятичного разделителя
    static func validateDecimalPlaces(_ text: String) -> Bool {
        let cleaned = text.replacingOccurrences(of: " ", with: "")
        if let dotIndex = cleaned.firstIndex(of: ".") {
            let afterDot = String(cleaned[cleaned.index(after: dotIndex)...])
            return afterDot.count <= 2
        }
        return true
    }

    /// Returns true if `amount` is within the accepted transaction range: (0, 999_999_999.99].
    /// Does NOT check decimal places — use `validateDecimalPlaces` for that.
    static func validate(_ amount: Decimal) -> Bool {
        let max = Decimal(string: "999999999.99")!
        return amount > 0 && amount <= max
    }
}
