//
//  AssistantVoiceSheet.swift
//  Tenra
//
//  Speaking to the assistant (docs/plan-ai-assistant.md §3.8, "voice in the chat"): the
//  composer's microphone opens this sheet, which listens with the voice screen's own pieces
//  (the edge glow, the "Speak..." prompt, the orb that stops it) and shows the words as they
//  are recognized. Stopped, by the orb or after five seconds without new words, it shows what
//  it heard: "Ask Ten" sends it as a question (the reply drafts what was said, with its confirm
//  card), "Say it again" starts over. Nothing is sent before that tap, so a misheard phrase
//  costs no answer.
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

    /// What was heard, the final transcription once there is one.
    private var heard: String {
        voiceService.getFinalText().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if voiceService.isRecording {
                    VoiceLevelGlow(voiceService: voiceService, followsVoice: true)
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
            }
        }
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
            if voiceService.transcribedText.isEmpty {
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
        if voiceService.isRecording {
            // The orb's frame leaves room for its glow and takes that room back vertically.
            HStack {
                Spacer()
                VoiceStopOrb(voiceService: voiceService, followsVoice: true) {
                    HapticManager.play(.tap)
                    silenceTimer?.cancel()
                    voiceService.stopRecording()
                }
                Spacer()
            }
            .padding(.vertical, -AppSpacing.xl)
            .padding(.bottom, AppSpacing.xl)
        } else {
            VStack(spacing: AppSpacing.sm) {
                if !voiceService.transcribedText.isEmpty {
                    DSButton(String(localized: "assistant.voice.send"), systemImage: "arrow.up", fullWidth: true) {
                        let text = heard
                        guard !text.isEmpty else { return }
                        HapticManager.light()
                        onSend(text)
                        dismiss()
                    }
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
