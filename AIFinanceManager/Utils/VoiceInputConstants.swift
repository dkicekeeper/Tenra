//
//  VoiceInputConstants.swift
//  AIFinanceManager
//
//  Created on 2026-01-18
//

import Foundation
import AVFAudio

/// Константы для системы голосового ввода
enum VoiceInputConstants {
    // MARK: - Задержки и таймауты

    /// Задержка перед финализацией транскрипции (миллисекунды)
    /// Используется для ожидания окончательного результата распознавания речи
    static let finalizationDelayMs: UInt64 = 350

    /// Задержка перед остановкой аудио-движка (миллисекунды)
    /// Даёт время на корректное завершение записи
    static let audioEngineStopDelayMs: UInt64 = 300

    /// Задержка перед автостартом записи при открытии view (миллисекунды)
    static let autoStartDelayMs: UInt64 = 100

    /// Задержка для debounce валидации (миллисекунды)
    static let validationDebounceMs: UInt64 = 300

    // MARK: - Парсинг чисел

    /// Максимальное число, которое можно распознать словами (например, "девять тысяч девятьсот девяносто девять")
    static let maxWordNumberValue = 9999

    /// Минимальное допустимое значение суммы
    static let minAmountValue: Decimal = 0.01

    /// Максимальное допустимое значение суммы
    static let maxAmountValue: Decimal = 999_999_999

    // MARK: - Скоринг счетов

    /// Порог разницы в скоре для уверенного выбора счета
    /// Если разница между лучшим и вторым кандидатом меньше этого значения,
    /// счет не выбирается автоматически и требуется подтверждение пользователя
    static let accountScoreAmbiguityThreshold = 5

    /// Вес точного совпадения имени счета
    static let accountExactMatchScore = 20

    /// Вес совпадения по паттерну ("со счета [name]")
    static let accountPatternMatchScore = 30

    /// Вес совпадения алиаса
    static let accountAliasMatchScore = 10

    /// Вес за каждый совпавший токен
    static let accountTokenMatchScore = 5

    // MARK: - UI параметры

    /// Максимальное количество строк для поля описания
    static let descriptionMaxLines = 6

    /// Минимальное количество строк для поля описания
    static let descriptionMinLines = 3

    /// Максимальная высота скролла для live-транскрипции
    static let transcriptionMaxHeight: CGFloat = 200

    // MARK: - Аудио параметры

    /// Размер буфера для аудио (семплы)
    static let audioBufferSize: AVAudioFrameCount = 1024

    // MARK: - Voice Activity Detection (VAD)

    /// Порог тишины в децибелах (dB)
    /// Значения ниже этого порога считаются тишиной
    /// Типичный диапазон: от -50 (очень чувствительный) до -30 (менее чувствительный)
    nonisolated static let vadSilenceThresholdDb: Float = -40.0

    /// Продолжительность тишины для автоматической остановки (секунды)
    /// Запись остановится после этой продолжительности непрерывной тишины
    nonisolated static let vadSilenceDuration: TimeInterval = 2.5

    /// Минимальная продолжительность речи перед включением VAD (секунды)
    /// Предотвращает ложные срабатывания в начале записи
    nonisolated static let vadMinimumSpeechDuration: TimeInterval = 1.0

    /// Включить/выключить Voice Activity Detection
    /// Если true, запись автоматически остановится после тишины
    /// Если false, пользователь должен вручную остановить запись
    static let vadEnabled: Bool = true

    // MARK: - Debug

    /// Флаг для включения детального логирования парсинга
    nonisolated static let enableParsingDebugLogs = true

    /// Префикс для debug-логов
    static let debugLogPrefix = "🔍 [VoiceInput]"
}
