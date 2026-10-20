//
//  SubscriptionsListView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct SubscriptionsListView: View {
    let transactionStore: TransactionStore
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel
    @Environment(TimeFilterManager.self) private var timeFilterManager
    @Namespace private var subscriptionNamespace
    private enum SubscriptionSheetItem: Identifiable {
        case new
        case edit(RecurringSeries)
        /// A "looks like a subscription" candidate, as a new subscription's starting values.
        case draft(RecurringSeries, SubscriptionCandidateDetector.Candidate)
        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let sub): return sub.id
            case .draft(let sub, _): return "draft-" + sub.id
            }
        }
    }
    @State private var sheetItem: SubscriptionSheetItem?
    /// Merchants charged monthly that no subscription tracks (SubscriptionCandidateDetector).
    @State private var candidates: [SubscriptionCandidateDetector.Candidate] = []

    var body: some View {
        ScrollView {
            VStack(spacing: AppSpacing.lg) {
                if !transactionStore.subscriptions.isEmpty {
                    SubscriptionCalendarView(
                        subscriptions: transactionStore.subscriptions,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency
                    )
                    .chartAppear()
                    .screenPadding()
                }

                if transactionStore.subscriptions.isEmpty {
                    emptyState
                        .screenPadding()
                } else {
                    subscriptionsList
                        .screenPadding()
                }

                candidatesSection
            }
            .padding(.vertical, AppSpacing.md)
        }
        .task(id: candidatesKey) {
            await refreshCandidates()
        }
        .navigationTitle(String(localized: "subscriptions.title"))
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: RecurringSeries.self) { subscription in
            SubscriptionDetailView(
                transactionStore: transactionStore,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel,
                subscription: subscription
            )
            .environment(timeFilterManager)
            .navigationTransition(.zoom(sourceID: subscription.id, in: subscriptionNamespace))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetItem = .new
                } label: {
                    Image(systemName: "plus")
                }
                .dsButton()
            }
        }
        .sheet(item: $sheetItem) { item in
            switch item {
            case .new:
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    subscription: nil
                )
            case .edit(let subscription):
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    subscription: subscription
                )
            case .draft(let draft, let candidate):
                SubscriptionEditView(
                    transactionStore: transactionStore,
                    transactionsViewModel: transactionsViewModel,
                    categoriesViewModel: categoriesViewModel,
                    accountsViewModel: accountsViewModel,
                    subscription: nil,
                    draft: draft,
                    // Its charges stay one-offs and a renamed subscription shares no word with
                    // the merchant: without this the candidate would be offered again.
                    onCreated: {
                        SubscriptionCandidateDismissals.dismiss(candidate.merchant)
                        candidates.removeAll { $0.id == candidate.id }
                    }
                )
            }
        }
    }
    
    private var emptyState: some View {
        MascotEmptyState(
            icon: "creditcard",
            title: String(localized: "subscriptions.empty"),
            description: String(localized: "subscriptions.emptyDescription"),
            actionTitle: String(localized: "subscriptions.addSubscription"),
            action: {
                sheetItem = .new
            },
            line: String(localized: "assistant.empty.subscriptions")
        )
    }
    
    // MARK: - Looks like a subscription

    private var candidatesKey: CandidatesKey {
        // `mutationVersion` is @ObservationIgnored: reading the observable arrays is what
        // re-evaluates the body after a transaction or a subscription changes.
        _ = transactionStore.transactions.count
        return CandidatesKey(
            mutationVersion: transactionStore.mutationVersion,
            trackedDescriptions: transactionStore.recurringSeries.map(\.description),
            day: DateFormatters.dateFormatter.string(from: Date())
        )
    }

    private struct CandidatesKey: Equatable {
        let mutationVersion: Int
        let trackedDescriptions: [String]
        /// "At most 40 days old" moves with the day.
        let day: String
    }

    private func refreshCandidates() async {
        let all = transactionStore.transactions
        let tracked = transactionStore.recurringSeries.map(\.description)
        let dismissed = SubscriptionCandidateDismissals.all()
        let found = await Task.detached(priority: .utility) {
            SubscriptionCandidateDetector.candidates(in: all, trackedDescriptions: tracked, dismissed: dismissed)
        }.value
        guard !Task.isCancelled else { return }
        candidates = found
    }

    @ViewBuilder
    private var candidatesSection: some View {
        if !candidates.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                SectionHeader(String(localized: "subscriptions.candidates.title"))
                ForEach(candidates) { candidate in
                    let draft = draftSeries(for: candidate)
                    Button {
                        sheetItem = .draft(draft, candidate)
                    } label: {
                        SubscriptionCard(
                            subscription: draft,
                            nextChargeDate: candidate.nextDate,
                            baseCurrency: transactionsViewModel.appSettings.baseCurrency
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .contextMenu {
                        Button(String(localized: "subscriptions.candidates.dismiss"), systemImage: "xmark") {
                            dismiss(candidate)
                        }
                    }
                    .accessibilityAction(named: Text(String(localized: "subscriptions.candidates.dismiss"))) {
                        dismiss(candidate)
                    }
                }
                Text(String(localized: "subscriptions.candidates.footer"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .screenPadding()
        }
    }

    /// The candidate as a new monthly subscription starting at its next expected charge, so
    /// nothing already recorded is generated again.
    private func draftSeries(for candidate: SubscriptionCandidateDetector.Candidate) -> RecurringSeries {
        let logos = MerchantLogoStore.shared
        return RecurringSeries(
            id: "candidate-" + candidate.id,
            // Through its text: Decimal(Double) keeps binary noise (9.99 → 9.990000000000002).
            amount: Decimal(string: String(candidate.amount)) ?? Decimal(candidate.amount),
            currency: candidate.currency,
            category: candidate.category,
            description: logos.customName(forDescription: candidate.sampleDescription)
                ?? MerchantName.displayName(candidate.sampleDescription),
            accountId: candidate.accountId,
            frequency: .monthly,
            startDate: DateFormatters.dateFormatter.string(from: candidate.nextDate),
            kind: .subscription,
            iconSource: logos.iconSource(forDescription: candidate.sampleDescription),
            status: .active
        )
    }

    private func dismiss(_ candidate: SubscriptionCandidateDetector.Candidate) {
        HapticManager.selection()
        SubscriptionCandidateDismissals.dismiss(candidate.merchant)
        withAnimation(AppAnimation.gentleSpring) {
            candidates.removeAll { $0.id == candidate.id }
        }
    }

    private var subscriptionsList: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(Array(transactionStore.subscriptions.enumerated()), id: \.element.id) { index, subscription in
                let nextChargeDate = transactionStore.nextChargeDate(for: subscription.id)

                NavigationLink(value: subscription) {
                    SubscriptionCard(
                        subscription: subscription,
                        nextChargeDate: nextChargeDate,
                        baseCurrency: transactionsViewModel.appSettings.baseCurrency
                    )
                    .equatable()
                    .matchedTransitionSource(id: subscription.id, in: subscriptionNamespace)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityIdentifier("subscriptions.card")
                .chartAppear(delay: Double(index) * 0.05)
            }
        }
    }
}

// MARK: - Previews

#Preview("Subscriptions List - Empty") {
    let coordinator = AppCoordinator()
    return NavigationStack {
        SubscriptionsListView(
            transactionStore: coordinator.transactionStore,
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
        .environment(TimeFilterManager())
    }
}

#Preview("Subscriptions List - Cards") {
    // Simulates the list body with real SubscriptionCard components
    let dateFormatter = DateFormatters.dateFormatter
    let today = dateFormatter.string(from: Date())
    let sampleSubscriptions = [
        RecurringSeries(id: "p1", amount: Decimal(9.99),  currency: "USD", category: "Развлечения",
                        description: "Netflix",             accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .brandService("Netflix"),  status: .active),
        RecurringSeries(id: "p2", amount: Decimal(4990),  currency: "KZT", category: "Музыка",
                        description: "Spotify Premium",    accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .brandService("Spotify"),  status: .active),
        RecurringSeries(id: "p3", amount: Decimal(2990),  currency: "KZT", category: "Облако",
                        description: "iCloud 50 GB",       accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("cloud.fill"),   status: .active),
        RecurringSeries(id: "p4", amount: Decimal(15000), currency: "KZT", category: "Здоровье",
                        description: "Фитнес зал",         accountId: "acc", frequency: .monthly,
                        startDate: today, kind: .subscription, iconSource: .sfSymbol("dumbbell.fill"), status: .paused)
    ]
    NavigationStack {
        List {
            ForEach(sampleSubscriptions) { sub in
                SubscriptionCard(
                    subscription: sub,
                    nextChargeDate: Date().addingTimeInterval(Double(Int.random(in: 1...28)) * 86400)
                )
            }
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Подписки")
        .navigationBarTitleDisplayMode(.large)
    }
    .environment(TimeFilterManager())
}

#Preview("Subscription Card") {
    let dateFormatter = DateFormatters.dateFormatter
    let today = dateFormatter.string(from: Date())

    let sampleSubscription = RecurringSeries(
        id: "preview-card",
        amount: Decimal(9.99),
        currency: "USD",
        category: "Entertainment",
        description: "Netflix",
        accountId: "preview-account",
        frequency: .monthly,
        startDate: today,
        kind: .subscription,
        iconSource: .brandService("Netflix"),
        status: .active
    )

    SubscriptionCard(
        subscription: sampleSubscription,
        nextChargeDate: Date().addingTimeInterval(7 * 24 * 60 * 60) // 7 days from now
    )
    .padding()
}
