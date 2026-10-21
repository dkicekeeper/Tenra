//
//  AssistantVoiceSheet.swift
//  Tenra
//
//  Speaking to the assistant (docs/domains/assistant.md §7, "voice in the chat"): the
//  composer's microphone opens this sheet, which listens with the voice screen's own pieces
//  (the edge glow, the "Speak..." prompt, the orb that stops it) and shows the words as they
//  are recognized. Stopped, by the orb or after five seconds without new words, it shows what
//  it heard: "Ask Ten" sends it as a question (the reply drafts what was said, with its confirm
//  card), "Say it again" starts over. Nothing is sent before that tap, so a misheard phrase
//  costs no answer. Ten sits in the title, listening to the voice as it records (DesignKit
//  `.listening` with the voice level), glad once it heard something.
//

import SwiftUI
import UIKit

struct AssistantVoiceSheet: View {
    /// Sends the recognized text as a question.
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppCoordinator.self) private var coordinator
    @State private var voiceService = VoiceInputService()
    @State private var silenceTimer: Task<Void, Never>?
    @State private var showingPermissionAlert = false
    @State private var isPermissionDenied = false
    @State private var permissionMessage = ""
    /// Screenshot capture (DEBUG): the Simulator recognizes no speech, so the sheet shows the
    /// demo phrase as heard while it "records", and the orb stops it.
    @State private var demoRecording = AssistantVoiceSheet.isScreenshotDemo

    private static var isScreenshotDemo: Bool {
        #if DEBUG
        return ScreenshotDemoMode.isActive
        #else
        return false
        #endif
    }

    private var demoPhrase: String? {
        #if DEBUG
        return Self.isScreenshotDemo ? ScreenshotDemoLexicon.current().voiceDemoPhrase : nil
        #else
        return nil
        #endif
    }

    /// What was heard, the final transcription once there is one.
    private var heard: String {
        if let demoPhrase { return demoPhrase }
        return voiceService.getFinalText().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if voiceService.isRecording || demoRecording {
                    VoiceLevelGlow(voiceService: voiceService, followsVoice: !Self.isScreenshotDemo)
                        .ignoresSafeArea()
                        .transition(.opacity.animation(AppAnimation.gentleSpring))
                }
                VStack(spacing: 0) {
                    transcript
                        .padding(.top, AppSpacing.xl)
                        .screenPadding()
                    Spacer(minLength: AppSpacing.lg)
                    controls
                }
            }
            .animation(AppAnimation.gentleSpring, value: voiceService.isRecording)
            .navigationTitle(String(localized: "tab.assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(String(localized: "button.close"), systemImage: "xmark") {
                        voiceService.stopRecording()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .principal) {
                    ListeningTen(
                        voiceService: voiceService,
                        isRecording: voiceService.isRecording || demoRecording,
                        heardSomething: !voiceService.transcribedText.isEmpty || demoPhrase != nil,
                        followsVoice: !Self.isScreenshotDemo
                    )
                }
            }
        }
        .softScrollEdges()
        .alert(String(localized: "voice.error"), isPresented: $showingPermissionAlert) {
            Button(String(localized: "voice.ok")) { dismiss() }
            if isPermissionDenied {
                Button(String(localized: "voice.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                }
            }
        } message: {
            Text(permissionMessage.isEmpty ? String(localized: "voice.errorMessage") : permissionMessage)
        }
        .onChange(of: voiceService.transcribedText) { _, text in
            // Five seconds without new words end the recording, as on the voice screen.
            guard !text.isEmpty, voiceService.isRecording else { return }
            silenceTimer?.cancel()
            silenceTimer = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, voiceService.isRecording else { return }
                voiceService.stopRecording()
            }
        }
        .onAppear {
            voiceService.categoriesViewModel = coordinator.categoriesViewModel
            voiceService.accountsViewModel = coordinator.accountsViewModel
            guard !Self.isScreenshotDemo else { return }
            start()
        }
        .onDisappear {
            silenceTimer?.cancel()
            // Unconditional: a start still bringing the audio up is cancelled too
            // (VoiceInputService.startToken).
            voiceService.stopRecording()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var transcript: some View {
        Group {
            if let demoPhrase {
                AnimatedTranscriptionText(text: demoPhrase, entities: [], font: AppTypography.h1, alignment: .leading)
            } else if voiceService.transcribedText.isEmpty {
                if voiceService.isRecording {
                    ListeningPrompt()
                } else {
                    Text(String(localized: "voice.emptyText"))
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.Text.secondary)
                }
            } else {
                AnimatedTranscriptionText(
                    text: voiceService.transcribedText,
                    entities: [],
                    font: AppTypography.h1,
                    alignment: .leading
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var controls: some View {
        if voiceService.isRecording || demoRecording {
            // The orb's frame leaves room for its glow and takes that room back vertically.
            HStack {
                Spacer()
                VoiceStopOrb(voiceService: voiceService, followsVoice: !Self.isScreenshotDemo) {
                    HapticManager.play(.tap)
                    if demoRecording {
                        demoRecording = false
                        return
                    }
                    silenceTimer?.cancel()
                    voiceService.stopRecording()
                }
                .accessibilityIdentifier("assistant.voice.orb")
                Spacer()
            }
            .padding(.vertical, -AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        } else {
            VStack(spacing: AppSpacing.sm) {
                if !voiceService.transcribedText.isEmpty || demoPhrase != nil {
                    DSButton(String(localized: "assistant.voice.send"), systemImage: "arrow.up", fullWidth: true) {
                        let text = heard
                        guard !text.isEmpty else { return }
                        HapticManager.light()
                        onSend(text)
                        dismiss()
                    }
                    .accessibilityIdentifier("assistant.voice.send")
                }
                DSButton(String(localized: "assistant.voice.again"), systemImage: "mic.fill", appearance: .flat, fullWidth: true) {
                    voiceService.transcribedText = ""
                    start()
                }
            }
            .screenPadding()
            .padding(.bottom, AppSpacing.xl)
            // Under Reduce Motion the controls fade in instead of sliding up.
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Recording

    private func start() {
        Task {
            try? await Task.sleep(for: .milliseconds(VoiceInputConstants.autoStartDelayMs))
            guard await voiceService.requestAuthorization() else {
                isPermissionDenied = true
                showingPermissionAlert = true
                return
            }
            do {
                try await voiceService.startRecording()
            } catch {
                permissionMessage = error.localizedDescription
                showingPermissionAlert = true
            }
        }
    }
}

/// Ten in the voice sheet's title: listening while it records, its swarm following the voice
/// level; glad once it heard something, at rest otherwise. A view of its own, as the level
/// changes dozens of times a second. The title it stands in for stays for VoiceOver.
private struct ListeningTen: View {
    let voiceService: VoiceInputService
    let isRecording: Bool
    let heardSomething: Bool
    /// Off for the screenshots, where the level stays at zero: the swarm ripples on its own.
    let followsVoice: Bool

    var body: some View {
        ParticleCreature(
            mood: isRecording ? .listening : (heardSomething ? .happy : .idle),
            style: .compact,
            level: isRecording && followsVoice ? voiceService.audioLevel : nil
        )
        .frame(width: AppIconSize.xl, height: AppIconSize.xl)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "tab.assistant"))
        .accessibilityAddTraits(.isHeader)
    }
}
