//
//  VoiceInputView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI
import UIKit

struct VoiceInputView: View {
    @Bindable var voiceService: VoiceInputService
    @Environment(\.dismiss) var dismiss
    let onComplete: (String) -> Void
    let parser: VoiceInputParser
    /// When true the view is hosted inside a tab — skips its own NavigationStack
    /// and close button so the parent NavigationStack handles navigation.
    var embeddedInTab: Bool = false

    @State private var showingPermissionAlert = false
    @State private var isPermissionDenied = false
    @State private var permissionMessage = ""
    @State private var recognizedEntities: [RecognizedEntity] = []
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""
    @State private var parseDebounceTask: Task<Void, Never>?
    @State private var stopTask: Task<Void, Never>?

    var body: some View {
        if embeddedInTab {
            coreContent
        } else {
            NavigationStack {
                coreContent
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button {
                                voiceService.stopRecording()
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel(String(localized: "button.close"))
                        }
                    }
            }
        }
    }

    // MARK: - Core content

    private var coreContent: some View {
        VStack(spacing: 0) {
            Spacer()
            transcriptionSection
            vadToggleSection
            stopButtonSection
        }
        .overlay {
            if voiceService.isRecording {
                SiriWaveRecordingView(amplitudeRef: voiceService.amplitudeRef)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(AppAnimation.gentleSpring))
            }
        }
        .navigationTitle(String(localized: "voice.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(String(localized: "voice.error"), isPresented: $showingPermissionAlert) {
            permissionAlertButtons
        } message: {
            Text(permissionMessage.isEmpty ? String(localized: "voice.errorMessage") : permissionMessage)
        }
        .alert(String(localized: "voice.error"), isPresented: $showingErrorAlert) {
            Button(String(localized: "voice.ok")) {
                if !embeddedInTab { dismiss() }
            }
        } message: {
            Text(errorAlertMessage.isEmpty ? String(localized: "voice.errorMessage") : errorAlertMessage)
        }
        .onChange(of: voiceService.errorMessage) { _, newError in
            if let error = newError, !error.isEmpty, !showingErrorAlert {
                errorAlertMessage = error
                showingErrorAlert = true
            }
        }
        .onChange(of: voiceService.isRecording) { oldValue, newValue in
            if oldValue && !newValue {
                if let error = voiceService.errorMessage, !error.isEmpty {
                    errorAlertMessage = error
                    showingErrorAlert = true
                }
            }
        }
        .onChange(of: voiceService.transcribedText) { _, newText in
            // Debounce parsing to avoid heavy regex work on every partial result
            parseDebounceTask?.cancel()
            parseDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                recognizedEntities = parser.parseEntitiesLive(from: newText)
                // Announce only debounced final text to avoid flooding VoiceOver
                if !newText.isEmpty {
                    UIAccessibility.post(notification: .announcement, argument: newText)
                }
            }
        }
        .onAppear { startRecordingOnAppear() }
        .onDisappear {
            parseDebounceTask?.cancel()
            stopTask?.cancel()
            if voiceService.isRecording { voiceService.stopRecording() }
        }
    }

    // MARK: - Subviews

    private var transcriptionSection: some View {
        ScrollView {
            VStack {
                Spacer()
                if voiceService.transcribedText.isEmpty {
                    Text(String(localized: "voice.speak"))
                        .font(AppTypography.h4)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.lg)
                } else {
                    HighlightedText(
                        text: voiceService.transcribedText,
                        entities: recognizedEntities,
                        font: AppTypography.h4
                    )
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxHeight: VoiceInputConstants.transcriptionMaxHeight)
    }

    @ViewBuilder
    private var vadToggleSection: some View {
        if !voiceService.isRecording {
            VStack(spacing: AppSpacing.sm) {
                Toggle(String(localized: "voice.vadToggle"), isOn: $voiceService.isVADEnabled)
                    .font(AppTypography.caption)
                    .padding(.horizontal, AppSpacing.lg)
                Text(String(localized: "voice.vadDescription"))
                    .font(AppTypography.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.lg)
            }
            .padding(.vertical, AppSpacing.md)
        }
    }

    @ViewBuilder
    private var stopButtonSection: some View {
        if voiceService.isRecording {
            HStack {
                Spacer()
                Button(action: handleStopTap) {
                    ZStack {
                        Circle()
                            .fill(AppColors.destructive)
                            .frame(width: AppSize.buttonXL, height: AppSize.buttonXL)
                            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
                        Image(systemName: "stop.fill")
                            .font(.system(size: AppIconSize.xl))
                            .foregroundStyle(.white)
                    }
                }
                .accessibilityLabel(String(localized: "voice.stopRecording"))
                .accessibilityHint(
                    voiceService.transcribedText.isEmpty
                        ? String(localized: "voice.noTextRecognizedYet")
                        : String(localized: "voice.tapToFinish")
                )
                Spacer()
            }
            .padding(.bottom, AppSpacing.xl)
            .background(AppColors.backgroundPrimary)
        }
    }

    @ViewBuilder
    private var permissionAlertButtons: some View {
        Button(String(localized: "voice.ok")) {
            if !embeddedInTab { dismiss() }
        }
        if isPermissionDenied {
            Button(String(localized: "voice.openSettings")) {
                if let url = URL(string: UIApplication.openSettingsURLString),
                   UIApplication.shared.canOpenURL(url) {
                    UIApplication.shared.open(url)
                }
                if !embeddedInTab { dismiss() }
            }
        }
    }

    // MARK: - Actions

    private func handleStopTap() {
        voiceService.stopRecording()
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(for: .milliseconds(VoiceInputConstants.finalizationDelayMs))
            guard !Task.isCancelled else { return }
            if let errorMsg = voiceService.errorMessage, !errorMsg.isEmpty {
                errorAlertMessage = errorMsg
                showingErrorAlert = true
                return
            }
            let finalText = voiceService.getFinalText()
            if !finalText.isEmpty {
                onComplete(finalText)
            } else {
                errorAlertMessage = String(localized: "voice.emptyText")
                showingErrorAlert = true
            }
        }
    }

    private func startRecordingOnAppear() {
        Task {
            try? await Task.sleep(for: .milliseconds(VoiceInputConstants.autoStartDelayMs))
            let authorized = await voiceService.requestAuthorization()
            if authorized {
                do {
                    try await voiceService.startRecording()
                } catch {
                    permissionMessage = error.localizedDescription
                    showingPermissionAlert = true
                }
            } else {
                isPermissionDenied = true
                showingPermissionAlert = true
            }
        }
    }
}

struct RecordingIndicatorView: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Circle()
                .fill(AppColors.destructive)
                .frame(width: AppSize.dotLargeSize, height: AppSize.dotLargeSize)
                .opacity(isAnimating ? 0.3 : 1.0)
                .animation(
                    AppAnimation.isReduceMotionEnabled
                        ? nil
                        : AppAnimation.gentleSpring.repeatForever(autoreverses: true),
                    value: isAnimating
                )

            Text(String(localized: "voice.recording"))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(AppColors.destructive)
        }
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    VoiceInputView(
        voiceService: VoiceInputService(),
        onComplete: { _ in },
        parser: VoiceInputParser(
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        )
    )
}
