//
//  PDFService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import PDFKit
@preconcurrency import Vision
import UIKit

struct OCRResult {
    let fullText: String
    let pageTexts: [String] // Для дебага - текст каждой страницы
    let structuredRows: [[String]]? // Структурированные строки таблицы (если найдены)
}

/// Структура для хранения распознанного текста с координатами
struct TextObservation {
    let text: String
    let boundingBox: CGRect // Координаты в системе Vision (0-1) или PDFKit (абсолютные)
    let confidence: Float
}

/// Структура для хранения текстового блока из PDFKit
struct PDFTextBlock {
    let text: String
    let boundingBox: CGRect // Координаты в системе PDFKit страницы
}

class PDFService {
    static let shared = PDFService()
    
    private init() {}
    
    func extractText(
        from url: URL,
        progressCallback: ((Int, Int) -> Void)? = nil
    ) async throws -> OCRResult {
        // Проверяем, что файл существует и доступен
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw PDFError.invalidDocument
        }
        
        // Начинаем доступ к файлу, если это security-scoped resource
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        // Сначала пытаемся открыть PDF документ
        guard let pdfDocument = PDFDocument(url: url) else {
            
            // Пытаемся прочитать данные напрямую
            if let data = try? Data(contentsOf: url) {
                if let pdfFromData = PDFDocument(data: data) {
                    // Если получилось открыть через Data, используем этот документ
                    return try await extractText(from: pdfFromData, progressCallback: progressCallback)
                }
            }
            
            throw PDFError.invalidDocument
        }
        
        return try await extractText(from: pdfDocument, progressCallback: progressCallback)
    }
    
    private func extractText(
        from pdfDocument: PDFDocument,
        progressCallback: ((Int, Int) -> Void)?
    ) async throws -> OCRResult {
        let pageCount = pdfDocument.pageCount
        var fullText = ""
        var pageTexts: [String] = []
        
        
        // Сначала пытаемся извлечь текст через PDFKit (для текстовых PDF)
        var hasAnyText = false
        for pageIndex in 0..<pageCount {
            // Обновляем прогресс для текстовых PDF
            if let callback = progressCallback {
                callback(pageIndex + 1, pageCount)
            }

            guard let page = pdfDocument.page(at: pageIndex) else {
                pageTexts.append("")
                continue
            }

            // Прямое извлечение текста (для текстовых PDF)
            if let pageText = page.string, !pageText.isEmpty {
                let trimmedPageText = pageText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !trimmedPageText.isEmpty {
                    fullText += pageText + "\n\n"
                    pageTexts.append(trimmedPageText)
                    hasAnyText = true
                } else {
                    pageTexts.append("")
                }
            } else {
                pageTexts.append("")
            }
        }
        
        // Если найден текст, извлекаем структуру через PDFKit с bounding boxes
        if hasAnyText {
            let trimmedText = fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            // Извлекаем структуру из PDFKit с использованием bounding boxes
            var allStructuredRows: [[String]] = []
            
            for pageIndex in 0..<pageCount {
                guard let page = pdfDocument.page(at: pageIndex) else { continue }
                let pageBounds = page.bounds(for: .mediaBox)
                
                // Извлекаем текст с координатами со страницы
                let textBlocks = extractTextBlocksWithBoundingBoxes(from: page, pageBounds: pageBounds)
                
                if !textBlocks.isEmpty {
                    
                    // Структурируем текст по координатам
                    let pageStructuredRows = structurePDFTextBlocks(textBlocks, pageBounds: pageBounds)
                    if !pageStructuredRows.isEmpty {
                        allStructuredRows.append(contentsOf: pageStructuredRows)
                    }
                }
            }
            
            
            // Финальный прогресс уже показан в цикле, просто возвращаем результат
            return OCRResult(
                fullText: trimmedText,
                pageTexts: pageTexts,
                structuredRows: allStructuredRows.isEmpty ? nil : allStructuredRows
            )
        }
        
        // Если текста нет, используем OCR через Vision с координатами
        return try await performStructuredOCR(
            from: pdfDocument,
            progressCallback: progressCallback
        )
    }
    
    /// Выполняет OCR с извлечением структуры таблицы через координаты
    private func performStructuredOCR(
        from pdfDocument: PDFDocument,
        progressCallback: ((Int, Int) -> Void)?
    ) async throws -> OCRResult {
        let pageCount = pdfDocument.pageCount
        var fullText = ""
        var pageTexts: [String] = []
        var allObservations: [TextObservation] = []
        var allStructuredRows: [[String]] = []
        
        // Обрабатываем каждую страницу
        for pageIndex in 0..<pageCount {
            // Обновляем прогресс (на main thread)
            if let callback = progressCallback {
                callback(pageIndex + 1, pageCount)
            }

            guard let page = pdfDocument.page(at: pageIndex) else {
                pageTexts.append("")
                continue
            }

            // Рендерим страницу PDF в изображение
            let pageRect = page.bounds(for: .mediaBox)
            // Увеличиваем разрешение для лучшего качества OCR (2x)
            let scale: CGFloat = 2.0
            let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)
            
            let renderer = UIGraphicsImageRenderer(size: scaledSize)
            
            let image = renderer.image { context in
                context.cgContext.saveGState()
                context.cgContext.translateBy(x: 0, y: scaledSize.height)
                context.cgContext.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: context.cgContext)
                context.cgContext.restoreGState()
            }
            
            guard let cgImage = image.cgImage else {
                pageTexts.append("")
                continue
            }
            
            // Выполняем OCR с получением координат
            let (pageText, observations) = try await recognizeTextWithCoordinates(from: cgImage, pageSize: scaledSize)
            pageTexts.append(pageText)
            fullText += pageText + "\n\n"
            
            // Сохраняем наблюдения для структурирования
            allObservations.append(contentsOf: observations)
            
            // Пытаемся структурировать текст текущей страницы
            let pageStructuredRows = structureObservations(observations, pageSize: scaledSize)
            if !pageStructuredRows.isEmpty {
                allStructuredRows.append(contentsOf: pageStructuredRows)
            }
            
        }
        
        // Финальный прогресс
        if let callback = progressCallback {
            callback(pageCount, pageCount)
        }
        
        let trimmedText = fullText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        
        guard !trimmedText.isEmpty else {
            throw PDFError.noTextFound
        }
        
        
        return OCRResult(
            fullText: trimmedText,
            pageTexts: pageTexts,
            structuredRows: allStructuredRows.isEmpty ? nil : allStructuredRows
        )
    }
    
    /// Извлекает текст с bounding boxes из PDFPage
    /// Использует selectionsByLine для получения строк с их координатами
    private func extractTextBlocksWithBoundingBoxes(from page: PDFPage, pageBounds: CGRect) -> [PDFTextBlock] {
        var textBlocks: [PDFTextBlock] = []
        
            // Получаем весь текст страницы как selection
            guard let fullSelection = page.selection(for: pageBounds),
                  let fullText = fullSelection.string,
                  !fullText.isEmpty else {
                return textBlocks
            }
            
            
            // Используем selectionsByLine для получения строк с их координатами
            // Это самый надежный метод, который PDFKit предоставляет для получения координат
            let lineSelections = fullSelection.selectionsByLine()
            
            
            // Для каждой строки извлекаем слова с их приблизительными позициями
            for lineSelection in lineSelections {
                guard let lineTextRaw = lineSelection.string else { continue }
                let lineText = lineTextRaw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            
            if lineText.isEmpty {
                continue
            }
            
            // Получаем bounding box строки
            let lineBounds = lineSelection.bounds(for: page)
            
            // Разбиваем строку на слова
            let words = lineText.components(separatedBy: CharacterSet.whitespacesAndNewlines)
                .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            if words.isEmpty {
                continue
            }
            
            // Для табличных строк (с разделителями или датами) разбиваем на части
            if lineText.contains("|") || isTableRow(lineText) {
                // Для строк с разделителями "|" разбиваем по разделителю
                if lineText.contains("|") {
                    let parts = lineText.components(separatedBy: "|")
                        .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    
                    if parts.count >= 2 {
                        // Распределяем части равномерно по ширине строки
                        let partWidth = lineBounds.width / CGFloat(parts.count)
                        var currentX = lineBounds.minX
                        
                        for part in parts {
                            if !part.isEmpty {
                                let partBounds = CGRect(
                                    x: currentX,
                                    y: lineBounds.minY,
                                    width: partWidth,
                                    height: lineBounds.height
                                )
                                textBlocks.append(PDFTextBlock(text: part, boundingBox: partBounds))
                                currentX += partWidth
                            }
                        }
                        continue
                    }
                }
                
                // Для табличных строк без разделителей используем равномерное распределение слов
                let wordWidth = lineBounds.width / CGFloat(words.count)
                var currentX = lineBounds.minX
                
                for word in words {
                    let wordBounds = CGRect(
                        x: currentX,
                        y: lineBounds.minY,
                        width: wordWidth,
                        height: lineBounds.height
                    )
                    textBlocks.append(PDFTextBlock(text: word, boundingBox: wordBounds))
                    currentX += wordWidth
                }
            } else {
                // Для обычных строк также разбиваем на слова с равномерным распределением
                // Это даст нам структуру для группировки по колонкам
                if words.count > 1 {
                    let wordWidth = lineBounds.width / CGFloat(words.count)
                    var currentX = lineBounds.minX
                    
                    for word in words {
                        let wordBounds = CGRect(
                            x: currentX,
                            y: lineBounds.minY,
                            width: wordWidth,
                            height: lineBounds.height
                        )
                        textBlocks.append(PDFTextBlock(text: word, boundingBox: wordBounds))
                        currentX += wordWidth
                    }
                } else {
                    // Одно слово - используем bounding box всей строки
                    textBlocks.append(PDFTextBlock(text: lineText, boundingBox: lineBounds))
                }
            }
        }
        
        return textBlocks
    }
    
    /// Проверяет, является ли строка строкой таблицы
    private func isTableRow(_ text: String) -> Bool {
        // Проверяем наличие даты в формате DD.MM.YYYY
        let hasDate = text.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil
        // Проверяем наличие чисел (суммы)
        let hasNumbers = text.range(of: #"\d+[\s,\.]\d+"#, options: .regularExpression) != nil
        // Не заголовок
        let isHeader = text.uppercased().contains("ДАТА") && text.uppercased().contains("ОПЕРАЦИЯ")
        
        return (hasDate || hasNumbers) && !isHeader && text.count > 10
    }
    
    /// Структурирует текст из PDFKit по координатам в строки и колонки
    private func structurePDFTextBlocks(_ textBlocks: [PDFTextBlock], pageBounds: CGRect) -> [[String]] {
        guard !textBlocks.isEmpty else { return [] }
        
        
        // Группируем по строкам (Y координаты)
        // В PDFKit координаты: (0,0) в нижнем левом углу, Y увеличивается вверх
        // Для удобства конвертируем в координаты, где (0,0) в верхнем левом углу, Y растет вниз
        let absoluteBlocks = textBlocks.map { block -> (text: String, x: CGFloat, y: CGFloat, width: CGFloat, box: CGRect) in
            let bounds = block.boundingBox
            // Конвертируем Y: в PDFKit Y растет снизу вверх, нам нужно сверху вниз
            // Используем midY для среднего Y координаты элемента
            let convertedY = pageBounds.height - bounds.midY
            return (
                text: block.text,
                x: bounds.midX,  // X остается таким же (растет слева направо)
                y: convertedY,   // Y конвертирован (теперь растет сверху вниз)
                width: bounds.width,
                box: bounds
            )
        }
        
        // Находим среднюю высоту текста для определения порога строки
        let avgHeight = absoluteBlocks.map { $0.box.height }.reduce(0, +) / CGFloat(absoluteBlocks.count)
        let rowTolerance = max(avgHeight * 0.5, pageBounds.height * 0.015) // Адаптивный порог
        
        
        // Сортируем блоки сверху вниз (по Y)
        let sortedBlocks = absoluteBlocks.sorted { $0.y < $1.y }
        
        // Группируем по строкам
        var rowGroups: [[(text: String, x: CGFloat, y: CGFloat, width: CGFloat, box: CGRect)]] = []
        
        for block in sortedBlocks {
            // Ищем группу строк с близкими Y координатами
            if let rowIndex = rowGroups.firstIndex(where: { row in
                guard let firstBlock = row.first else { return false }
                return abs(firstBlock.y - block.y) <= rowTolerance
            }) {
                rowGroups[rowIndex].append(block)
            } else {
                // Создаем новую группу строк
                rowGroups.append([block])
            }
        }
        
        
        // Сортируем элементы в каждой строке по X (слева направо)
        for i in 0..<rowGroups.count {
            rowGroups[i].sort { $0.x < $1.x }
        }
        
        // Формируем структурированные строки
        var structuredRows: [[String]] = []
        
        for row in rowGroups {
            guard row.count > 1 else { continue } // Пропускаем строки с одним элементом
            
            // Группируем элементы на основе промежутков между X координатами
            var rowCells: [String] = []
            var currentColumn: [String] = []
            var lastX: CGFloat? = nil
            
            // Вычисляем средний промежуток между соседними элементами для адаптивного порога
            var gaps: [CGFloat] = []
            for i in 0..<row.count - 1 {
                let gap = row[i + 1].x - row[i].x
                gaps.append(gap)
            }
            let avgGap = gaps.isEmpty ? pageBounds.width * 0.1 : gaps.reduce(0, +) / CGFloat(gaps.count)
            let minColumnGap = max(avgGap * 0.3, pageBounds.width * 0.03) // Минимальный промежуток для новой колонки
            
            for block in row {
                if let prevX = lastX {
                    let gap = block.x - prevX
                    if gap > minColumnGap {
                        // Новый столбец - сохраняем предыдущий
                        if !currentColumn.isEmpty {
                            rowCells.append(currentColumn.joined(separator: " "))
                            currentColumn = []
                        }
                    }
                }
                
                currentColumn.append(block.text)
                lastX = block.x
            }
            
            // Добавляем последнюю колонку
            if !currentColumn.isEmpty {
                rowCells.append(currentColumn.joined(separator: " "))
            }
            
            // Проверяем, является ли строка транзакцией (содержит дату)
            let rowText = rowCells.joined(separator: " ")
            let hasDate = rowText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil
            
            // Также проверяем, не является ли это заголовком таблицы
            let isHeader = rowText.uppercased().contains("ДАТА") && rowText.uppercased().contains("ОПЕРАЦИЯ")
            
            if !isHeader && hasDate && rowCells.count >= 2 {
                // Удаляем пустые колонки с конца
                while let last = rowCells.last, last.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    rowCells.removeLast()
                }
                
                if !rowCells.isEmpty {
                    structuredRows.append(rowCells)
                }
            }
        }
        
        
        if !structuredRows.isEmpty {
        }
        
        return structuredRows
    }
    
    /// Структурирует наблюдения текста в строки таблицы на основе координат
    private func structureObservations(_ observations: [TextObservation], pageSize: CGSize) -> [[String]] {
        guard !observations.isEmpty else { return [] }
        
        
        // Конвертируем координаты Vision в абсолютные координаты
        // Vision использует координаты 0-1, где (0,0) - нижний левый угол
        let absoluteObservations = observations.map { obs -> (text: String, x: CGFloat, y: CGFloat, width: CGFloat, box: CGRect) in
            let absRect = CGRect(
                x: obs.boundingBox.origin.x * pageSize.width,
                y: (1.0 - obs.boundingBox.origin.y - obs.boundingBox.height) * pageSize.height, // Инвертируем Y
                width: obs.boundingBox.width * pageSize.width,
                height: obs.boundingBox.height * pageSize.height
            )
            return (
                text: obs.text,
                x: absRect.midX,
                y: absRect.midY,
                width: absRect.width,
                box: absRect
            )
        }
        
        // Группируем по строкам (Y координаты)
        // Используем адаптивный порог для группировки строк
        // Сначала находим среднюю высоту текста для определения порога
        let avgHeight = absoluteObservations.map { $0.box.height }.reduce(0, +) / CGFloat(absoluteObservations.count)
        let rowTolerance = max(avgHeight * 0.5, pageSize.height * 0.02) // Адаптивный порог
        
        
        // Сортируем наблюдения сверху вниз (по Y)
        let sortedObs = absoluteObservations.sorted { $0.y > $1.y }
        
        // Группируем по строкам
        var rowGroups: [[(text: String, x: CGFloat, y: CGFloat, width: CGFloat, box: CGRect)]] = []
        
        for obs in sortedObs {
            // Ищем группу строк с близкими Y координатами
            if let rowIndex = rowGroups.firstIndex(where: { row in
                guard let firstObs = row.first else { return false }
                let yDiff = abs(firstObs.y - obs.y)
                return yDiff <= rowTolerance
            }) {
                rowGroups[rowIndex].append(obs)
            } else {
                // Создаем новую группу строк
                rowGroups.append([obs])
            }
        }
        
        
        // Определяем колонки на основе X координат
        // Собираем все X координаты для определения позиций колонок
        var allXPositions: [CGFloat] = []
        for row in rowGroups {
            for obs in row {
                allXPositions.append(obs.x)
            }
        }
        
        // Сортируем и находим уникальные позиции колонок (кластеризуем близкие X)
        let sortedX = allXPositions.sorted()
        var columnPositions: [CGFloat] = []
        let columnTolerance = pageSize.width * 0.05 // 5% ширины страницы
        
        for x in sortedX {
            if columnPositions.isEmpty {
                columnPositions.append(x)
            } else {
                // Проверяем, не слишком ли близко к существующим колонкам
                let isClose = columnPositions.contains { abs($0 - x) <= columnTolerance }
                if !isClose {
                    columnPositions.append(x)
                }
            }
        }
        
        columnPositions.sort()
        
        // Сортируем элементы в каждой строке по X (слева направо)
        for i in 0..<rowGroups.count {
            rowGroups[i].sort { $0.x < $1.x }
        }
        
        // Формируем структурированные строки
        var structuredRows: [[String]] = []
        
        // Для более надежной работы с таблицами, используем упрощенный подход:
        // Просто группируем текст по строкам (Y) и сортируем по X внутри строки
        // Это даст нам структуру, близкую к исходной таблице
        
        for row in rowGroups {
            // Для каждой строки формируем массив колонок
            // Используем упрощенный подход: просто берем все элементы строки по порядку
            var rowCells: [String] = []
            
            // Более умная группировка: разбиваем элементы на колонки на основе промежутков между X координатами
            if row.count == 1 {
                // Если в строке только один элемент, это может быть продолжение предыдущей строки
                // Или заголовок - пропускаем для упрощения
                continue
            }
            
            // Группируем элементы по колонкам на основе промежутков между X
            var currentColumn: [String] = []
            var lastX: CGFloat? = nil
            let minColumnGap = pageSize.width * 0.08 // Минимальный промежуток для новой колонки (8% ширины)
            
            for obs in row {
                if let prevX = lastX {
                    let gap = obs.x - prevX
                    if gap > minColumnGap {
                        // Новый столбец - сохраняем предыдущий
                        if !currentColumn.isEmpty {
                            rowCells.append(currentColumn.joined(separator: " "))
                            currentColumn = []
                        }
                    }
                }
                
                currentColumn.append(obs.text)
                lastX = obs.x
            }
            
            // Добавляем последнюю колонку
            if !currentColumn.isEmpty {
                rowCells.append(currentColumn.joined(separator: " "))
            }
            
            // Проверяем, является ли строка транзакцией (содержит дату)
            let rowText = rowCells.joined(separator: " ")
            let hasDate = rowText.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) != nil
            
            // Также проверяем, не является ли это заголовком таблицы
            let isHeader = rowText.uppercased().contains("ДАТА") && rowText.uppercased().contains("ОПЕРАЦИЯ")
            
            if !isHeader && hasDate && rowCells.count >= 3 {
                // Удаляем пустые колонки с конца
                while let last = rowCells.last, last.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                    rowCells.removeLast()
                }
                
                if !rowCells.isEmpty {
                    structuredRows.append(rowCells)
                }
            }
        }
        
        
        if !structuredRows.isEmpty {
        }
        
        return structuredRows
    }
    
    /// Распознает текст с получением координат для структурирования
    private func recognizeTextWithCoordinates(from cgImage: CGImage, pageSize: CGSize) async throws -> (text: String, observations: [TextObservation]) {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var recognizedStrings: [String] = []
                var textObservations: [TextObservation] = []

                // Guard against double-resume: the completion handler fires
                // on success, but handler.perform() can also throw independently.
                var didResume = false

                let request = VNRecognizeTextRequest { request, error in
                    guard !didResume else { return }
                    didResume = true

                    if let error = error {
                        continuation.resume(throwing: PDFError.ocrError(error.localizedDescription))
                        return
                    }

                    guard let observations = request.results as? [VNRecognizedTextObservation] else {
                        continuation.resume(returning: ("", []))
                        return
                    }

                    let sortedObservations = observations.sorted { obs1, obs2 in
                        let y1 = 1.0 - obs1.boundingBox.midY
                        let y2 = 1.0 - obs2.boundingBox.midY

                        if abs(y1 - y2) > 0.02 {
                            return y1 < y2
                        } else {
                            return obs1.boundingBox.midX < obs2.boundingBox.midX
                        }
                    }

                    for observation in sortedObservations {
                        guard let topCandidate = observation.topCandidates(1).first else {
                            continue
                        }

                        let text = topCandidate.string
                        recognizedStrings.append(text)

                        textObservations.append(TextObservation(
                            text: text,
                            boundingBox: observation.boundingBox,
                            confidence: topCandidate.confidence
                        ))
                    }

                    let fullText = recognizedStrings.joined(separator: " ")
                    continuation.resume(returning: (fullText, textObservations))
                }

                request.recognitionLanguages = ["ru-RU", "en-US"]
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true

                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

                do {
                    try handler.perform([request])
                } catch {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(throwing: PDFError.ocrError(error.localizedDescription))
                }
            }
        }
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
