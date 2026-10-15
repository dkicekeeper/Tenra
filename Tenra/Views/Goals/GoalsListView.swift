//
//  GoalsListView.swift
//  Tenra
//
//  The savings goals, from the Goals card in Finances (docs/domains/goals-and-debts.md): goals
//  in progress, then the reached ones; a tap opens one (GoalDetailView), "+" adds one. Goals
//  are free.
//

import SwiftUI

struct GoalsListView: View {
    let goalStore: GoalStore

    @Environment(AppCoordinator.self) private var coordinator
    @State private var showingAdd = false

    private var baseCurrency: String {
        coordinator.transactionsViewModel.appSettings.baseCurrency
    }

    /// Accounts a goal can follow: everything but loans.
    private var followableAccounts: [Account] {
        coordinator.transactionStore.accounts.filter { $0.loanInfo == nil }
    }

    var body: some View {
        let today = Date()
        let inProgress = goalStore.goals.filter { !goalStore.status(for: $0, today: today).isReached }
        let reached = goalStore.goals.filter { goalStore.status(for: $0, today: today).isReached }
        Group {
            if !goalStore.isLoaded {
                Color.clear
            } else if goalStore.goals.isEmpty {
                EmptyState(
                    icon: "target",
                    title: String(localized: "goal.emptyTitle"),
                    description: String(localized: "goal.emptyDescription"),
                    actionTitle: String(localized: "goal.new"),
                    action: {
                        HapticManager.light()
                        showingAdd = true
                    }
                )
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        ForEach(Array(inProgress.enumerated()), id: \.element.id) { index, goal in
                            row(goal, today: today)
                                .chartAppear(delay: Double(index) * 0.05)
                        }
                        if !reached.isEmpty {
                            SectionHeader(String(localized: "goal.reachedSection"))
                                .screenPadding()
                                .padding(.top, AppSpacing.sm)
                            ForEach(reached) { goal in
                                row(goal, today: today)
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(String(localized: "goal.listTitle"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HapticManager.light()
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .dsButton()
                .accessibilityLabel(String(localized: "goal.new"))
            }
        }
        .sheet(isPresented: $showingAdd) {
            GoalEditView(goal: nil, accounts: followableAccounts, baseCurrency: baseCurrency) { goal in
                Task { await goalStore.add(goal) }
            }
        }
        .task { await goalStore.load() }
    }

    private func row(_ goal: SavingsGoal, today: Date) -> some View {
        NavigationLink(value: FinancesDestination.goalDetail(goal.id)) {
            GoalCard(
                goal: goal,
                status: goalStore.status(for: goal, today: today),
                accountName: goalStore.followsAccount(goal)
                    ? coordinator.transactionStore.accounts.first { $0.id == goal.linkedAccountId }?.name
                    : nil
            )
        }
        .buttonStyle(.plain)
        .screenPadding()
    }
}

#Preview("Goals List") {
    let coordinator = AppCoordinator()
    NavigationStack {
        GoalsListView(goalStore: coordinator.goalStore)
    }
    .environment(coordinator)
}
