//
//  CSVImporter.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import os

struct CSVFile {
    let headers: [String]
    let rows: [[String]]
    let preview: [[String]]
    
    var rowCount: Int {
        rows.count
    }
}

nonisolated class CSVImporter {
    private static let logger = Logger(subsystem: "AIFinanceManager", category: "CSVImporter")

    static func parseCSV(from url: URL) throws -> CSVFile {
        
        // Проверяем, является ли URL временным файлом (уже скопированным DocumentPicker)
        let isTemporaryFile = url.path.contains(FileManager.default.temporaryDirectory.path)
        var fileURL = url
        
        // Если это не временный файл, пытаемся получить доступ к security-scoped ресурсу
        if !isTemporaryFile {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if !isAccessing {
                logger.warning("startAccessingSecurityScopedResource failed for \(url.lastPathComponent, privacy: .public)")
            }

            // Копируем файл во временную директорию для надежного доступа
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
            try? FileManager.default.removeItem(at: tempURL)

            do {
                try FileManager.default.copyItem(at: url, to: tempURL)
                fileURL = tempURL
            } catch {
                logger.warning("copyItem failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public) — falling back to original URL")
            }
        }
        
        // Читаем содержимое файла
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            // Пробуем другие кодировки
            if let contentUTF16 = try? String(contentsOf: fileURL, encoding: .utf16) {
                return try parseCSVContent(contentUTF16)
            }
            if let contentWindowsCP1251 = try? String(contentsOf: fileURL, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)))) {
                return try parseCSVContent(contentWindowsCP1251)
            }
            throw CSVImportError.invalidEncoding
        }
        
        return try parseCSVContent(content)
    }
    
    private static func parseCSVContent(_ content: String) throws -> CSVFile {

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            throw CSVImportError.emptyFile
        }

        // Парсим CSV с учетом кавычек
        let parsedLines = lines.map { parseCSVLine($0) }

        guard let headers = parsedLines.first else {
            throw CSVImportError.noHeaders
        }

        let expectedColumnCount = headers.count

        // Нормализуем строки - дополняем недостающие колонки пустыми значениями
        let rows = Array(parsedLines.dropFirst()).map { row in
            normalizeRow(row, expectedColumnCount: expectedColumnCount)
        }

        let preview = Array(rows.prefix(5))


        return CSVFile(headers: headers, rows: rows, preview: preview)
    }

    private static func normalizeRow(_ row: [String], expectedColumnCount: Int) -> [String] {
        if row.count == expectedColumnCount {
            return row
        } else if row.count < expectedColumnCount {
            // Дополняем недостающие колонки пустыми значениями
            return row + Array(repeating: "", count: expectedColumnCount - row.count)
        } else {
            // Обрезаем лишние колонки
            return Array(row.prefix(expectedColumnCount))
        }
    }
    
    /// Parses a single CSV line per RFC 4180:
    /// - Fields may be enclosed in double-quotes
    /// - Double-quotes inside a quoted field are escaped as "" (two consecutive quotes)
    /// - Commas inside quoted fields are literal (not delimiters)
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        let chars = Array(line)
        var i = 0

        while i < chars.count {
            let char = chars[i]

            if insideQuotes {
                if char == "\"" {
                    // Peek ahead: "" = escaped quote, otherwise end of quoted field
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        currentField.append("\"")
                        i += 2
                        continue
                    } else {
                        insideQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    insideQuotes = true
                } else if char == "," {
                    fields.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }
            i += 1
        }

        fields.append(currentField.trimmingCharacters(in: .whitespaces))
        return fields
    }
}

enum CSVImportError: LocalizedError {
    case fileAccessDenied
    case invalidEncoding
    case emptyFile
    case noHeaders
    case invalidFormat
    case missingDependency(String)  // ✨ Phase 11: For missing TransactionStore or other deps

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "Нет доступа к файлу"
        case .invalidEncoding:
            return "Неверная кодировка файла (требуется UTF-8)"
        case .emptyFile:
            return "Файл пуст"
        case .noHeaders:
            return "В файле отсутствуют заголовки"
        case .invalidFormat:
            return "Неверный формат CSV"
        case .missingDependency(let message):
            return "Отсутствует зависимость: \(message)"
        }
    }
}
