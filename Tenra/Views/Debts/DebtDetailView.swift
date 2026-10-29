//
//  DebtDetailView.swift
//  Tenra
//
//  One personal debt (docs/domains/goals-and-debts.md), on EntityDetailScaffold: what is left
//  with the share returned in the hero; "Repayment" and "Settle" while it is open, "Reopen"
//  once settled; which way, the amount, what came back, the dates and the note; then the
//  repayments, newest first, in a card of AmountRows (a long press deletes one, which breaks
//  into dust). A repayment that covers the rest settles the debt, with confetti; one above what
//  is left asks whether to record all of it or only the rest.
//

import SwiftUI

struct DebtDetailView: View {
    let debtStore: DebtStore
    let debtId: String

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(\.amountsHidden) private var amountsHidden
    @State private var showingEdit = false
    @State private var showingRepayment = false
    @State private var showingDelete = false
    /// Bumped when a repayment settles the debt: one confetti burst each time.
    @State private var celebrations = 0
    /// A repayment above what is left, waiting for the person's choice once its sheet is gone.
    @State private var overpayment: PendingRepayment?
    @State private var showingOverpayment = false

    private struct PendingRepayment {
        let amount: Double
        let date: Date
        let note: String?
    }

    private var appSettings: AppSettings { coordinator.transactionsViewModel.appSettings }

    var body: some View {
        Group {
            if let debt = debtStore.debt(id: debtId) {
                scaffold(for: debt)
            } else {
                EmptyState(
                    icon: "person.2",
                    title: String(localized: "debt.notFound"),
                    description: String(localized: "debt.notFoundDescription")
                )
                .navigationTitle(String(localized: "debt.listTitle"))
            }
        }
    }

    @ViewBuilder
    private func scaffold(for debt: PersonalDebt) -> some View {
        let today = Date()
        EntityDetailScaffold(
            navigationTitle: debt.person,
            navigationAmount: debt.remaining,
            navigationCurrency: debt.currency,
            primaryAction: debt.isSettled
                ? ActionConfig(title: String(localized: "debt.reopen"), systemImage: "arrow.uturn.backward") {
                    HapticManager.selection()
                    Task { await debtStore.reopen(id: debt.id) }
                }
                : ActionConfig(title: String(localized: "debt.recordRepayment"), systemImage: "arrow.uturn.down") {
                    HapticManager.light()
                    showingRepayment = true
                },
            secondaryAction: debt.isSettled ? nil : ActionConfig(title: String(localized: "debt.settle"), systemImage: "checkmark") {
                HapticManager.success()
                Task { await debtStore.settle(id: debt.id) }
            },
            infoRows: infoRows(for: debt, today: today),
            hero: {
                HeroSection(
                    icon: debt.iconSource,
                    title: debt.person,
                    primaryAmount: debt.remaining,
                    primaryCurrency: debt.currency,
                    subtitle: heroSubtitle(for: debt),
                    // HeroSection draws "label · NN%": the label is a word, not the share.
                    progress: ProgressConfig(
                        current: debt.isSettled ? debt.amount : debt.repaid,
                        total: debt.amount,
                        label: String(localized: "debt.returned"),
                        color: AppColors.income
                    )
                )
            },
            customSections: {
                if !debt.repayments.isEmpty {
                    repaymentsSection(for: debt)
                }
            },
            toolbarMenu: {
                AskAssistantMenuItem(topic: .debt(person: debt.person, owedToMe: debt.direction == .owedToMe))
                Button {
                    HapticManager.selection()
                    showingEdit = true
                } label: {
                    Label(String(localized: "button.edit"), systemImage: "pencil")
                }
                if debt.isSettled {
                    Button {
                        Task { await debtStore.reopen(id: debt.id) }
                    } label: {
                        Label(String(localized: "debt.reopen"), systemImage: "arrow.uturn.backward")
                    }
                } else {
                    Button {
                        Task { await debtStore.settle(id: debt.id) }
                    } label: {
                        Label(String(localized: "debt.settle"), systemImage: "checkmark")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    HapticManager.warning()
                    showingDelete = true
                } label: {
                    Label(String(localized: "debt.delete"), systemImage: "trash")
                }
            }
        )
        .heroAccentGlow(icon: debt.iconSource)
        // The money sheet already played the success haptic.
        .celebration(trigger: celebrations, playsHaptic: false)
        .sheet(isPresented: $showingEdit) {
            DebtEditView(debt: debt, appSettings: appSettings) { updated in
                Task { await debtStore.update(updated) }
            }
        }
        // The question waits for the sheet to close: a dialog presented while it is closing
        // would not appear.
        .sheet(isPresented: $showingRepayment, onDismiss: {
            if overpayment != nil { showingOverpayment = true }
        }) {
            MoneyEntrySheet(
                title: debt.person,
                icon: debt.iconSource,
                subtitle: String(format: String(localized: "debt.leftAmount"), amountText(debt.remaining, debt.currency)),
                currency: debt.currency,
                appSettings: appSettings,
                suggestedAmount: debt.remaining
            ) { amount, date, note in
                let left = debtStore.debt(id: debt.id)?.remaining ?? debt.remaining
                if amount > left + PersonalDebt.centTolerance {
                    overpayment = PendingRepayment(amount: amount, date: date, note: note)
                } else {
                    recordRepayment(amount, date: date, note: note)
                }
            }
        }
        .confirmationDialog(
            String(localized: "debt.overpay.title"),
            isPresented: $showingOverpayment,
            titleVisibility: .visible,
            presenting: overpayment
        ) { pending in
            Button(String(format: String(localized: "debt.overpay.recordAll"), amountText(pending.amount, debt.currency))) {
                recordRepayment(pending.amount, date: pending.date, note: pending.note)
            }
            Button(String(format: String(localized: "debt.overpay.onlyLeft"), amountText(debt.remaining, debt.currency))) {
                recordRepayment(debt.remaining, date: pending.date, note: pending.note)
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: { _ in
            Text(String(format: String(localized: "debt.overpay.message"), amountText(debt.remaining, debt.currency)))
        }
        .onChange(of: showingOverpayment) { _, showing in
            if !showing { overpayment = nil }
        }
        .alert(String(localized: "debt.deleteTitle"), isPresented: $showingDelete) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                Task { await debtStore.delete(id: debt.id) }
                dismiss()
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "debt.deleteMessage"))
        }
    }

    // MARK: - Sections

    private func heroSubtitle(for debt: PersonalDebt) -> String {
        if let settledAt = debt.settledAt {
            return String(format: String(localized: "debt.settledOn"), DateFormatters.displayDateOmittingCurrentYear(settledAt))
        }
        return debt.direction == .owedToMe
            ? String(localized: "debt.section.owedToMe")
            : String(localized: "debt.section.iOwe")
    }

    private func infoRows(for debt: PersonalDebt, today: Date) -> [InfoRowConfig] {
        var rows = [
            InfoRowConfig(icon: "banknote", label: String(localized: "debt.amount"), amount: debt.amount, currency: debt.currency),
            InfoRowConfig(icon: "arrow.uturn.down", label: String(localized: "debt.returned"), amount: debt.repaid, currency: debt.currency, iconColor: AppColors.income),
            InfoRowConfig(icon: "calendar", label: String(localized: "debt.date"), value: DateFormatters.displayDateOmittingCurrentYear(debt.date)),
        ]
        if let dueDate = debt.dueDate {
            let isOverdue = debt.isOverdue(today: today)
            rows.append(InfoRowConfig(
                icon: "calendar.badge.clock",
                label: String(localized: "debt.dueDate"),
                value: isOverdue
                    ? String(format: String(localized: "debt.overdueSince"), DateFormatters.displayDateOmittingCurrentYear(dueDate))
                    : DateFormatters.displayDateOmittingCurrentYear(dueDate),
                iconColor: isOverdue ? AppColors.destructive : AppColors.accent
            ))
        }
        if let note = debt.note {
            rows.append(InfoRowConfig(icon: "text.alignleft", label: String(localized: "debt.note"), value: note))
        }
        return rows
    }

    private func repaymentsSection(for debt: PersonalDebt) -> some View {
        let repayments = Array(debt.repayments.reversed())
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "debt.repayments"))
            VStack(spacing: 0) {
                ForEach(repayments) { repayment in
                    VStack(spacing: 0) {
                        HistoryEntryRow(
                            date: repayment.date,
                            note: repayment.note,
                            amount: repayment.amount,
                            currency: debt.currency,
                            symbol: "arrow.uturn.down"
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button(role: .destructive) {
                                HapticManager.warning()
                                Task { await debtStore.deleteRepayment(id: repayment.id, from: debt.id) }
                            } label: {
                                Label(String(localized: "button.delete"), systemImage: "trash")
                            }
                        }
                        if repayment.id != repayments.last?.id {
                            RowDivider(inset: AppIconSize.Tile.sm + AppSpacing.md)
                        }
                    }
                    // A deleted entry breaks into dust, as a deleted transaction does.
                    .transition(AsymmetricTransition(insertion: OpacityTransition(), removal: DissolveTransition()))
                }
            }
            .padding(AppSpacing.lg)
            .cardStyle()
            .animation(AppAnimation.gentleSpring, value: repayments.map(\.id))
        }
        .screenPadding()
    }

    // MARK: - Helpers

    /// Saves a repayment; one that covers the rest settles the debt, with confetti.
    private func recordRepayment(_ amount: Double, date: Date, note: String?) {
        guard amount > 0 else { return }
        Task {
            await debtStore.addRepayment(DebtRepayment(amount: amount, date: date, note: note), to: debtId)
            if debtStore.debt(id: debtId)?.isSettled == true {
                celebrations += 1
            }
        }
    }

    private func amountText(_ amount: Double, _ currency: String) -> String {
        amountsHidden
            ? Formatting.hiddenAmount(currency: currency)
            : Formatting.formatCurrencySmart(amount, currency: currency)
    }
}

#Preview("Debt Detail") {
    let coordinator = AppCoordinator()
    NavigationStack {
        DebtDetailView(debtStore: coordinator.debtStore, debtId: "missing")
    }
    .environment(coordinator)
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
