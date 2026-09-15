//
//  VoiceAudioSession.swift
//  Tenra
//
//  Audio-session setup for speech recording, kept OFF the main actor.
//
//  `setCategory` / `setActive` are blocking CoreAudio calls (tens of milliseconds,
//  more on a cold audio stack). `VoiceInputService` is `@MainActor`, so calling them
//  inline stalled whatever animation was running — visible as a hitch when the "+"
//  tab expands and `VoiceInputView.onAppear` starts recording. iOS 27 also logs it:
//  "AVAudioSession_iOS.mm:978 This method can lead to UI unresponsiveness if called
//  on the main thread. Consider using the asynchronous activate/deactivate API".
//
//  Every function here is `nonisolated async`, so it runs on the cooperative pool
//  rather than inheriting the caller's actor. iOS 27 additionally has a genuinely
//  asynchronous activate/deactivate pair; on iOS 26 the synchronous calls are still
//  the only option, but off the main thread they no longer block the UI.
//

import AVFAudio
import Foundation
import os

// `nonisolated` so the off-main functions below can log (`Logger` is Sendable on iOS 26+).
private nonisolated let logger = Logger(subsystem: "com.tenra.app", category: "VoiceAudioSession")

enum VoiceAudioSession {

    /// Configures the session for speech capture and activates it.
    /// - Throws: whatever AVAudioSession reports; the caller maps it to `VoiceInputError`.
    nonisolated static func activateForRecording() async throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord + .measurement is the combination the recognizer expects;
        // .duckOthers lowers background audio instead of stopping it.
        try session.setCategory(
            .playAndRecord,
            mode: .measurement,
            options: [.duckOthers, .defaultToSpeaker]
        )

        if #available(iOS 27, *) {
            _ = try await session.activate(options: [])
        } else {
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        }
    }

    /// Deactivates the session, notifying other apps so their audio can resume.
    /// Failures are logged, never thrown: the recording has already ended by then and
    /// there is nothing the caller could do differently.
    nonisolated static func deactivate() async {
        let session = AVAudioSession.sharedInstance()
        do {
            if #available(iOS 27, *) {
                _ = try await session.deactivate(options: .notifyOthersOnDeactivation)
            } else {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            }
        } catch {
            logger.warning("Failed to deactivate audio session: \(error.localizedDescription, privacy: .public)")
        }
    }
}
