//
//  SubcategoriesManagementView.swift
//  Tenra
//
//  Management view for subcategories
//

import SwiftUI

struct SubcategoriesManagementView: View {
    let categoriesViewModel: CategoriesViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddSubcategory = false
    @State private var editingSubcategory: Subcategory?
    @State private var mode: ManagementMode = .normal
    @State private var selection: Set<String> = []
    @State private var showingBulkDeleteDialog = false

    /// Precomputed per-subcategory stats. The previous implementation called
    /// `subcategoryLastUsedDate` per row, which scanned all 19k transactions and
    /// ran `DateFormatter.date(from:)` on each — that's O(N_subcats × N_tx) on
    /// every list re-render. We instead build the table once per data change in
    /// a single O(N_links + N_tx) pass on a background task.
    @State private var stats: [String: SubcategoryStat] = [:]

    /// Stable trigger for `.task(id:)` — recomputes stats only when the underlying
    /// data actually changes, not on every body re-eval.
    private var statsTrigger: StatsTrigger {
        StatsTrigger(
            subcategoriesCount: categoriesViewModel.subcategories.count,
            linksCount: categoriesViewModel.transactionSubcategoryLinks.count,
            transactionsCount: categoriesViewModel.transactionStore?.transactionsCount ?? 0
        )
    }

    @ViewBuilder
    private func subcategoryRow(for subcategory: Subcategory) -> some View {
        let stat = stats[subcategory.id]
        SubcategoryManagementRow(
            subcategory: subcategory,
            usageCount: stat?.usageCount ?? 0,
            lastUsedDate: stat?.lastUsedDate,
            onEdit: {
                guard !mode.isSelecting else { return }
                editingSubcategory = subcategory
            },
            onDelete: {
                HapticManager.warning()
                categoriesViewModel.deleteSubcategory(subcategory.id)
            }
        )
    }

    var body: some View {
        Group {
            if categoriesViewModel.subcategories.isEmpty {
                EmptyStateView(
                    icon: "list.bullet",
                    title: String(localized: "emptyState.noSubcategories"),
                    description: String(localized: "emptyState.startTracking"),
                    actionTitle: String(localized: "subcategory.new"),
                    action: {
                        showingAddSubcategory = true
                    }
                )
            } else {
                List(selection: mode.isSelecting ? $selection : nil) {
                    ForEach(categoriesViewModel.subcategories) { subcategory in
                        subcategoryRow(for: subcategory)
                    }
                }
                .environment(\.editMode, .constant(mode.editMode))
            }
        }
        .navigationTitle(String(localized: "settings.subcategories"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                switch mode {
                case .normal:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) { mode = .selecting }
                    } label: {
                        Image(systemName: "checkmark.circle")
                    }
                    .accessibilityLabel(String(localized: "bulk.select"))
                case .selecting:
                    Button {
                        HapticManager.light()
                        withAnimation(AppAnimation.contentSpring) {
                            mode = .normal
                            selection.removeAll()
                        }
                    } label: {
                        Text(String(localized: "bulk.done"))
                    }
                    .glassProminentButton()
                case .reordering:
                    EmptyView()
                }
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                if mode == .normal {
                    Button(action: {
                        HapticManager.light()
                        showingAddSubcategory = true
                    }) {
                        Image(systemName: "plus")
                    }
                    .glassProminentButton()
                } else if mode.isSelecting {
                    Button {
                        HapticManager.selection()
                        let allIds = Set(categoriesViewModel.subcategories.map(\.id))
                        if selection == allIds {
                            selection.removeAll()
                        } else {
                            selection = allIds
                        }
                    } label: {
                        Text(selection.count == categoriesViewModel.subcategories.count
                             ? String(localized: "bulk.deselectAll")
                             : String(localized: "bulk.selectAll"))
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if mode.isSelecting && !selection.isEmpty {
                BulkDeleteButton(count: selection.count) {
                    showingBulkDeleteDialog = true
                }
                .animation(AppAnimation.contentSpring, value: selection.count)
            }
        }
        .alert(
            String(format: String(localized: "bulk.deleteSubcategories.title"), selection.count),
            isPresented: $showingBulkDeleteDialog
        ) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "bulk.deleteSubcategories.confirm"), role: .destructive) {
                HapticManager.warning()
                categoriesViewModel.deleteSubcategories(selection)
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .normal
                }
            }
        }
        .sheet(isPresented: $showingAddSubcategory) {
            SubcategoryEditView(
                categoriesViewModel: categoriesViewModel,
                subcategory: nil,
                onSave: { subcategory in
                    HapticManager.success()
                    _ = categoriesViewModel.addSubcategory(name: subcategory.name)
                    showingAddSubcategory = false
                },
                onCancel: { showingAddSubcategory = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingSubcategory) { subcategory in
            SubcategoryEditView(
                categoriesViewModel: categoriesViewModel,
                subcategory: subcategory,
                onSave: { updatedSubcategory in
                    HapticManager.success()
                    categoriesViewModel.updateSubcategory(updatedSubcategory)
                    editingSubcategory = nil
                },
                onCancel: { editingSubcategory = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task(id: statsTrigger) {
            await refreshStats()
        }
    }

    // MARK: - Stats Refresh

    private func refreshStats() async {
        // Snapshot Sendable scalars on MainActor before crossing the thread.
        let linksSnapshot: [(subcategoryId: String, transactionId: String)] =
            categoriesViewModel.transactionSubcategoryLinks.map {
                (subcategoryId: $0.subcategoryId, transactionId: $0.transactionId)
            }
        let txDates: [(id: String, date: String)] =
            categoriesViewModel.transactionStore?.transactions.map { (id: $0.id, date: $0.date) } ?? []

        let computed = await Task.detached(priority: .userInitiated) {
            Self.buildStats(links: linksSnapshot, txDates: txDates)
        }.value

        guard !Task.isCancelled else { return }
        stats = computed
    }

    /// Single O(N_links + N_tx) build:
    ///   1. tx-id → parsed Date map (one DateFormatter pass).
    ///   2. walk links once — increment usage count and track max date per subcategory.
    private nonisolated static func buildStats(
        links: [(subcategoryId: String, transactionId: String)],
        txDates: [(id: String, date: String)]
    ) -> [String: SubcategoryStat] {
        var dateById: [String: Date] = [:]
        dateById.reserveCapacity(txDates.count)
        for entry in txDates {
            if let date = DateFormatters.dateFormatter.date(from: entry.date) {
                dateById[entry.id] = date
            }
        }

        var result: [String: SubcategoryStat] = [:]
        for link in links {
            var stat = result[link.subcategoryId] ?? SubcategoryStat(usageCount: 0, lastUsedDate: nil)
            stat.usageCount += 1
            if let txDate = dateById[link.transactionId] {
                if let existing = stat.lastUsedDate {
                    if txDate > existing { stat.lastUsedDate = txDate }
                } else {
                    stat.lastUsedDate = txDate
                }
            }
            result[link.subcategoryId] = stat
        }
        return result
    }
}

// MARK: - Stats Types

private struct SubcategoryStat {
    var usageCount: Int
    var lastUsedDate: Date?
}

private struct StatsTrigger: Equatable {
    let subcategoriesCount: Int
    let linksCount: Int
    let transactionsCount: Int
}

struct SubcategoryManagementRow: View {
    let subcategory: Subcategory
    let usageCount: Int
    let lastUsedDate: Date?
    let onEdit: () -> Void
    let onDelete: () -> Void

    private nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        Button {
            HapticManager.selection()
            onEdit()
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(subcategory.name)
                    .font(AppTypography.h4)
                HStack(spacing: AppSpacing.sm) {
                    if usageCount > 0 {
                        Text(String(format: String(localized: "subcategory.usageCount"), usageCount))
                        if let lastUsed = lastUsedDate {
                            Text("·")
                            Text(Self.dateFormatter.string(from: lastUsed))
                        }
                    } else {
                        Text(String(localized: "subcategory.notUsed"))
                    }
                }
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
        }
    }
}

struct SubcategoryEditView: View {
    let categoriesViewModel: CategoriesViewModel
    let subcategory: Subcategory?
    let onSave: (Subcategory) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    @FocusState private var isNameFocused: Bool
    
    var body: some View {
        EditSheetContainer(
            title: subcategory == nil ? String(localized: "modal.newSubcategory") : String(localized: "modal.editSubcategory"),
            isSaveDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            onSave: {
                let subcategoryToSave = Subcategory(
                    id: subcategory?.id ?? UUID().uuidString,
                    name: name
                )
                onSave(subcategoryToSave)
            },
            onCancel: onCancel
        ) {
            Section(header: Text(String(localized: "common.name"))) {
                TextField(String(localized: "subcategory.namePlaceholder"), text: $name)
                    .focused($isNameFocused)
            }
        }
        .task {
            if let subcategory = subcategory {
                name = subcategory.name
                isNameFocused = false
            } else {
                name = ""
                // Yield to the runloop so the view finishes layout before activating focus
                await Task.yield()
                isNameFocused = true
            }
        }
    }
}

#Preview("Subcategories Management") {
    let coordinator = AppCoordinator()
    NavigationStack {
        SubcategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
}

#Preview("Subcategories Management - Empty") {
    let coordinator = AppCoordinator()
    coordinator.categoriesViewModel.subcategories = []
    
    return NavigationStack {
        SubcategoriesManagementView(
            categoriesViewModel: coordinator.categoriesViewModel
        )
    }
}

#Preview("Subcategory Row") {
    let sampleSubcategories = [
        Subcategory(id: "preview-1", name: "Groceries"),
        Subcategory(id: "preview-2", name: "Restaurants"),
        Subcategory(id: "preview-3", name: "Fast Food"),
        Subcategory(id: "preview-4", name: "Coffee Shops")
    ]
    
    return List {
        ForEach(Array(sampleSubcategories.enumerated()), id: \.element.id) { index, subcategory in
            SubcategoryManagementRow(
                subcategory: subcategory,
                usageCount: [5, 12, 0, 3][index],
                lastUsedDate: index == 2 ? nil : Date().addingTimeInterval(Double(-index) * 86400),
                onEdit: {},
                onDelete: {}
            )
        }
    }
    .listStyle(PlainListStyle())
}

#Preview("Subcategory Edit View - New") {
    let coordinator = AppCoordinator()
    
    return SubcategoryEditView(
        categoriesViewModel: coordinator.categoriesViewModel,
        subcategory: nil,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Subcategory Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleSubcategory = Subcategory(
        id: "preview",
        name: "Test Subcategory"
    )
    
    return SubcategoryEditView(
        categoriesViewModel: coordinator.categoriesViewModel,
        subcategory: sampleSubcategory,
        onSave: { _ in },
        onCancel: {}
    )
}
