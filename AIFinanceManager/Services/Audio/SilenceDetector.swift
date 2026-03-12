//
//  SilenceDetector.swift
//  AIFinanceManager
//
//  Created on 2026-01-19
//

import Foundation
import AVFAudio

/// Detects silence in audio stream using Voice Activity Detection (VAD)
/// Uses RMS (Root Mean Square) energy calculation to determine if audio contains speech
nonisolated class SilenceDetector {

    // MARK: - Configuration

    /// Silence threshold in decibels (dB)
    /// Audio below this level is considered silence
    private let silenceThreshold: Float

    /// Duration of sustained silence required to trigger detection (seconds)
    private let silenceDuration: TimeInterval

    /// Minimum speech duration to prevent false positives (seconds)
    private let minimumSpeechDuration: TimeInterval

    // MARK: - State

    /// Timestamp when silence started
    private var silenceStartTime: Date?

    /// Timestamp when speech started
    private var speechStartTime: Date?

    /// Current silence state
    private var isSilent: Bool = false

    /// Indicates if we've had enough speech before silence
    private var hasHadSpeech: Bool = false

    // MARK: - Initialization

    /// Initialize silence detector
    /// - Parameters:
    ///   - silenceThreshold: Threshold in dB (default: -40.0)
    ///   - silenceDuration: Required silence duration in seconds (default: 2.5)
    ///   - minimumSpeechDuration: Minimum speech duration to prevent false positives (default: 1.0)
    init(
        silenceThreshold: Float = VoiceInputConstants.vadSilenceThresholdDb,
        silenceDuration: TimeInterval = VoiceInputConstants.vadSilenceDuration,
        minimumSpeechDuration: TimeInterval = VoiceInputConstants.vadMinimumSpeechDuration
    ) {
        self.silenceThreshold = silenceThreshold
        self.silenceDuration = silenceDuration
        self.minimumSpeechDuration = minimumSpeechDuration
    }

    // MARK: - Public Methods

    /// Analyze audio buffer to detect silence
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: True if sustained silence detected, false otherwise
    func analyzeSample(_ buffer: AVAudioPCMBuffer) -> Bool {
        // Calculate RMS energy
        let rmsDb = calculateRMS(buffer: buffer)

        let now = Date()

        // Check if audio is silent
        if rmsDb < silenceThreshold {
            // Audio is silent
            if silenceStartTime == nil {
                // Silence just started
                silenceStartTime = now

                #if DEBUG
                if VoiceInputConstants.enableParsingDebugLogs {
                }
                #endif
            }

            // Check if silence has lasted long enough
            if let startTime = silenceStartTime {
                let silentDuration = now.timeIntervalSince(startTime)

                // Only trigger if we had enough speech before silence
                if silentDuration >= silenceDuration && hasHadSpeech {
                    #if DEBUG
                    if VoiceInputConstants.enableParsingDebugLogs {
                    }
                    #endif
                    return true
                }
            }

            isSilent = true
        } else {
            // Audio contains speech
            if isSilent {
                // Speech resumed after silence
                #if DEBUG
                if VoiceInputConstants.enableParsingDebugLogs {
                }
                #endif
            }

            // Track speech duration
            if speechStartTime == nil {
                speechStartTime = now
            } else {
                // Check if we've had enough speech
                let speechDuration = now.timeIntervalSince(speechStartTime!)
                if speechDuration >= minimumSpeechDuration {
                    hasHadSpeech = true

                    #if DEBUG
                    if VoiceInputConstants.enableParsingDebugLogs && !hasHadSpeech {
                    }
                    #endif
                }
            }

            // Reset silence tracking
            silenceStartTime = nil
            isSilent = false
        }

        return false
    }

    /// Reset detector state
    func reset() {
        silenceStartTime = nil
        speechStartTime = nil
        isSilent = false
        hasHadSpeech = false

        #if DEBUG
        if VoiceInputConstants.enableParsingDebugLogs {
        }
        #endif
    }

    // MARK: - Private Methods

    /// Calculate RMS (Root Mean Square) energy in decibels
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: RMS energy in dB
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return -Float.infinity // No audio data
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else {
            return -Float.infinity
        }

        // Calculate sum of squares
        var sumOfSquares: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sumOfSquares += sample * sample
        }

        // Calculate RMS
        let rms = sqrt(sumOfSquares / Float(frameLength))

        // Convert to decibels
        // dB = 20 * log10(rms)
        // Adding small epsilon to avoid log(0)
        let db = 20 * log10(max(rms, 1e-10))

        return db
    }

    // MARK: - Getters

    /// Current silence state
    var isCurrentlySilent: Bool {
        return isSilent
    }

    /// Time elapsed since silence started
    var silenceDurationElapsed: TimeInterval? {
        guard let startTime = silenceStartTime else { return nil }
        return Date().timeIntervalSince(startTime)
    }

    /// Whether detector has detected sufficient speech
    var hasSufficientSpeech: Bool {
        return hasHadSpeech
    }
}

// MARK: - Debug Helper

#if DEBUG
extension SilenceDetector {
    /// Generate debug status report
    func debugStatus() -> String {
        var status = "🎤 SilenceDetector Status:\n"
        status += "  - Silent: \(isSilent ? "Yes" : "No")\n"
        status += "  - Has speech: \(hasHadSpeech ? "Yes" : "No")\n"

        if let elapsed = silenceDurationElapsed {
            status += "  - Silence duration: \(String(format: "%.1f", elapsed))s / \(String(format: "%.1f", silenceDuration))s\n"
        } else {
            status += "  - Silence duration: N/A\n"
        }

        status += "  - Threshold: \(String(format: "%.1f", silenceThreshold)) dB\n"
        status += "  - Required duration: \(String(format: "%.1f", silenceDuration))s\n"

        return status
    }
}
#endif
