//
//  CategoryMLPredictor.swift
//  AIFinanceManager
//
//  Created on 2026-01-18
//

import Foundation
import CoreML

/// ML-предсказатель категорий транзакций
/// Работает как fallback для rule-based парсера
@available(iOS 14.0, *)
nonisolated class CategoryMLPredictor {

    // MARK: - Properties

    private var model: MLModel?
    private let modelName = "CategoryClassifier"

    // MARK: - Initialization

    init() {
        loadModel()
    }

    // MARK: - Public Methods

    /// Проверяет, доступна ли ML модель
    var isAvailable: Bool {
        return model != nil
    }

    /// Предсказывает категорию на основе текста описания
    /// - Parameters:
    ///   - text: Текст транзакции
    ///   - amount: Сумма транзакции (опционально, для улучшения точности)
    ///   - type: Тип операции (расход/доход)
    /// - Returns: Кортеж (категория, уверенность 0-1)
    func predict(text: String, amount: Decimal? = nil, type: TransactionType = .expense) -> (category: String?, confidence: Double) {
        guard model != nil else {
            return (nil, 0.0)
        }

        // FEATURE: ML-based category prediction (Future Enhancement)
        // Implementation steps when ML model is ready:
        // 1. Prepare training data (description → category) from transaction history
        // 2. Train model using Create ML
        // 3. Add .mlmodel file to project
        // 4. Implement prediction logic here

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif

        return (nil, 0.0)
    }

    /// Собирает данные для обучения модели
    /// - Parameters:
    ///   - transactions: Массив транзакций пользователя
    /// - Returns: CSV строка для экспорта в Create ML
    static func prepareTrainingData(from transactions: [Transaction]) -> String {
        var csv = "description,category,amount,type\n"

        for transaction in transactions {
            // Экранируем запятые и кавычки в описании
            let description = transaction.description
                .replacingOccurrences(of: "\"", with: "\"\"")

            let amount = transaction.amount
            let category = transaction.category
            let type = transaction.type == .expense ? "expense" : "income"

            csv += "\"\(description)\",\"\(category)\",\(amount),\(type)\n"
        }

        return csv
    }

    // MARK: - Private Methods

    private func loadModel() {
        // Пытаемся загрузить модель из бандла
        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
            return
        }

        do {
            model = try MLModel(contentsOf: modelURL)

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
        } catch {
            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
        }
    }
}

// MARK: - Hybrid Parser Integration

extension CategoryMLPredictor {
    /// Гибридный подход: сначала rule-based, потом ML
    /// - Parameters:
    ///   - text: Текст для парсинга
    ///   - ruleBasedCategory: Категория из rule-based парсера
    ///   - ruleBasedConfidence: Уверенность rule-based (0-1)
    ///   - amount: Сумма транзакции
    ///   - type: Тип операции
    /// - Returns: Финальная категория
    func hybridPredict(
        text: String,
        ruleBasedCategory: String?,
        ruleBasedConfidence: Double,
        amount: Decimal?,
        type: TransactionType
    ) -> String? {
        // Если rule-based уверен (нашел точное совпадение)
        if let category = ruleBasedCategory,
           category != "Другое",
           ruleBasedConfidence > 0.8 {
            return category
        }

        // Если rule-based не уверен, пробуем ML
        if isAvailable {
            let (mlCategory, mlConfidence) = predict(text: text, amount: amount, type: type)

            // Используем ML если уверенность высокая
            if let category = mlCategory, mlConfidence > 0.7 {
                #if DEBUG
                if VoiceInputConstants.enableParsingDebugLogs {
                }
                #endif
                return category
            }
        }

        // Fallback на rule-based или "Другое"
        return ruleBasedCategory ?? "Другое"
    }
}
