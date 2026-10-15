//
//  GoalDetailView.swift
//  Tenra
//
//  One savings goal (docs/domains/goals-and-debts.md), on EntityDetailScaffold: the saved
//  amount with the share of the target in the hero; "Add money" (a goal without an account)
//  and "Edit"; the target, what is left, the deadline, what to put aside each month and the
//  account it follows; then the contributions, newest first, in a card of AmountRows (a long
//  press deletes one, which breaks into dust). When the goal is reached (a contribution, an
//  edit, or the linked account's balance growing), confetti bursts once.
//

import SwiftUI

struct GoalDetailView: View {
    let goalStore: GoalStore
    let goalId: String

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.amountsHidden) private var amountsHidden
    @State private var showingEdit = false
    @State private var showingContribution = false
    @State private var showingDelete = false
    /// Bumped when the goal is reached: one confetti burst each time.
    @State private var celebrations = 0

    private var appSettings: AppSettings { coordinator.transactionsViewModel.appSettings }

    var body: some View {
        Group {
            if let goal = goalStore.goal(id: goalId) {
                scaffold(for: goal)
            } else {
                EmptyState(
                    icon: "target",
                    title: String(localized: "goal.notFound"),
                    description: String(localized: "goal.notFoundDescription")
                )
                .navigationTitle(String(localized: "goal.listTitle"))
            }
        }
    }

    @ViewBuilder
    private func scaffold(for goal: SavingsGoal) -> some View {
        let status = goalStore.status(for: goal)
        let follows = goalStore.followsAccount(goal)
        EntityDetailScaffold(
            navigationTitle: goal.name,
            navigationAmount: status.saved,
            navigationCurrency: goal.currency,
            primaryAction: follows ? nil : ActionConfig(
                title: String(localized: "goal.contribute"),
                systemImage: "plus",
                action: {
                    HapticManager.light()
                    showingContribution = true
                }
            ),
            secondaryAction: ActionConfig(
                title: String(localized: "button.edit"),
                systemImage: "pencil",
                action: {
                    HapticManager.selection()
                    showingEdit = true
                }
            ),
            infoRows: infoRows(for: goal, status: status, follows: follows),
            hero: {
                HeroSection(
                    icon: goal.iconSource ?? SavingsGoal.defaultIcon,
                    title: goal.name,
                    primaryAmount: status.saved,
                    primaryCurrency: goal.currency,
                    subtitle: String(format: String(localized: "goal.ofTarget"), amountText(goal.targetAmount, goal.currency)),
                    // HeroSection draws "label · NN%": the label is a word, not the share.
                    progress: ProgressConfig(
                        current: status.saved,
                        total: goal.targetAmount,
                        label: String(localized: "goal.savedShare"),
                        color: AppColors.income
                    )
                )
            },
            customSections: {
                if !follows, !goal.contributions.isEmpty {
                    contributionsSection(for: goal)
                }
            },
            toolbarMenu: {
                AskAssistantMenuItem(topic: .goal(name: goal.name))
                Button {
                    HapticManager.selection()
                    showingEdit = true
                } label: {
                    Label(String(localized: "button.edit"), systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    HapticManager.warning()
                    showingDelete = true
                } label: {
                    Label(String(localized: "goal.delete"), systemImage: "trash")
                }
            }
        )
        .heroAccentGlow(icon: goal.iconSource ?? SavingsGoal.defaultIcon)
        // The money sheet already played the success haptic.
        .celebration(trigger: celebrations, playsHaptic: false)
        .sheet(isPresented: $showingEdit) {
            GoalEditView(
                goal: goal,
                accounts: coordinator.transactionStore.accounts.filter { $0.loanInfo == nil },
                baseCurrency: appSettings.baseCurrency
            ) { updated in
                Task {
                    await goalStore.update(updated)
                    await checkReached()
                }
            }
        }
        .sheet(isPresented: $showingContribution) {
            MoneyEntrySheet(
                title: goal.name,
                icon: goal.iconSource ?? SavingsGoal.defaultIcon,
                subtitle: status.isReached ? nil : String(format: String(localized: "goal.leftAmount"), amountText(status.left, goal.currency)),
                currency: goal.currency,
                appSettings: appSettings
            ) { amount, date, note in
                Task {
                    await goalStore.addContribution(GoalContribution(amount: amount, date: date, note: note), to: goal.id)
                    await checkReached()
                }
            }
        }
        .alert(String(localized: "goal.deleteTitle"), isPresented: $showingDelete) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                Task { await goalStore.delete(id: goal.id) }
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "goal.deleteMessage"))
        }
        // A linked account's balance can reach the target while the screen is open.
        .task(id: status.isReached) {
            await checkReached()
        }
    }

    // MARK: - Sections

    private func infoRows(for goal: SavingsGoal, status: GoalProgress.Status, follows: Bool) -> [InfoRowConfig] {
        var rows = [
            InfoRowConfig(icon: "flag.checkered", label: String(localized: "goal.target"), amount: goal.targetAmount, currency: goal.currency)
        ]
        if !status.isReached {
            rows.append(InfoRowConfig(icon: "hourglass", label: String(localized: "goal.left"), amount: status.left, currency: goal.currency))
        }
        if let deadline = goal.deadline {
            rows.append(InfoRowConfig(
                icon: "calendar",
                label: String(localized: "goal.deadline"),
                value: status.isOverdue
                    ? String(localized: "goal.overdue")
                    : DateFormatters.displayDateOmittingCurrentYear(deadline),
                iconColor: status.isOverdue ? AppColors.destructive : AppColors.accent
            ))
        }
        if let monthly = status.monthly {
            rows.append(InfoRowConfig(icon: "calendar.badge.plus", label: String(localized: "goal.monthly"), amount: monthly, currency: goal.currency))
        }
        if follows, let account = coordinator.transactionStore.accounts.first(where: { $0.id == goal.linkedAccountId }) {
            rows.append(InfoRowConfig(icon: "building.columns", label: String(localized: "goal.account"), value: account.name))
        }
        if status.isReached, let reachedAt = goal.reachedAt {
            rows.append(InfoRowConfig(
                icon: "checkmark.seal",
                label: String(localized: "goal.reached"),
                value: DateFormatters.displayDateOmittingCurrentYear(reachedAt),
                iconColor: AppColors.income
            ))
        }
        return rows
    }

    private func contributionsSection(for goal: SavingsGoal) -> some View {
        let contributions = Array(goal.contributions.reversed())
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "goal.contributions"))
            VStack(spacing: 0) {
                ForEach(contributions) { contribution in
                    VStack(spacing: 0) {
                        HistoryEntryRow(
                            date: contribution.date,
                            note: contribution.note,
                            amount: contribution.amount,
                            currency: goal.currency,
                            symbol: "plus"
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                HapticManager.warning()
                                Task {
                                    await goalStore.deleteContribution(id: contribution.id, from: goal.id)
                                    await checkReached()
                                }
                            } label: {
                                Label(String(localized: "button.delete"), systemImage: "trash")
                            }
                        }
                        if contribution.id != contributions.last?.id {
                            Divider().padding(.leading, AppIconSize.Tile.sm + AppSpacing.md)
                        }
                    }
                    // A deleted entry breaks into dust, as a deleted transaction does.
                    .transition(AsymmetricTransition(insertion: OpacityTransition(), removal: DissolveTransition()))
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
            .animation(AppAnimation.gentleSpring, value: contributions.map(\.id))
        }
        .screenPadding()
    }

    // MARK: - Helpers

    private func checkReached() async {
        if await goalStore.refreshReached(goalId: goalId) {
            celebrations += 1
        }
    }

    private func amountText(_ amount: Double, _ currency: String) -> String {
        amountsHidden
            ? Formatting.hiddenAmount(currency: currency)
            : Formatting.formatCurrencySmart(amount, currency: currency)
    }
}

#Preview("Goal Detail") {
    let coordinator = AppCoordinator()
    NavigationStack {
        GoalDetailView(goalStore: coordinator.goalStore, goalId: "missing")
    }
    .environment(coordinator)
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
