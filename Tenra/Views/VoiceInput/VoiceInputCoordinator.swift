//
//  VoiceInputCoordinator.swift
//  Tenra
//
//  Voice input flow coordinator - handles voice recording via sheet.
//  VoiceInputView manages its own confirmation sheet internally.
//

import SwiftUI

/// Coordinates the voice input flow: voice button → recording sheet.
/// VoiceInputView handles preview, quick save, and editing internally.
struct VoiceInputCoordinator: View {
    // MARK: - Dependencies
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TransactionStore.self) private var transactionStore

    // MARK: - State
    @State private var showingVoiceInput = false
    @State private var voiceService = VoiceInputService()

    // MARK: - Body
    var body: some View {
        voiceButton
            .sheet(isPresented: $showingVoiceInput) {
                NavigationStack {
                    VoiceInputView(
                        voiceService: voiceService,
                        parser: VoiceInputParser(
                            categoriesViewModel: categoriesViewModel,
                            accountsViewModel: accountsViewModel,
                            transactionsViewModel: transactionsViewModel
                        ),
                        transactionsViewModel: transactionsViewModel,
                        categoriesViewModel: categoriesViewModel,
                        accountsViewModel: accountsViewModel
                    )
                }
                .environment(transactionStore)
            }
            .onAppear {
                voiceService.categoriesViewModel = categoriesViewModel
                voiceService.accountsViewModel = accountsViewModel
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
                .frame(width: 64, height: 64)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(String(localized: "accessibility.voiceInput"))
        .accessibilityHint(String(localized: "accessibility.voiceInputHint"))
    }
}
