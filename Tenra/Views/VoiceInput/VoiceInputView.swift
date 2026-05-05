//
//  VoiceInputView.swift
//  Tenra
//
//  Voice input with live transcription, animated text, and transaction preview.
//  Manages its own confirmation sheet — no callback chain to parent.
//

import SwiftUI
import UIKit

struct VoiceInputView: View {
    @Bindable var voiceService: VoiceInputService
    @Environment(\.dismiss) var dismiss
    @Environment(TransactionStore.self) private var transactionStore
    let parser: VoiceInputParser
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    var embeddedInTab: Bool = false

    @State private var showingPermissionAlert = false
    @State private var isPermissionDenied = false
    @State private var permissionMessage = ""
    @State private var recognizedEntities: [RecognizedEntity] = []
    @State private var showingErrorAlert = false
    @State private var errorAlertMessage = ""
    @State private var parseDebounceTask: Task<Void, Never>?
    @State private var livePreview: ParsedOperation?
    @State private var silenceTimer: Task<Void, Never>?
    /// Set when user taps preview card → opens confirmation sheet directly
    @State private var editingOperation: ParsedOperation?
    /// Captured text at the moment of action
    @State private var capturedText: String = ""
    /// Saved successfully flag
    @State private var savedSuccessfully = false

    private var currentText: String {
        let final = voiceService.getFinalText()
        return final.isEmpty ? voiceService.transcribedText : final
    }

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
            previewSection
            transcriptionSection
                .padding(.bottom, 24)
            buttonSection
        }
        .overlay {
            if voiceService.isRecording {
                SiriWaveRecordingView(amplitudeRef: voiceService.amplitudeRef)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(AppAnimation.gentleSpring))
            }
        }
        .animation(AppAnimation.gentleSpring, value: voiceService.isRecording)
        .navigationTitle(String(localized: "voice.title"))
        .navigationBarTitleDisplayMode(.inline)
        // ── Confirmation sheet (edit-only mode: returns updated ParsedOperation) ──
        .sheet(item: $editingOperation) { parsed in
            VoiceInputConfirmationView(
                transactionsViewModel: transactionsViewModel,
                accountsViewModel: accountsViewModel,
                categoriesViewModel: categoriesViewModel,
                parsedOperation: parsed,
                originalText: capturedText,
                onUpdate: { updated in
                    withAnimation(AppAnimation.gentleSpring) {
                        livePreview = updated
                    }
                }
            )
            .environment(transactionStore)
        }
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
        .onChange(of: voiceService.transcribedText) { oldText, newText in
            // Text-driven amplitude boost
            let lengthDelta = newText.count - oldText.count
            if lengthDelta > 0 {
                let target = min(Float(lengthDelta) * 0.12, 1.0)
                let current = voiceService.amplitudeRef.value
                let blended = current * 0.4 + max(current, target) * 0.6
                voiceService.amplitudeRef.value = min(blended, 1.0)
            }

            // Text-based auto-stop: 5s after last recognized text
            if !newText.isEmpty && voiceService.isRecording {
                silenceTimer?.cancel()
                silenceTimer = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    if voiceService.isRecording {
                        voiceService.stopRecording()
                    }
                }
            }

            // Debounced parse
            parseDebounceTask?.cancel()
            parseDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                recognizedEntities = parser.parseEntitiesLive(from: newText)

                if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let parsed = parser.parse(newText)
                    if parsed.amount != nil {
                        withAnimation(AppAnimation.gentleSpring) {
                            livePreview = parsed
                        }
                    } else if livePreview != nil {
                        withAnimation(AppAnimation.gentleSpring) {
                            livePreview = nil
                        }
                    }
                }

                if !newText.isEmpty {
                    UIAccessibility.post(notification: .announcement, argument: newText)
                }
            }
        }
        .onAppear { startRecordingOnAppear() }
        .onDisappear {
            parseDebounceTask?.cancel()
            silenceTimer?.cancel()
            if voiceService.isRecording { voiceService.stopRecording() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewSection: some View {
        if let preview = livePreview {
            previewCard(for: preview)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Preview card matching TransactionCard's visual layout but without
    /// its built-in tap/sheet/swipe gestures. Wrapped in a Button for our own action.
    private func previewCard(for parsed: ParsedOperation) -> some View {
        let amount = (parsed.amount as? NSDecimalNumber)?.doubleValue ?? 0
        let category = parsed.categoryName ?? String(localized: "category.other")
        let currency = parsed.currencyCode ?? accountsViewModel.accounts.first(where: { $0.id == parsed.accountId })?.currency ?? "KZT"
        let description = parsed.note.isEmpty ? voiceService.transcribedText : parsed.note
        let sourceAccount = accountsViewModel.accounts.first(where: { $0.id == parsed.accountId })

        let styleData = CategoryStyleHelper.cached(
            category: category,
            type: parsed.type,
            customCategories: categoriesViewModel.customCategories
        )

        return Button {
            capturedText = currentText
            voiceService.stopRecording()
            silenceTimer?.cancel()
            editingOperation = parsed
        } label: {
            HStack(spacing: AppSpacing.md) {
                // Icon — same as TransactionIconView
                IconView(
                    source: .sfSymbol(styleData.iconName),
                    style: .circle(
                        size: AppIconSize.xxl,
                        tint: .monochrome(styleData.primaryColor),
                        backgroundColor: styleData.lightBackgroundColor
                    )
                )

                // Info — same structure as TransactionInfoView
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(category)
                        .font(AppTypography.h4)
                        .foregroundStyle(AppColors.textPrimary)

                    if let accountName = sourceAccount?.name {
                        Text(accountName)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if !description.isEmpty {
                        Text(description)
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Amount — same as FormattedAmountView
                FormattedAmountView(
                    amount: amount,
                    currency: currency,
                    prefix: TransactionDisplayHelper.amountPrefix(for: parsed.type),
                    color: TransactionDisplayHelper.amountColor(for: parsed.type)
                )
            }
            .padding(AppSpacing.lg)
            .cardStyle()
        }
        .buttonStyle(.plain)
        .borderBeam(isActive: voiceService.isRecording)
    }

    private var transcriptionSection: some View {
        VStack {
            if voiceService.transcribedText.isEmpty {
                if voiceService.isRecording {
                    PulsingText(text: String(localized: "voice.speak"))
                }
            } else {
                HighlightedText(
                    text: voiceService.transcribedText,
                    entities: recognizedEntities,
                    font: AppTypography.h4
                )
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
                .contentTransition(.interpolate)
                .animation(AppAnimation.gentleSpring, value: voiceService.transcribedText)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: VoiceInputConstants.transcriptionMaxHeight)
    }

    @ViewBuilder
    private var buttonSection: some View {
        if voiceService.isRecording {
            // Recording: stop button
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
                            .foregroundStyle(AppColors.staticWhite)
                    }
                }
                .accessibilityLabel(String(localized: "voice.stopRecording"))
                Spacer()
            }
            .padding(.bottom, AppSpacing.xl)
        } else if !voiceService.transcribedText.isEmpty, let preview = livePreview {
            // Stopped with parsed preview: confirm saves directly
            Button {
                quickSave(preview)
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: "checkmark")
                        .font(AppTypography.bodyEmphasis)
                    Text(String(localized: "voiceConfirmation.confirm"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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
        silenceTimer?.cancel()
    }

    private func quickSave(_ parsed: ParsedOperation) {
        let accountId = parsed.accountId ?? accountsViewModel.accounts.first?.id
        guard let accountId else { return }
        let account = accountsViewModel.accounts.first { $0.id == accountId }
        let currency = parsed.currencyCode ?? account?.currency ?? "KZT"

        let transaction = Transaction(
            id: "",
            date: DateFormatters.dateFormatter.string(from: parsed.date),
            description: parsed.note.isEmpty ? currentText : parsed.note,
            amount: (parsed.amount as? NSDecimalNumber)?.doubleValue ?? 0,
            currency: currency,
            type: parsed.type,
            category: parsed.categoryName ?? String(localized: "category.other"),
            accountId: accountId
        )

        Task {
            do {
                _ = try await transactionStore.add(transaction)
                HapticManager.success()
                // Reset and restart recording for next transaction
                withAnimation(AppAnimation.gentleSpring) {
                    livePreview = nil
                }
                try? await voiceService.startRecording()
            } catch {
                HapticManager.error()
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

// MARK: - Pulsating Placeholder

private struct PulsingText: View {
    let text: String
    @State private var isPulsing = false

    var body: some View {
        Text(text)
            .font(AppTypography.h4)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, AppSpacing.lg)
            .opacity(isPulsing ? 0.3 : 0.8)
            .animation(
                AppAnimation.isReduceMotionEnabled
                    ? nil
                    : .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Recording Indicator

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
        .onAppear { isAnimating = true }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    VoiceInputView(
        voiceService: VoiceInputService(),
        parser: VoiceInputParser(
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel,
            transactionsViewModel: coordinator.transactionsViewModel
        ),
        transactionsViewModel: coordinator.transactionsViewModel,
        categoriesViewModel: coordinator.categoriesViewModel,
        accountsViewModel: coordinator.accountsViewModel
    )
    .environment(coordinator.transactionStore)
}
