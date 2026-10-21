//
//  GoalsListView.swift
//  Tenra
//
//  The savings goals, from the Goals card in Finances (docs/domains/goals-and-debts.md): goals
//  in progress, then the reached ones; a tap opens one (GoalDetailView), a long press edits or
//  deletes it, the toolbar selects several to delete, reorders them and adds one (DesignKit
//  8.0.0's `CardList`). Goals are free.
//

import SwiftUI

struct GoalsListView: View {
    let goalStore: GoalStore

    @Environment(AppCoordinator.self) private var coordinator
    @State private var showingAdd = false
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<String> = []
    @State private var editingGoal: SavingsGoal?
    /// The goals a confirmation is asked for: one from its menu, or the ones selected.
    @State private var goalsToDelete: [String] = []

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
                // The cards to come (GoalCard is DesignKit's PayoffProgressCard).
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        PayoffProgressCardSkeleton().screenPadding()
                    }
                }
                .padding(.vertical, AppSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            } else if goalStore.goals.isEmpty {
                MascotEmptyState(
                    icon: "target",
                    title: String(localized: "goal.emptyTitle"),
                    description: String(localized: "goal.emptyDescription"),
                    actionTitle: String(localized: "goal.new"),
                    action: {
                        HapticManager.light()
                        showingAdd = true
                    },
                    line: String(localized: "assistant.empty.goals")
                )
                .transition(.skeletonReveal)
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        list(inProgress, today: today)
                        if !reached.isEmpty {
                            SectionHeader(String(localized: "goal.reachedSection"))
                                .screenPadding()
                                .padding(.top, AppSpacing.sm)
                            list(reached, today: today)
                        }
                    }
                    .padding(.vertical, AppSpacing.md)
                }
                .transition(.skeletonReveal)
            }
        }
        .animation(AppAnimation.smooth, value: goalStore.isLoaded)
        .navigationTitle(String(localized: "goal.listTitle"))
        .navigationBarTitleDisplayMode(.large)
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: goalStore.goals.map(\.id),
            addLabel: String(localized: "goal.new"),
            onAdd: { showingAdd = true },
            onDeleteSelected: { goalsToDelete = Array(selection) }
        )
        .sheet(isPresented: $showingAdd) {
            GoalEditView(goal: nil, accounts: followableAccounts, baseCurrency: baseCurrency) { goal in
                Task { await goalStore.add(goal) }
            }
        }
        .sheet(item: $editingGoal) { goal in
            GoalEditView(goal: goal, accounts: followableAccounts, baseCurrency: baseCurrency) { updated in
                Task { await goalStore.update(updated) }
            }
        }
        .alert(
            goalsToDelete.count > 1
                ? String(format: String(localized: "bulk.deleteGoals.title", defaultValue: "Delete %d goals?"), goalsToDelete.count)
                : String(localized: "goal.deleteTitle"),
            isPresented: Binding(get: { !goalsToDelete.isEmpty }, set: { if !$0 { goalsToDelete = [] } })
        ) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                let ids = goalsToDelete
                goalsToDelete = []
                Task {
                    for id in ids {
                        await goalStore.delete(id: id)
                    }
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .browsing
                }
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "goal.deleteMessage"))
        }
        .task { await goalStore.load() }
    }

    /// Goals as DesignKit's `CardList` of ready-made cards (8.0.0); a drag puts a goal in its
    /// place within its list.
    private func list(_ goals: [SavingsGoal], today: Date) -> some View {
        CardList(goals, layout: .stack, mode: mode, selection: $selection, onMove: { source, destination in
            var reordered = goals
            reordered.move(fromOffsets: source, toOffset: destination)
            Task { await goalStore.reorder(reordered.map(\.id)) }
        }) { goal in
            row(goal, today: today)
        }
        .screenPadding()
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
        .accessibilityIdentifier("goals.card")
        .contextMenu {
            Button {
                editingGoal = goal
            } label: {
                Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                HapticManager.warning()
                goalsToDelete = [goal.id]
            } label: {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
        }
    }
}

#Preview("Goals List") {
    let coordinator = AppCoordinator()
    NavigationStack {
        GoalsListView(goalStore: coordinator.goalStore)
    }
    .environment(coordinator)
}
