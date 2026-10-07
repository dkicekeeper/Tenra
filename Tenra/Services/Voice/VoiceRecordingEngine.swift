//
//  VoiceRecordingEngine.swift
//  Tenra
//
//  AVAudioEngine lifecycle for speech capture, kept OFF the main actor —
//  the companion of `VoiceAudioSession`.
//
//  Every call below blocks inside CoreAudio: the first `inputNode` access spins up
//  the input hardware, `outputFormat(forBus:)` queries it, `prepare()` allocates the
//  render buffers, and `start()` brings up the IO thread. On `VoiceInputService`
//  (`@MainActor`) that ran on the main thread and stalled whatever animation was in
//  flight when recording began.
//

import AVFAudio
import Foundation
import Speech

enum VoiceRecordingEngine {

    /// Builds the engine, installs the tap that feeds `request`, and starts it.
    /// - Parameter onLevel: The voice level of each buffer, 0…1, on the audio thread; it drives
    ///   the recording screen's `EdgeGlow`.
    /// - Returns: the running engine, for the caller to retain and later stop.
    nonisolated static func makeAndStart(
        request: SFSpeechAudioBufferRecognitionRequest,
        bufferSize: AVAudioFrameCount,
        onLevel: @escaping @Sendable (Double) -> Void
    ) async throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { buffer, _ in
            // Runs on the audio thread. Forward the buffer to speech recognition, and its level
            // to the recording screen's glow (one number per buffer, about 47 a second).
            request.append(buffer)
            onLevel(level(of: buffer))
        }

        engine.prepare()
        try engine.start()
        return engine
    }

    /// The buffer's RMS in decibels mapped to 0…1: −50 dB (a quiet room) is 0, −10 dB (a voice
    /// close to the phone) is 1.
    nonisolated static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sumOfSquares: Float = 0
        for index in 0..<count { sumOfSquares += samples[index] * samples[index] }
        let decibels = 20 * log10(max(sqrt(sumOfSquares / Float(count)), 1e-7))
        return Double(min(max((decibels + 50) / 40, 0), 1))
    }

    /// Stops the engine and removes the tap. `stop()` blocks as well, so this is
    /// `nonisolated async` for the same reason as `makeAndStart`.
    nonisolated static func stop(_ engine: AVAudioEngine) async {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}
