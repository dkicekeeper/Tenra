//
//  VoiceInputCoordinator.swift
//  AIFinanceManager
//
//  Voice input flow coordinator - handles voice recording and confirmation
//  Extracted from ContentView for Single Responsibility Principle
//

import SwiftUI

/// Coordinates the voice input flow: voice button → recording → parsing → confirmation
/// Single responsibility: Voice input orchestration
struct VoiceInputCoordinator: View {
    // MARK: - Dependencies
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    // MARK: - State
    @State private var showingVoiceInput = false
    @State private var voiceService = VoiceInputService()
    @State private var parsedOperation: ParsedOperation? = nil

    // MARK: - Body
    var body: some View {
        voiceButton
            .sheet(isPresented: $showingVoiceInput) {
                voiceInputSheet
            }
            .sheet(item: $parsedOperation) { parsed in
                voiceConfirmationSheet(for: parsed)
            }
            .onAppear {
                setupVoiceService()
            }
    }

    // MARK: - Voice Button
    private var voiceButton: some View {
        Button(action: {
            HapticManager.light()
            showingVoiceInput = true
        }) {
            Image(systemName: "mic.fill")
                .font(.system(size: AppIconSize.lg))
                .fontWeight(.semibold)
                .frame(width: AppSize.buttonLarge, height: AppSize.buttonLarge)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(String(localized: "accessibility.voiceInput"))
        .accessibilityHint(String(localized: "accessibility.voiceInputHint"))
    }

    // MARK: - Voice Input Sheet
    private var voiceInputSheet: some View {
        // Create parser once for the entire sheet
        let parser = VoiceInputParser(
            categoriesViewModel: categoriesViewModel,
            accountsViewModel: accountsViewModel,
            transactionsViewModel: transactionsViewModel
        )

        return VoiceInputView(
            voiceService: voiceService,
            onComplete: { transcribedText in
                // Check that text is not empty
                guard !transcribedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    // If text is empty, just close voice input
                    showingVoiceInput = false
                    return
                }

                showingVoiceInput = false
                let parsed = parser.parse(transcribedText)
                // Set parsedOperation - sheet will open automatically via .sheet(item:)
                parsedOperation = parsed
            },
            parser: parser
        )
    }

    // MARK: - Voice Confirmation Sheet
    private func voiceConfirmationSheet(for parsed: ParsedOperation) -> some View {
        VoiceInputConfirmationView(
            transactionsViewModel: transactionsViewModel,
            accountsViewModel: accountsViewModel,
            categoriesViewModel: categoriesViewModel,
            parsedOperation: parsed,
            originalText: voiceService.getFinalText()
        )
    }

    // MARK: - Setup
    private func setupVoiceService() {
        // Setup VoiceInputService with ViewModels for contextual strings (iOS 17+)
        voiceService.categoriesViewModel = categoriesViewModel
        voiceService.accountsViewModel = accountsViewModel
    }
}
