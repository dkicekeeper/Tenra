//
//  DebtsListView.swift
//  Tenra
//
//  Personal debts, from the Debts card in Finances (docs/domains/goals-and-debts.md): what
//  others owe the person, what the person owes, then the settled ones; a tap opens one
//  (DebtDetailView). Debts are a Tenra Pro feature: every add path routes non-Pro users to the
//  paywall and continues into the form once Pro is on; debts already kept stay open to view.
//

import SwiftUI

struct DebtsListView: View {
    let debtStore: DebtStore

    @Environment(AppCoordinator.self) private var coordinator
    @Environment(PremiumManager.self) private var premium
    @State private var showingAdd = false
    @State private var showingPaywall = false

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: add) {
                    Image(systemName: "plus")
                }
                .dsButton()
                .accessibilityLabel(String(localized: "debt.new"))
            }
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

    @ViewBuilder
    private func section(_ title: String, debts: [PersonalDebt], today: Date) -> some View {
        if !debts.isEmpty {
            SectionHeader(title)
                .screenPadding()
                .padding(.top, AppSpacing.sm)
            ForEach(Array(debts.enumerated()), id: \.element.id) { index, debt in
                NavigationLink(value: FinancesDestination.debtDetail(debt.id)) {
                    DebtCard(debt: debt, today: today)
                }
                .buttonStyle(.plain)
                .screenPadding()
                .chartAppear(delay: Double(index) * 0.05)
            }
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
