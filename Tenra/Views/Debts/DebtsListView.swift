//
//  DebtsListView.swift
//  Tenra
//
//  Personal debts, from the Debts card in Finances (docs/domains/goals-and-debts.md): what
//  others owe the person, what the person owes, then the settled ones; a tap opens one
//  (DebtDetailView), a long press edits or deletes it, the toolbar selects several to delete
//  and reorders them within their section (DesignKit 8.0.0's `CardList`). Debts are a Tenra Pro feature: every add path routes non-Pro users to the
//  paywall and continues into the form once Pro is on; debts already kept stay open to view.
//

import SwiftUI

struct DebtsListView: View {
    let debtStore: DebtStore

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PremiumManager.self) private var premium
    @State private var showingAdd = false
    @State private var showingPaywall = false
    // DesignKit 8.0.0's list actions: select several, reorder, edit and delete from the menu.
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<String> = []
    @State private var editingDebt: PersonalDebt?
    /// The debts a confirmation is asked for: one from its menu, or the ones selected.
    @State private var debtsToDelete: [String] = []

    var body: some View {
        let today = Date()
        let owedToMe = debtStore.open(.owedToMe)
        let iOwe = debtStore.open(.iOwe)
        let settled = debtStore.settled
        Group {
            if !debtStore.isLoaded {
                // The cards to come (DebtCard is DesignKit's PayoffProgressCard).
                VStack(spacing: AppSpacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        PayoffProgressCardSkeleton().screenPadding()
                    }
                }
                .padding(.vertical, AppSpacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            } else if debtStore.debts.isEmpty {
                MascotEmptyState(
                    icon: "person.2",
                    title: String(localized: "debt.emptyTitle"),
                    description: String(localized: "debt.emptyDescription"),
                    actionTitle: String(localized: "debt.new"),
                    action: add,
                    line: String(localized: "assistant.empty.debts")
                )
                .transition(.skeletonReveal)
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.md) {
                        section(String(localized: "debt.section.owedToMe"), debts: owedToMe, today: today)
                        section(String(localized: "debt.section.iOwe"), debts: iOwe, today: today)
                        section(String(localized: "debt.section.settled"), debts: settled, today: today)
                    }
                    .padding(.vertical, AppSpacing.md)
                }
                .transition(.skeletonReveal)
            }
        }
        .animation(AppAnimation.smooth, value: debtStore.isLoaded)
        .navigationTitle(String(localized: "debt.listTitle"))
        .navigationBarTitleDisplayMode(.large)
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: debtStore.debts.map(\.id),
            addLabel: String(localized: "debt.new"),
            onAdd: add,
            onDeleteSelected: { debtsToDelete = Array(selection) }
        )
        .sheet(item: $editingDebt) { debt in
            DebtEditView(debt: debt, appSettings: coordinator.transactionsViewModel.appSettings) { updated in
                Task { await debtStore.update(updated) }
            }
        }
        .alert(
            debtsToDelete.count > 1
                ? String(format: String(localized: "bulk.deleteDebts.title", defaultValue: "Delete %d debts?"), debtsToDelete.count)
                : String(localized: "debt.deleteTitle"),
            isPresented: Binding(get: { !debtsToDelete.isEmpty }, set: { if !$0 { debtsToDelete = [] } })
        ) {
            Button(String(localized: "button.delete"), role: .destructive) {
                HapticManager.warning()
                let ids = debtsToDelete
                debtsToDelete = []
                Task {
                    for id in ids {
                        await debtStore.delete(id: id)
                    }
                }
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .browsing
                }
            }
            Button(String(localized: "button.cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "debt.deleteMessage"))
        }
        .paywallSheet(isPresented: $showingPaywall) {
            // After unlocking Pro, continue straight into the new debt.
            showingAdd = true
        }
        .sheet(isPresented: $showingAdd) {
            DebtEditView(debt: nil, appSettings: coordinator.transactionsViewModel.appSettings) { debt in
                Task { await debtStore.add(debt) }
            }
        }
        .task { await debtStore.load() }
    }

    /// One way of debts as DesignKit's `CardList` of ready-made cards (8.0.0): a tap opens a
    /// debt, a long press shows Edit and Delete; a drag puts it in its place within the section.
    @ViewBuilder
    private func section(_ title: String, debts: [PersonalDebt], today: Date) -> some View {
        if !debts.isEmpty {
            SectionHeader(title)
                .screenPadding()
                .padding(.top, AppSpacing.sm)
            CardList(debts, layout: .stack, mode: mode, selection: $selection, onMove: { source, destination in
                var reordered = debts
                reordered.move(fromOffsets: source, toOffset: destination)
                Task { await debtStore.reorder(reordered.map(\.id)) }
            }) { debt in
                NavigationLink(value: FinancesDestination.debtDetail(debt.id)) {
                    DebtCard(debt: debt, today: today)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("debts.card")
                .contextMenu {
                    Button {
                        editingDebt = debt
                    } label: {
                        Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        HapticManager.warning()
                        debtsToDelete = [debt.id]
                    } label: {
                        Label(String(localized: "button.delete"), systemImage: "trash")
                    }
                }
            }
            .screenPadding()
        }
    }

    private func add() {
        HapticManager.light()
        if premium.isPro {
            showingAdd = true
        } else {
            showingPaywall = true
        }
    }
}

#Preview("Debts List") {
    let coordinator = AppCoordinator()
    NavigationStack {
        DebtsListView(debtStore: coordinator.debtStore)
    }
    .environment(coordinator)
    // Required: the view reads `@Environment(PremiumManager.self)` for the Pro gate.
    .environment(PremiumManager.shared)
}
