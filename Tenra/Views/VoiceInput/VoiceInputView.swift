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
    /// All transactions parsed from the current utterance. Empty when nothing
    /// is recognized yet; a single element for one-clause speech, multiple for
    /// "500 на такси и 1000 на продукты"-style multi-operation input.
    @State private var livePreviews: [ParsedOperation] = []
    @State private var silenceTimer: Task<Void, Never>?
    @State private var lastAnnouncedText: String = ""
    @State private var announcementTask: Task<Void, Never>?
    /// Beam activates only after the preview card's entrance transition has
    /// settled, so the moving sweep doesn't compete with move+opacity interp.
    @State private var beamActive: Bool = false
    /// Carries both the index and the snapshot of the operation being edited
    /// so the sheet (item:) presentation has a stable Identifiable and we
    /// know which slot to update on return.
    @State private var editingTarget: EditingTarget?
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
        ZStack {
            if voiceService.isRecording {
                SiriWaveRecordingView()
                    .ignoresSafeArea()
                    .transition(.opacity.animation(AppAnimation.gentleSpring))
            }

            VStack(spacing: 0) {
                transcriptionSection
                    .padding(.top, AppSpacing.xl)
                    .padding(.horizontal, AppSpacing.lg)
                Spacer(minLength: AppSpacing.lg)
                previewSection
                buttonSection
            }
        }
        .animation(AppAnimation.gentleSpring, value: voiceService.isRecording)
        .navigationTitle(String(localized: "voice.title"))
        .navigationBarTitleDisplayMode(.inline)
        // ── Confirmation sheet (edit-only mode: returns updated ParsedOperation) ──
        .sheet(item: $editingTarget) { target in
            VoiceInputConfirmationView(
                transactionsViewModel: transactionsViewModel,
                accountsViewModel: accountsViewModel,
                categoriesViewModel: categoriesViewModel,
                parsedOperation: target.operation,
                originalText: capturedText,
                onUpdate: { updated in
                    withAnimation(AppAnimation.gentleSpring) {
                        guard livePreviews.indices.contains(target.index) else { return }
                        livePreviews[target.index] = updated
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
        .onChange(of: voiceService.transcribedText) { _, newText in
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

            // Debounced parse — Apple Speech can emit partials many times per
            // second; we coalesce them into one parse pass per ~300ms.
            parseDebounceTask?.cancel()
            parseDebounceTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                recognizedEntities = parser.parseEntitiesLive(from: newText)

                if !newText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // Multi-operation parse: "500 на такси и 3000 на продукты"
                    // produces two cards; a single clause produces one.
                    let parsed = parser.parseMulti(newText)
                    let next = mergeLivePreviews(existing: livePreviews, parsed: parsed)
                    if next != livePreviews {
                        withAnimation(AppAnimation.gentleSpring) {
                            livePreviews = next
                        }
                    }
                }
            }

            // Throttle VoiceOver announcements — fire at most once per ~700ms
            // and only when the final text differs from the last announced.
            if !newText.isEmpty {
                announcementTask?.cancel()
                announcementTask = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    guard !Task.isCancelled else { return }
                    if newText != lastAnnouncedText {
                        lastAnnouncedText = newText
                        UIAccessibility.post(notification: .announcement, argument: newText)
                    }
                }
            }
        }
        .onAppear { startRecordingOnAppear() }
        .onDisappear {
            parseDebounceTask?.cancel()
            silenceTimer?.cancel()
            announcementTask?.cancel()
            if voiceService.isRecording { voiceService.stopRecording() }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewSection: some View {
        if !livePreviews.isEmpty {
            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(livePreviews.enumerated()), id: \.element.id) { index, preview in
                    StaggeredCard(index: index) {
                        previewCard(for: preview, at: index)
                            .contextMenu {
                                if livePreviews.count > 1 {
                                    Button(role: .destructive) {
                                        withAnimation(AppAnimation.gentleSpring) {
                                            guard livePreviews.indices.contains(index) else { return }
                                            livePreviews.remove(at: index)
                                        }
                                    } label: {
                                        Label(String(localized: "button.delete"), systemImage: "trash")
                                    }
                                }
                            }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
            .task {
                // Let the entrance spring settle before lighting up the
                // beam — running both concurrently is what causes hitch.
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { beamActive = true }
            }
            .onDisappear { beamActive = false }
        }
    }

    /// Preview card matching TransactionCard's visual layout but without
    /// its built-in tap/sheet/swipe gestures. Wrapped in a Button for our own action.
    private func previewCard(for parsed: ParsedOperation, at index: Int) -> some View {
        let amount = (parsed.amount as? NSDecimalNumber)?.doubleValue ?? 0
        let category = parsed.categoryName ?? String(localized: "category.other")
        let currency = parsed.currencyCode ?? accountsViewModel.accounts.first(where: { $0.id == parsed.accountId })?.currency ?? "KZT"
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
            editingTarget = EditingTarget(index: index, operation: parsed)
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

                // Info — mirrors TransactionInfoView in history: category →
                // subcategories → account. Voice-input transcript text is
                // intentionally omitted; the user already sees it at the top.
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(category)
                        .font(AppTypography.h4)
                        .foregroundStyle(AppColors.textPrimary)

                    if !parsed.subcategoryNames.isEmpty {
                        Text(parsed.subcategoryNames.joined(separator: ", "))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    if let accountName = sourceAccount?.name {
                        Text(accountName)
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
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
        .borderGlow(
            isActive: beamActive && voiceService.isRecording,
            colors: [styleData.primaryColor]
        )
        .borderBeam(
            isActive: beamActive && voiceService.isRecording,
            colors: [styleData.primaryColor]
        )
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if voiceService.transcribedText.isEmpty {
                if voiceService.isRecording {
                    PulsingText(text: String(localized: "voice.speak"))
                }
            } else {
                AnimatedTranscriptionText(
                    text: voiceService.transcribedText,
                    entities: recognizedEntities,
                    font: AppTypography.h1,
                    alignment: .leading
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
        } else if !voiceService.transcribedText.isEmpty, !livePreviews.isEmpty {
            // Stopped with parsed previews: confirm saves them all in one batch.
            Button {
                HapticManager.light()
                quickSaveAll(livePreviews)
            } label: {
                Label(confirmButtonLabel(count: livePreviews.count), systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()
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

    /// Voice quick-save creates regular income/expense, never loan/deposit ops.
    /// Resolve account: parsed id wins only if it's a regular account; fall
    /// back to the first regular account otherwise.
    private func makeTransaction(from parsed: ParsedOperation) -> Transaction? {
        let resolvedAccount: Account? = {
            if let parsedId = parsed.accountId,
               let acc = accountsViewModel.accounts.first(where: { $0.id == parsedId }),
               !acc.isLoan, !acc.isDeposit {
                return acc
            }
            return accountsViewModel.regularAccounts.first
        }()
        guard let account = resolvedAccount else { return nil }
        let currency = parsed.currencyCode ?? account.currency

        return Transaction(
            id: "",
            date: DateFormatters.dateFormatter.string(from: parsed.date),
            description: parsed.note.isEmpty ? currentText : parsed.note,
            amount: (parsed.amount as? NSDecimalNumber)?.doubleValue ?? 0,
            currency: currency,
            type: parsed.type,
            category: parsed.categoryName ?? String(localized: "category.other"),
            accountId: account.id
        )
    }

    /// Saves every operation in one atomic batch via `TransactionStore.addBatch`.
    /// Used by both the single-clause and multi-clause flows — same path.
    private func quickSaveAll(_ operations: [ParsedOperation]) {
        let transactions = operations.compactMap(makeTransaction(from:))
        guard !transactions.isEmpty else { return }

        Task {
            do {
                try await transactionStore.addBatch(transactions)
                HapticManager.success()
                // Feed the learning store every confirmed (category → account)
                // pair so the next parse can prefer the user's actual choice.
                for tx in transactions {
                    VoiceLearningStore.shared.recordSave(
                        category: tx.category,
                        accountId: tx.accountId
                    )
                }
                withAnimation(AppAnimation.gentleSpring) {
                    livePreviews = []
                }
                try? await voiceService.startRecording()
            } catch {
                HapticManager.error()
            }
        }
    }

    /// Russian-style plural for the confirm button label.
    /// 1 → «Подтвердить», 2–4 → «Подтвердить N транзакции»,
    /// 5+ / 11–14 → «Подтвердить N транзакций».
    private func confirmButtonLabel(count: Int) -> String {
        if count <= 1 { return String(localized: "voiceConfirmation.confirm") }
        let mod10 = count % 10
        let mod100 = count % 100
        let suffix: String
        if mod10 == 1, mod100 != 11 {
            suffix = "транзакцию"
        } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
            suffix = "транзакции"
        } else {
            suffix = "транзакций"
        }
        return "Подтвердить \(count) \(suffix)"
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

    /// Reconcile the parser's latest snapshot against what's already on
    /// screen so we preserve stable identity for unchanged operations.
    /// Speech recognition streams refinements many times per second; without
    /// this, every refinement would re-trigger a card insertion animation
    /// even though the content matches.
    private func mergeLivePreviews(
        existing: [ParsedOperation],
        parsed: [ParsedOperation]
    ) -> [ParsedOperation] {
        guard !parsed.isEmpty else { return [] }
        var result: [ParsedOperation] = []
        result.reserveCapacity(parsed.count)
        for (idx, newOp) in parsed.enumerated() {
            if idx < existing.count, sameSemantic(existing[idx], newOp) {
                // Treat as the same card — keep the existing id so SwiftUI
                // updates the row in place instead of re-running the entrance.
                result.append(existing[idx])
            } else {
                result.append(newOp)
            }
        }
        return result
    }

    /// Two parsed ops describe the same on-screen card if their visible
    /// fields match; the `id` UUID is deliberately ignored.
    private func sameSemantic(_ lhs: ParsedOperation, _ rhs: ParsedOperation) -> Bool {
        lhs.type == rhs.type
            && lhs.amount == rhs.amount
            && lhs.currencyCode == rhs.currencyCode
            && lhs.accountId == rhs.accountId
            && lhs.categoryName == rhs.categoryName
            && lhs.subcategoryNames == rhs.subcategoryNames
    }
}

// MARK: - Editing Target

extension VoiceInputView {
    /// Pairs the index of the preview being edited with a stable snapshot of
    /// the operation, so the confirmation sheet has an `Identifiable` to
    /// drive `.sheet(item:)`.
    struct EditingTarget: Identifiable {
        let index: Int
        let operation: ParsedOperation
        var id: UUID { operation.id }
    }
}

// MARK: - Staggered Card Wrapper

/// Wraps a preview card and delays its first appearance by `index × 80 ms`
/// so multi-card batches cascade in instead of all popping in at once.
/// Removal is left to the parent's `.transition(...)` so deletions still
/// animate immediately.
private struct StaggeredCard<Content: View>: View {
    let index: Int
    @ViewBuilder var content: () -> Content

    @State private var visible = false

    var body: some View {
        content()
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .task {
                try? await Task.sleep(for: .milliseconds(index * 80))
                guard !Task.isCancelled else { return }
                withAnimation(AppAnimation.gentleSpring) {
                    visible = true
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
            .font(AppTypography.h1)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
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
