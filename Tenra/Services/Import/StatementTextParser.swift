//
//  StatementTextParser.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation

nonisolated class StatementTextParser {
    /// Парсит распознанный текст выписки Alatau City Bank в CSVFile формат
    /// Если structuredRows предоставлены, использует их напрямую, иначе парсит текст
    static func parseStatementToCSV(_ text: String, structuredRows: [[String]]? = nil) -> CSVFile {
        
        // Заголовки CSV (аналогично стандартному CSV импорту)
        let headers = ["Дата", "Тип", "Сумма", "Валюта", "Описание", "Счет", "Категория", "Подкатегория"]
        
        var transactions: [[String]] = []
        var currentAccount: String = ""
        
        // Если есть структурированные строки, используем их
        if let structuredRows = structuredRows, !structuredRows.isEmpty {
            return parseStructuredRows(structuredRows, headers: headers, text: text)
        }
        
        
        // Разбиваем текст на строки
        let allLines = text.components(separatedBy: .newlines)
        var lines: [String] = []
        var currentLine = ""
        var inTableRow = false
        
        // Объединяем многострочные строки таблицы
        for line in allLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Проверяем, является ли строка частью таблицы (содержит "|")
            let isTableRow = trimmed.contains("|")
            
            if isTableRow {
                // Строка с разделителями таблицы
                if !currentLine.isEmpty {
                    // Сохраняем предыдущую строку
                    lines.append(currentLine.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentLine = ""
                }
                currentLine = trimmed
                inTableRow = true
            } else if inTableRow && !trimmed.isEmpty {
                // Продолжение строки таблицы (многострочная ячейка)
                currentLine += " " + trimmed
            } else if !trimmed.isEmpty {
                // Обычная строка (не таблица)
                if !currentLine.isEmpty {
                    lines.append(currentLine.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentLine = ""
                }
                lines.append(trimmed)
                inTableRow = false
            } else {
                // Пустая строка
                if !currentLine.isEmpty && inTableRow {
                    // Если мы в таблице, добавляем пробел для многострочной ячейки
                    currentLine += " "
                } else if !currentLine.isEmpty {
                    // Если не в таблице, сохраняем текущую строку
                    lines.append(currentLine.trimmingCharacters(in: .whitespacesAndNewlines))
                    currentLine = ""
                    inTableRow = false
                }
            }
        }
        
        // Сохраняем последнюю строку, если она не пустая
        if !currentLine.isEmpty {
            lines.append(currentLine.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        
        // Удаляем пустые строки
        lines = lines.filter { !$0.isEmpty }

        // Ищем начало таблицы транзакций по заголовкам
        var i = 0
        var inTransactionsTable = false // Флаг, что мы находимся в таблице транзакций
        
        // Проверяем, есть ли вообще "Транзакции по счету" в тексте (без учета регистра)
        let hasTransactionsHeader = lines.contains { line in
            let normalized = line.uppercased()
            return normalized.contains("ТРАНЗАКЦИИ ПО СЧЕТУ") || normalized.contains("ТРАНЗАКЦИИПОСЧЕТУ")
        }
        
        _ = hasTransactionsHeader
        
        while i < lines.count {
            let line = lines[i]
            
            // Ищем заголовок таблицы транзакций (может быть "Транзакции по счету:" или "Транзакции по счету")
            let normalizedLine = line.uppercased().replacingOccurrences(of: "  ", with: " ")
            if normalizedLine.contains("ТРАНЗАКЦИИ ПО СЧЕТУ") || normalizedLine.contains("ТРАНЗАКЦИИПОСЧЕТУ") || line.contains("Транзакции по счету") {
                
                // Извлекаем номер счета из строки вида "Транзакции по счету: KZ51998PB00009669873 KZT"
                let accountMatch = extractAccountFromLine(line)
                if !accountMatch.isEmpty {
                    currentAccount = accountMatch
                }
                
                // Включаем режим парсинга транзакций
                inTransactionsTable = true
                
                // Пропускаем строку с заголовком таблицы
                i += 1
                if i >= lines.count { break }
                
                // Пропускаем разделитель таблицы (строка с "| --- | --- | ...")
                if lines[i].contains("|---") {
                    i += 1
                    if i >= lines.count { break }
                }
                
                // Пропускаем строку с названиями колонок ("Дата | Операция | Детали | ...")
                if lines[i].contains("Дата") && lines[i].contains("Операция") {
                    i += 1
                    if i >= lines.count { break }
                }
                
                // Пропускаем разделитель таблицы после заголовков
                if lines[i].contains("|---") {
                    i += 1
                    if i >= lines.count { break }
                }
                
                // Продолжаем, чтобы начать парсить транзакции со следующей строки
                continue
            }
            
            // Проверяем, не закончилась ли таблица транзакций
            if inTransactionsTable && (line.contains("Сумма в обработке") || (line.contains("---") && !line.contains("|"))) {
                // Это разделитель между основной таблицей и таблицей "в обработке" или конец таблицы
                if line.contains("Сумма в обработке") {
                    // Продолжаем парсить таблицу "в обработке"
                    i += 1
                    if i >= lines.count { break }
                    
                    // Пропускаем заголовок таблицы "в обработке"
                    if i < lines.count && lines[i].contains("Дата") && lines[i].contains("Операция") {
                        i += 1
                    }
                    if i < lines.count && lines[i].contains("|---") {
                        i += 1
                    }
                } else {
                    // Конец основной таблицы, выключаем режим
                    inTransactionsTable = false
                    i += 1
                }
                continue
            }
            
            // Парсим строку транзакции только если мы находимся в таблице транзакций
            if inTransactionsTable && line.contains("|") && isTransactionLine(line) {
                
                // Если следующая строка также содержит "|" но не является новой транзакцией, это продолжение текущей
                var transactionLine = line
                var nextIndex = i + 1
                
                while nextIndex < lines.count {
                    let nextLine = lines[nextIndex]
                    if nextLine.contains("|") {
                        // Если это продолжение транзакции (нет даты), добавляем к текущей строке
                        if !isTransactionLine(nextLine) && !nextLine.contains("|---") && !nextLine.contains("Сумма в обработке") && !nextLine.contains("Транзакции по счету:") {
                            transactionLine += " " + nextLine
                            nextIndex += 1
                        } else {
                            break
                        }
                    } else {
                        break
                    }
                }
                
                if let transaction = parseTransactionLine(transactionLine, account: currentAccount) {
                    transactions.append(transaction)
                } else {
                }
                
                i = nextIndex
                continue
            }
            
            i += 1
        }
        
        // Создаем preview (первые 5 строк)
        let preview = Array(transactions.prefix(5))
        
        
        return CSVFile(headers: headers, rows: transactions, preview: preview)
    }
    
    /// Парсит структурированные строки, полученные из OCR с координатами
    private static func parseStructuredRows(_ structuredRows: [[String]], headers: [String], text: String) -> CSVFile {
        var transactions: [[String]] = []
        var currentAccount: String = ""
        
        // Ищем номер счета в тексте выписки
        currentAccount = extractAccountFromText(text)


        for row in structuredRows {
            // Пропускаем заголовки таблицы
            if row.contains("Дата") && row.contains("Операция") {
                continue
            }
            
            // Пропускаем разделители
            if row.joined().contains("---") || row.isEmpty {
                continue
            }
            
            // Пытаемся найти дату в строке (для структурированных данных проверяем наличие даты в любой колонке)
            let rowText = row.joined(separator: " ")
            let hasDate = rowText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil
            let isHeader = rowText.uppercased().contains("ДАТА") && rowText.uppercased().contains("ОПЕРАЦИЯ")
            
            if !hasDate || isHeader {
                // Если нет даты или это заголовок, пропускаем
                continue
            }
            
            // Парсим структурированную строку
            if let transaction = parseStructuredRow(row, account: currentAccount) {
                transactions.append(transaction)
            } else {
            }
        }
        
        let preview = Array(transactions.prefix(5))
        
        
        return CSVFile(headers: headers, rows: transactions, preview: preview)
    }
    
    /// Извлекает номер счета из текста выписки
    private static func extractAccountFromText(_ text: String) -> String {
        // Ищем паттерн "Транзакции по счету: KZ51998PB00009669873" или "KZ51998PB00009669873 KZT"
        let accountPattern = #"KZ[0-9A-Z]{16,}"#
        if let range = text.range(of: accountPattern, options: .regularExpression) {
            return String(text[range])
        }
        return ""
    }
    
    /// Парсит структурированную строку (массив колонок) в формат CSV
    private static func parseStructuredRow(_ row: [String], account: String) -> [String]? {
        guard row.count >= 3 else {
            return nil
        }
        
        // Ищем дату в строке
        var dateString = ""
        var dateIndex = -1
        
        for (index, cell) in row.enumerated() {
            let extractedDate = extractDate(from: cell)
            if !extractedDate.isEmpty {
                dateString = extractedDate
                dateIndex = index
                break
            }
        }
        
        guard !dateString.isEmpty else {
            return nil
        }
        
        // Ищем тип операции
        var transactionType = "expense"
        var operationIndex = -1
        
        for (index, cell) in row.enumerated() {
            let normalized = cell.uppercased()
            if normalized.contains("ПОКУПКА") || normalized.contains("ПОПОЛНЕНИЕ") || normalized.contains("ПЕРЕВОД") {
                transactionType = mapOperationType(cell)
                operationIndex = index
                break
            }
        }
        
        // Ищем сумму (числовое значение)
        var amountString = ""
        var currency = "KZT"
        var amountIndex = -1
        
        for (index, cell) in row.enumerated() {
            let cleaned = cell.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
            if isNumericString(cleaned) && Double(cleaned) != nil {
                amountString = cleaned
                amountIndex = index
                // Проверяем следующую колонку на валюту
                if index + 1 < row.count {
                    let nextCell = row[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if ["KZT", "USD", "EUR", "RUB", "UAH"].contains(nextCell.uppercased()) {
                        currency = nextCell.uppercased()
                    }
                }
                break
            }
        }
        
        guard !amountString.isEmpty else {
            return nil
        }
        
        // Формируем описание из оставшихся колонок (кроме даты, типа, суммы, валюты)
        var descriptionParts: [String] = []
        let usedIndices = [dateIndex, operationIndex, amountIndex].filter { $0 >= 0 }
        
        for (index, cell) in row.enumerated() {
            if !usedIndices.contains(index) && !cell.isEmpty {
                let trimmed = cell.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Проверяем, не является ли это валютой
                if !["KZT", "USD", "EUR", "RUB", "UAH"].contains(trimmed.uppercased()) {
                    descriptionParts.append(trimmed)
                }
            }
        }
        
        let description = cleanDescription(descriptionParts.joined(separator: " "))
        
        return [
            dateString,           // Дата
            transactionType,      // Тип
            amountString,         // Сумма
            currency,             // Валюта
            description,          // Описание
            account,              // Счет
            "",                   // Категория (заполнится при маппинге)
            ""                    // Подкатегория (заполнится при маппинге)
        ]
    }
    
    /// Проверяет, является ли строка строкой транзакции
    private static func isTransactionLine(_ line: String) -> Bool {
        // Проверяем наличие даты в формате DD.MM.YYYY
        // Также проверяем, что строка содержит разделитель "|" и не является разделителем таблицы
        guard line.contains("|") && !line.contains("|---") else {
            return false
        }
        
        // Проверяем наличие даты в формате DD.MM.YYYY
        let datePattern = #"\d{2}\.\d{2}\.\d{4}"#
        let hasDate = line.range(of: datePattern, options: .regularExpression) != nil
        
        // Также проверяем, что это не заголовок таблицы
        let isHeader = line.contains("Дата") && line.contains("Операция")
        
        return hasDate && !isHeader
    }
    
    /// Извлекает номер счета из строки "Транзакции по счету: KZ51998PB00009669873 KZT"
    private static func extractAccountFromLine(_ line: String) -> String {
        // Ищем паттерн: KZ + цифры и буквы
        let pattern = #"KZ[0-9A-Z]{16,}"#
        if let range = line.range(of: pattern, options: .regularExpression) {
            return String(line[range])
        }
        return ""
    }
    
    /// Парсит строку транзакции из таблицы
    /// Формат таблицы: Дата | Операция | Детали | Сумма | Валюта операции | Приход в валюте счета | Расход в валюте счета
    /// Пример: "08.01.2026 17:19:46 | Покупка | YANDEX.GO Референс: 600815665697 Код авторизации: 681997 | 2 500 | KZT | 0 | 2 500"
    private static func parseTransactionLine(_ line: String, account: String) -> [String]? {
        // Разбиваем строку по "|"
        let parts = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
        
        // Минимум должно быть 7 колонок (Дата, Операция, Детали, Сумма, Валюта, Приход, Расход)
        // Но описание может занимать несколько частей, если оно длинное
        guard parts.count >= 7 else {
            return nil
        }
        
        // Часть 0: Дата и время (может быть на нескольких строках)
        let dateTimePart = parts[0].replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "  ", with: " ")
        let dateString = extractDate(from: dateTimePart)
        
        guard !dateString.isEmpty else {
            return nil
        }
        
        // Часть 1: Тип операции (Покупка, Пополнение, Перевод)
        let operationType = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        let transactionType = mapOperationType(operationType)
        
        // Часть 2: Детали (описание)
        // Описание может занимать несколько частей, если оно длинное
        // Проверяем части начиная с индекса 2, пока не найдем числовое значение (сумму)
        var descriptionParts: [String] = []
        var amountIndex = 2
        var foundAmount = false
        
        // Ищем, где начинается сумма (первая часть, содержащая только числа)
        for i in 2..<parts.count {
            let part = parts[i].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
            if isNumericString(part) && !part.isEmpty {
                // Это сумма
                amountIndex = i
                foundAmount = true
                break
            } else {
                // Это часть описания
                descriptionParts.append(parts[i])
            }
        }
        
        guard foundAmount else {
            return nil
        }
        
        // Объединяем части описания
        let detailsPart = descriptionParts.joined(separator: " ")
        
        // Очищаем описание от "Референс:" и "Код авторизации:"
        let description = cleanDescription(detailsPart)
        
        // Индексы колонок (после описания идет сумма)
        // amountIndex - это индекс суммы
        let currencyIndex = amountIndex + 1
        let incomeIndex = amountIndex + 2
        let expenseIndex = amountIndex + 3
        
        // Проверяем корректность индексов
        guard parts.count > expenseIndex else {
            return nil
        }
        
        // Извлекаем сумму
        var amountString = parts[amountIndex].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        
        // Извлекаем валюту
        var currency = parts[safe: currencyIndex]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "KZT"
        
        // Определяем сумму на основе типа операции и колонок Приход/Расход
        let incomeAmount = parseAmount(parts[safe: incomeIndex] ?? "0")
        let expenseAmount = parseAmount(parts[safe: expenseIndex] ?? "0")
        
        // Используем сумму из колонки Приход/Расход, если она больше нуля
        // Это более надежно, так как там уже конвертированная сумма в валюте счета
        if transactionType == "income" && incomeAmount > 0 {
            amountString = String(format: "%.2f", incomeAmount)
        } else if expenseAmount > 0 {
            amountString = String(format: "%.2f", expenseAmount)
        }
        
        // Если сумма все еще пустая или невалидная, используем исходное значение
        if amountString.isEmpty || Double(amountString) == nil {
            amountString = parts[amountIndex].replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
            if Double(amountString) == nil {
                return nil
            }
        }
        
        // Если валюта пустая, используем валюту по умолчанию
        if currency.isEmpty {
            currency = "KZT"
        }
        
        // Формируем строку транзакции в формате CSV
        return [
            dateString,           // Дата (DD.MM.YYYY)
            transactionType,      // Тип (income/expense/internal)
            amountString,         // Сумма
            currency,             // Валюта
            description,          // Описание (очищенное)
            account,              // Счет
            "",                   // Категория (пусто, будет заполнено при маппинге)
            ""                    // Подкатегория (пусто, будет заполнено при маппинге)
        ]
    }
    
    /// Извлекает дату из строки в формате "08.01.2026 17:19:46" или "08.01.2026"
    private static func extractDate(from dateTimeString: String) -> String {
        // Ищем паттерн даты DD.MM.YYYY
        let datePattern = #"(\d{2})\.(\d{2})\.(\d{4})"#
        let regex = try? NSRegularExpression(pattern: datePattern)
        let range = NSRange(dateTimeString.startIndex..., in: dateTimeString)
        
        if let match = regex?.firstMatch(in: dateTimeString, range: range) {
            let dayRange = Range(match.range(at: 1), in: dateTimeString)!
            let monthRange = Range(match.range(at: 2), in: dateTimeString)!
            let yearRange = Range(match.range(at: 3), in: dateTimeString)!
            
            let day = String(dateTimeString[dayRange])
            let month = String(dateTimeString[monthRange])
            let year = String(dateTimeString[yearRange])
            
            // Возвращаем в формате DD.MM.YYYY (как в CSV по умолчанию)
            return "\(day).\(month).\(year)"
        }
        
        return ""
    }
    
    /// Маппит тип операции из выписки в тип транзакции
    private static func mapOperationType(_ operation: String) -> String {
        let normalized = operation.uppercased()
        
        if normalized.contains("ПОКУПКА") || normalized.contains("ПОКУПКИ") {
            return "expense"
        } else if normalized.contains("ПОПОЛНЕНИЕ") || normalized.contains("ПОПОЛНЕНИЯ") {
            return "income"
        } else if normalized.contains("ПЕРЕВОД") || normalized.contains("ПЕРЕВОДЫ") {
            return "internal"
        } else if normalized.contains("СНЯТИЕ") || normalized.contains("СНЯТИЯ") {
            return "expense"
        } else if normalized.contains("КОМИССИЯ") || normalized.contains("КОМИССИИ") {
            return "expense"
        }
        
        return "expense" // По умолчанию
    }
    
    /// Очищает описание от технических данных
    private static func cleanDescription(_ description: String) -> String {
        var cleaned = description
        
        // Удаляем "Референс: ..."
        let refPattern = #"(?i)Референс:\s*[^\n]+"#
        cleaned = cleaned.replacingOccurrences(of: refPattern, with: "", options: .regularExpression)
        
        // Удаляем "Код авторизации: ..."
        let authPattern = #"(?i)Код авторизации:\s*[^\n]+"#
        cleaned = cleaned.replacingOccurrences(of: authPattern, with: "", options: .regularExpression)
        
        // Удаляем лишние пробелы и переносы строк
        cleaned = cleaned.replacingOccurrences(of: "\n", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Парсит сумму из строки, убирая пробелы
    private static func parseAmount(_ amountString: String) -> Double {
        let cleaned = amountString.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0.0
    }
    
    /// Проверяет, является ли строка числом
    private static func isNumericString(_ string: String) -> Bool {
        let cleaned = string.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) != nil
    }
}
