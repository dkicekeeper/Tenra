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
    /// The one-time hint on screen (DesignKit's spotlight), if any.
    @State private var tourHint: FeatureTourState.Hint?

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
                        ToolbarItem(placement: .topBarLeading) {
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

    /// Screenshot capture mode renders a static "recording" look (wave + sample
    /// phrase) because speech recognition can't run in the Simulator.
    private var isScreenshotDemo: Bool {
        #if DEBUG
        return ScreenshotDemoMode.isActive
        #else
        return false
        #endif
    }

    private var coreContent: some View {
        ZStack {
            if voiceService.isRecording || isScreenshotDemo {
                VoiceLevelGlow(voiceService: voiceService, followsVoice: !isScreenshotDemo)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(AppAnimation.gentleSpring))
            }

            VStack(spacing: 0) {
                transcriptionSection
                    .padding(.top, AppSpacing.xl)
                    .screenPadding()
                Spacer(minLength: AppSpacing.lg)
                previewSection
                buttonSection
            }
        }
        .animation(AppAnimation.gentleSpring, value: voiceService.isRecording)
        // Once: the first recording points at the orb, the new stop button.
        .spotlight(
            $tourHint,
            message: { _ in String(localized: "voice.tour.orb") },
            cornerRadius: VoiceStopOrb.spotlightRadius
        )
        .onChange(of: voiceService.isRecording) { _, isRecording in
            if isRecording {
                showStopOrbHintIfNeeded()
            } else {
                tourHint = nil
            }
        }
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
            // Unconditional: `isRecording` is still false while the audio stack is
            // coming up, and skipping the call there left the microphone open once the
            // pending start finished. `stopRecording()` guards itself and also cancels
            // an in-flight start (see `VoiceInputService.startToken`).
            voiceService.stopRecording()
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var previewSection: some View {
        if !livePreviews.isEmpty {
            VStack(spacing: AppSpacing.sm) {
                ForEach(Array(livePreviews.enumerated()), id: \.element.id) { index, preview in
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
                        // Several operations cascade in, 80 ms apart (DesignKit's cascadeIn).
                        .cascadeIn(index: index)
                    // A deleted card breaks into dust (DesignKit's dissolve).
                    .transition(AsymmetricTransition(
                        insertion: MoveTransition(edge: .bottom).combined(with: OpacityTransition()),
                        removal: DissolveTransition()
                    ))
                }
            }
            .screenPadding()
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
                // Icon — same as the history row (TransactionCardView)
                Icon(
                    source: .sfSymbol(styleData.iconName),
                    style: .circle(
                        size: AppIconSize.Tile.sm,
                        tint: .monochrome(styleData.primaryColor),
                        backgroundColor: styleData.lightBackgroundColor
                    )
                )

                // Info — mirrors the history row: category →
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

                // Amount — same as the transaction row
                FormattedAmountText(
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
                #if DEBUG
                if isScreenshotDemo {
                    AnimatedTranscriptionText(
                        text: ScreenshotDemoLexicon.current().voiceDemoPhrase,
                        entities: [],
                        font: AppTypography.h1,
                        alignment: .leading
                    )
                } else if voiceService.isRecording {
                    ListeningPrompt()
                }
                #else
                if voiceService.isRecording {
                    ListeningPrompt()
                }
                #endif
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
        if voiceService.isRecording || isScreenshotDemo {
            // Recording: the voice orb is the stop button. Its frame leaves room for the glow,
            // which may spill over the neighbours, so it takes back that room vertically.
            HStack {
                Spacer()
                VoiceStopOrb(
                    voiceService: voiceService,
                    followsVoice: !isScreenshotDemo,
                    action: handleStopTap
                )
                Spacer()
            }
            .padding(.vertical, -AppSpacing.xl)
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
            .dsButton()
            .screenPadding()
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
        HapticManager.play(.tap)
        voiceService.stopRecording()
        silenceTimer?.cancel()
    }

    /// The first recording shows, once, that the orb is the stop button. A tap anywhere
    /// lifts the hint; stopping the recording lifts it too.
    private func showStopOrbHintIfNeeded() {
        guard !isScreenshotDemo, !FeatureTourState.hasSeen(.voiceStopOrb) else { return }
        Task {
            // Let the orb settle in first.
            try? await Task.sleep(for: .seconds(1))
            guard voiceService.isRecording else { return }
            FeatureTourState.markSeen(.voiceStopOrb)
            tourHint = .voiceStopOrb
        }
    }

    /// One operation ready to save, before its currency conversion (`converted`).
    private struct QuickSaveDraft {
        let transaction: Transaction
        let accountCurrency: String
    }

    /// Voice quick-save creates regular income/expense, never loan/deposit ops.
    /// Resolve account: parsed id wins only if it's a regular account; fall
    /// back to the first regular account otherwise.
    private func makeDraft(from parsed: ParsedOperation) -> QuickSaveDraft? {
        let resolvedAccount: Account? = {
            if let parsedId = parsed.accountId,
               let acc = accountsViewModel.accounts.first(where: { $0.id == parsedId }),
               !acc.isLoan, !acc.isDeposit {
                return acc
            }
            return accountsViewModel.regularAccounts.first
        }()
        guard let account = resolvedAccount else { return nil }
        // No positive amount: drop this one operation. Passed through as 0 it failed
        // validation, and addBatch rejected the whole batch.
        let amount = (parsed.amount as? NSDecimalNumber)?.doubleValue ?? 0
        guard amount > 0 else { return nil }
        let currency = parsed.currencyCode ?? account.currency
        // The parser maps keywords onto built-in names ("Еда", "Other") that the user's
        // categories may not have (renamed or deleted). An unknown name failed validation
        // and the whole batch was rejected, so Confirm saved nothing. Resolve it as the
        // App Intents do: exact, case-insensitive, related name, the user's "Other", else
        // uncategorized (which the store accepts).
        let category = TransactionDraftService.resolveCategory(
            named: parsed.categoryName,
            type: parsed.type,
            in: categoriesViewModel.customCategories
        ).name

        let transaction = Transaction(
            id: "",
            date: DateFormatters.dateFormatter.string(from: parsed.date),
            description: parsed.note.isEmpty ? currentText : parsed.note,
            amount: amount,
            currency: currency,
            type: parsed.type,
            category: category,
            accountId: account.id
        )
        return QuickSaveDraft(transaction: transaction, accountCurrency: account.currency)
    }

    /// The draft's transaction with its conversion fields (`TransactionConversion`), nil
    /// when its amount is in another currency than the account's and no rate is cached.
    private func converted(_ draft: QuickSaveDraft, baseCurrency: String) -> Transaction? {
        let tx = draft.transaction
        guard let fields = TransactionConversion.singleAccount(
            amount: tx.amount,
            currency: tx.currency,
            accountCurrency: draft.accountCurrency,
            baseCurrency: baseCurrency,
            convert: TransactionConversion.cachedRate
        ) else { return nil }
        return Transaction(
            id: tx.id,
            date: tx.date,
            description: tx.description,
            amount: tx.amount,
            currency: tx.currency,
            convertedAmount: fields.convertedAmount,
            type: tx.type,
            category: tx.category,
            accountId: tx.accountId,
            targetCurrency: fields.targetCurrency,
            targetAmount: fields.targetAmount,
            createdAt: tx.createdAt
        )
    }

    /// Every draft converted, or nil when one of them has no rate.
    private func convertedForSaving(_ drafts: [QuickSaveDraft], baseCurrency: String) -> [Transaction]? {
        var transactions: [Transaction] = []
        for draft in drafts {
            guard let tx = converted(draft, baseCurrency: baseCurrency) else { return nil }
            transactions.append(tx)
        }
        return transactions
    }

    /// Saves every operation in one atomic batch via `TransactionStore.addBatch`.
    /// Used by both the single-clause and multi-clause flows — same path.
    private func quickSaveAll(_ operations: [ParsedOperation]) {
        let drafts = operations.compactMap(makeDraft(from:))
        guard !drafts.isEmpty else { return }
        let baseCurrency = transactionStore.baseCurrency

        Task {
            // An amount in another currency than its account's posts converted, like the
            // add screen. It was saved raw: 10 USD came off a KZT card as 10 ₸. Rates are
            // loaded once on a miss (or a missing "≈" equivalent); still without a rate the
            // batch is refused and says why.
            var ready = convertedForSaving(drafts, baseCurrency: baseCurrency)
            let lacksEquivalent = ready?.contains { $0.currency != baseCurrency && $0.targetAmount == nil } ?? true
            if lacksEquivalent {
                let currencies = drafts.flatMap { [$0.transaction.currency, $0.accountCurrency] }
                await TransactionConversion.loadRates(Set(currencies + [baseCurrency]))
                ready = convertedForSaving(drafts, baseCurrency: baseCurrency)
            }
            guard let transactions = ready else {
                HapticManager.error()
                errorAlertMessage = String(localized: "currency.error.conversionFailed")
                showingErrorAlert = true
                return
            }

            do {
                try await transactionStore.addBatch(transactions)
                HapticManager.success()
                // Count only: recording restarts right below, don't pop the survey over the mic.
                RatingPromptService.shared.recordTransactionAdded(count: transactions.count, promptNow: false)
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
                // Say why instead of only buzzing: nothing was saved.
                HapticManager.error()
                errorAlertMessage = error.localizedDescription
                showingErrorAlert = true
            }
        }
    }

    /// Plural forms live in Localizable.stringsdict (voiceConfirmation.confirmCount).
    private func confirmButtonLabel(count: Int) -> String {
        if count <= 1 { return String(localized: "voiceConfirmation.confirm") }
        return String(format: NSLocalizedString("voiceConfirmation.confirmCount", comment: "Confirm button with transaction count"), count)
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

// MARK: - Listening Prompt

/// "Speak..." while nothing is recognized yet: DesignKit's thinking shimmer runs through it, in
/// the voice orb's colours (a still gradient under Reduce Motion).
private struct ListeningPrompt: View {
    var body: some View {
        Text(String(localized: "voice.speak"))
            .font(AppTypography.h1)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .thinkingShimmer()
            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Edge glow

/// The recording screen's edge light, following the voice. Its own small view, so the level
/// (about 47 updates a second) redraws the glow only, not the screen.
private struct VoiceLevelGlow: View {
    let voiceService: VoiceInputService
    /// Off for screenshots, where nothing is recorded: the glow then breathes on its own.
    let followsVoice: Bool

    var body: some View {
        EdgeGlow(level: followsVoice ? voiceService.audioLevel : nil)
    }
}

// MARK: - Stop orb

/// The stop button while recording: DesignKit's voice orb, swelling with the voice, with a
/// small stop glyph in the middle. At rest the orb is about the size of the old 80 pt button;
/// only that circle takes the tap. Its own small view, so the level (about 47 updates a second)
/// redraws the orb only.
private struct VoiceStopOrb: View {
    let voiceService: VoiceInputService
    /// Off for screenshots, where nothing is recorded: the orb then breathes on its own.
    let followsVoice: Bool
    let action: () -> Void

    /// The orb's canvas: room for it to swell and for its glow.
    private static let size: CGFloat = 144
    /// The tappable circle: the canvas inset to about the orb at rest.
    private static let tapInset: CGFloat = 32
    /// The orb at rest, the circle the tap and the hint's cut-out go round.
    private static let restingDiameter: CGFloat = size - 2 * tapInset
    /// The hint's cut-out: a circle round the resting orb and the spotlight's padding.
    static let spotlightRadius: CGFloat = restingDiameter / 2 + AppSpacing.sm

    var body: some View {
        Button(action: action) {
            VoiceWave(level: followsVoice ? voiceService.audioLevel : nil, style: .orb)
                .frame(width: Self.size, height: Self.size)
                .overlay {
                    Image(systemName: "stop.fill")
                        .font(.system(size: AppIconSize.lg))
                        .foregroundStyle(AppColors.staticWhite)
                        .shadow(color: .black.opacity(0.25), radius: 4)
                }
                .contentShape(Circle().inset(by: Self.tapInset))
        }
        .buttonStyle(.bounce)
        .accessibilityLabel(String(localized: "voice.stopRecording"))
        .background {
            Color.clear
                .frame(width: Self.restingDiameter, height: Self.restingDiameter)
                .spotlightAnchor(FeatureTourState.Hint.voiceStopOrb)
        }
    }
}
