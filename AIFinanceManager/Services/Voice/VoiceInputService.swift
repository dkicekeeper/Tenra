//
//  VoiceInputService.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import Speech
import AVFoundation
import AVFAudio
import Observation

enum VoiceInputError: LocalizedError {
    case speechRecognitionNotAvailable
    case speechRecognitionDenied
    case speechRecognitionRestricted
    case audioEngineError(String)
    case recognitionError(String)
    
    var errorDescription: String? {
        switch self {
        case .speechRecognitionNotAvailable:
            return "Распознавание речи недоступно на этом устройстве"
        case .speechRecognitionDenied:
            return "Доступ к распознаванию речи запрещен. Разрешите доступ в Настройках"
        case .speechRecognitionRestricted:
            return "Доступ к распознаванию речи ограничен"
        case .audioEngineError(let message):
            return "Ошибка аудио: \(message)"
        case .recognitionError(let message):
            return "Ошибка распознавания: \(message)"
        }
    }
}

/// ✅ MIGRATED 2026-02-12: Now using @Observable instead of ObservableObject
@Observable
@MainActor
class VoiceInputService: NSObject {
    var isRecording = false
    var transcribedText = ""
    var errorMessage: String?

    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer: SFSpeechRecognizer?
    private var finalTranscription: String = ""
    private var isStopping: Bool = false // Флаг для предотвращения множественных вызовов stop

    // MARK: - Voice Activity Detection

    /// Silence detector for automatic stop
    private var silenceDetector: SilenceDetector?

    /// VAD enabled flag (can be toggled by user)
    var isVADEnabled: Bool = VoiceInputConstants.vadEnabled

    // MARK: - Dynamic Context (iOS 17+)

    /// Weak references to ViewModels for contextual strings
    @ObservationIgnored weak var categoriesViewModel: CategoriesViewModel?
    @ObservationIgnored weak var accountsViewModel: AccountsViewModel?
    
    override init() {
        // Инициализируем распознаватель для русского языка
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
        recognizer?.delegate = nil // Будет установлен после super.init()
        self.speechRecognizer = recognizer
        super.init()
        // Устанавливаем delegate после super.init()
        self.speechRecognizer?.delegate = self
    }
    
    // Проверка доступности распознавания речи
    var isSpeechRecognitionAvailable: Bool {
        guard let recognizer = speechRecognizer else { return false }
        return recognizer.isAvailable
    }
    
    // Запрос разрешений
    func requestAuthorization() async -> Bool {
        // Запрос разрешения на микрофон (iOS 17+)
        let micStatus: Bool
        if #available(iOS 17.0, *) {
            micStatus = await AVAudioApplication.requestRecordPermission()
        } else {
            micStatus = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        guard micStatus else {
            errorMessage = "Доступ к микрофону запрещен. Разрешите доступ в Настройках"
            return false
        }
        
        // Запрос разрешения на распознавание речи
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        
        switch speechStatus {
        case .authorized:
            return true
        case .denied:
            errorMessage = VoiceInputError.speechRecognitionDenied.errorDescription
            return false
        case .restricted:
            errorMessage = VoiceInputError.speechRecognitionRestricted.errorDescription
            return false
        case .notDetermined:
            errorMessage = "Разрешение на распознавание речи не получено"
            return false
        @unknown default:
            errorMessage = "Неизвестная ошибка разрешений"
            return false
        }
    }
    
    // Начать запись
    func startRecording() async throws {
        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif

        // Проверяем доступность
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
            throw VoiceInputError.speechRecognitionNotAvailable
        }

        // Если уже записываем, не делаем ничего
        if isRecording {
            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
            return
        }
        
        // Останавливаем предыдущую запись, если она есть
        await stopRecordingSync()
        
        // Сбрасываем состояние
        transcribedText = ""
        finalTranscription = ""
        errorMessage = nil
        isStopping = false

        // Initialize silence detector if VAD is enabled
        if isVADEnabled {
            silenceDetector = SilenceDetector()

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
        } else {
            silenceDetector = nil

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
        }
        
        // Настраиваем аудио сессию
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Используем .playAndRecord для лучшего качества
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceInputError.audioEngineError("Не удалось настроить аудио сессию: \(error.localizedDescription)")
        }
        
        // Создаем запрос на распознавание
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw VoiceInputError.recognitionError("Не удалось создать запрос на распознавание")
        }
        
        // Показываем partial results для UI, но используем только final для парсинга
        recognitionRequest.shouldReportPartialResults = true
        
        // Улучшаем распознавание: включаем контекстные подсказки
        if #available(iOS 13.0, *) {
            recognitionRequest.taskHint = .dictation
            // Включаем on-device recognition если доступно
            if recognizer.supportsOnDeviceRecognition {
                recognitionRequest.requiresOnDeviceRecognition = true
            }
        }

        // Dynamic Context Injection (iOS 17+)
        if #available(iOS 17.0, *) {
            let contextualStrings = buildContextualStrings()
            recognitionRequest.contextualStrings = contextualStrings

            #if DEBUG
            if VoiceInputConstants.enableParsingDebugLogs {
            }
            #endif
        }
        
        // Настраиваем аудио engine
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            throw VoiceInputError.audioEngineError("Не удалось создать аудио engine")
        }
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: VoiceInputConstants.audioBufferSize, format: recordingFormat) { [weak self] buffer, _ in
            // Send buffer to speech recognition
            recognitionRequest.append(buffer)

            // Analyze for silence detection if VAD is enabled
            if let self = self, self.isVADEnabled, let detector = self.silenceDetector {
                Task { @MainActor in
                    let silenceDetected = detector.analyzeSample(buffer)

                    if silenceDetected {
                        #if DEBUG
                        if VoiceInputConstants.enableParsingDebugLogs {
                        }
                        #endif

                        // Auto-stop recording
                        self.stopRecording()
                    }
                }
            }
        }
        
        // Запускаем аудио engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw VoiceInputError.audioEngineError("Не удалось запустить аудио engine: \(error.localizedDescription)")
        }
        
        // Запускаем распознавание
        recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                Task { @MainActor in
                    let transcription = result.bestTranscription.formattedString
                    self.transcribedText = transcription

                    #if DEBUG
                    if VoiceInputConstants.enableParsingDebugLogs {
                    }
                    #endif

                    // Сохраняем финальную транскрипцию
                    if result.isFinal {
                        self.finalTranscription = transcription
                    }
                }
            }

            if let error = error {
                #if DEBUG
                if VoiceInputConstants.enableParsingDebugLogs {
                }
                #endif

                Task { @MainActor in
                    if !self.isRecording {
                        // Игнорируем ошибки после остановки
                        return
                    }
                    self.errorMessage = VoiceInputError.recognitionError(error.localizedDescription).errorDescription
                    self.stopRecording()
                }
            }
        }

        isRecording = true

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif
    }
    
    // Остановить запись (асинхронная версия для UI)
    func stopRecording() {
        Task { @MainActor in
            await stopRecordingSync()
        }
    }
    
    // Синхронная остановка записи
    // @MainActor гарантирует thread-safety, так как все вызовы происходят на главном потоке
    private func stopRecordingSync() async {
        // Предотвращаем множественные вызовы
        guard !isStopping else { return }
        guard isRecording else { return }

        isStopping = true
        isRecording = false

        // Сохраняем ссылки на объекты перед очисткой
        let currentAudioEngine = audioEngine
        let currentRecognitionRequest = recognitionRequest
        let currentRecognitionTask = recognitionTask

        // Завершаем запрос на распознавание
        currentRecognitionRequest?.endAudio()

        // Даем время на финализацию результата
        try? await Task.sleep(for: .milliseconds(VoiceInputConstants.audioEngineStopDelayMs))

        // Останавливаем аудио engine
        if let engine = currentAudioEngine, engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil

        recognitionRequest = nil

        // Отменяем задачу распознавания
        currentRecognitionTask?.cancel()
        recognitionTask = nil

        // Деактивируем аудио сессию
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
        }

        // Reset silence detector
        silenceDetector?.reset()
        silenceDetector = nil

        // Сбрасываем флаг остановки
        isStopping = false
    }
    
    // Получить финальный текст
    func getFinalText() -> String {
        // Используем финальную транскрипцию, если доступна, иначе текущую
        return finalTranscription.isEmpty ? transcribedText : finalTranscription
    }

    // MARK: - Dynamic Context Injection (iOS 17+)

    /// Build contextual strings for improved Speech Recognition
    /// - Returns: Array of contextual strings for better recognition of custom categories, accounts, etc.
    @available(iOS 17.0, *)
    private func buildContextualStrings() -> [String] {
        var context: [String] = []

        // 1. Account names with common patterns
        if let accountsVM = accountsViewModel {
            let accountNames = accountsVM.accounts.map { $0.name.lowercased() }
            context.append(contentsOf: accountNames)

            // Add variations: "карта X", "счет X", "со счета X"
            for name in accountNames {
                context.append("карта \(name)")
                context.append("счет \(name)")
                context.append("счёт \(name)")
                context.append("с карты \(name)")
                context.append("со счета \(name)")
                context.append("со счёта \(name)")
            }
        }

        // 2. Category names with common patterns
        if let categoriesVM = categoriesViewModel {
            let categoryNames = categoriesVM.customCategories.map { $0.name.lowercased() }
            context.append(contentsOf: categoryNames)

            // Add variations: "на X", "для X", "в X"
            for name in categoryNames {
                context.append("на \(name)")
                context.append("для \(name)")
                context.append("в \(name)")
            }
        }

        // 3. Subcategories
        if let categoriesVM = categoriesViewModel {
            let subcategoryNames = categoriesVM.subcategories.map { $0.name.lowercased() }
            context.append(contentsOf: subcategoryNames)
        }

        // 4. Common financial phrases
        let commonPhrases = [
            // Currencies
            "тенге", "тг", "доллар", "долларов", "евро", "рубль", "рублей",
            // Transaction types
            "пополнение", "расход", "доход", "перевод", "оплата", "покупка",
            "зачисление", "списание", "возврат",
            // Amount words
            "тысяча", "тысяч", "миллион",
            // Time words
            "вчера", "сегодня", "позавчера"
        ]
        context.append(contentsOf: commonPhrases)

        // Remove duplicates and return
        return Array(Set(context))
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension VoiceInputService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available && isRecording {
                errorMessage = "Распознавание речи стало недоступно"
                stopRecording()
            }
        }
    }
}
