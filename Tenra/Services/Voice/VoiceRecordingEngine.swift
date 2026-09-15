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
    /// - Returns: the running engine, for the caller to retain and later stop.
    nonisolated static func makeAndStart(
        request: SFSpeechAudioBufferRecognitionRequest,
        bufferSize: AVAudioFrameCount
    ) async throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { buffer, _ in
            // Runs on the audio thread. Forward the buffer to speech recognition; the
            // wave visualization is time-driven and needs no amplitude side channel.
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()
        return engine
    }

    /// Stops the engine and removes the tap. `stop()` blocks as well, so this is
    /// `nonisolated async` for the same reason as `makeAndStart`.
    nonisolated static func stop(_ engine: AVAudioEngine) async {
        guard engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
    }
}
