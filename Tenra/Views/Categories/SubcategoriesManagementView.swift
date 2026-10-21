//
//  SubcategoriesManagementView.swift
//  Tenra
//
//  Management view for subcategories
//

import SwiftUI

enum SubcategorySortOrder: String, CaseIterable, Identifiable {
    case alphabetical
    case lastUsed
    case usageCount

    var id: String { rawValue }

    var label: String {
        switch self {
        case .alphabetical: return String(localized: "subcategory.sort.alphabetical")
        case .lastUsed:     return String(localized: "subcategory.sort.lastUsed")
        case .usageCount:   return String(localized: "subcategory.sort.usageCount")
        }
    }

    var icon: String {
        switch self {
        case .alphabetical: return "textformat"
        case .lastUsed:     return "clock"
        case .usageCount:   return "number"
        }
    }
}

struct SubcategoriesManagementView: View {
    let categoriesViewModel: CategoriesViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddSubcategory = false
    @State private var editingSubcategory: Subcategory?
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<String> = []
    /// The subcategories a confirmation is asked for: one from its menu, or the ones selected.
    @State private var subcategoriesToDelete: Set<String> = []
    @State private var sortOrder: SubcategorySortOrder = .alphabetical

    private func handleSortOrderChange(_ newValue: SubcategorySortOrder) {
        HapticManager.selection()
    }

    private var sortedSubcategories: [Subcategory] {
        let subs = categoriesViewModel.subcategories
        switch sortOrder {
        case .alphabetical:
            return subs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed:
            return subs.sorted { lhs, rhs in
                let lDate = categoriesViewModel.subcategoryLastUsedDate(for: lhs.id)
                let rDate = categoriesViewModel.subcategoryLastUsedDate(for: rhs.id)
                switch (lDate, rDate) {
                case let (l?, r?): return l > r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            }
        case .usageCount:
            return subs.sorted { lhs, rhs in
                let lCount = categoriesViewModel.subcategoryUsageCount(for: lhs.id)
                let rCount = categoriesViewModel.subcategoryUsageCount(for: rhs.id)
                if lCount != rCount { return lCount > rCount }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    /// Row stats now come straight from `TransactionStore.subcategoryUsageCountById`
    /// and `subcategoryLastUsedById`, which are O(1) reads maintained
    /// incrementally on every transaction / link mutation. The previous
    /// background-built `stats` cache became unnecessary once those indexes
    /// landed (see TransactionStore+SubcategoryIndex).
    private func subcategoryRow(for subcategory: Subcategory) -> some View {
        SubcategoryManagementRow(
            subcategory: subcategory,
            usageCount: categoriesViewModel.subcategoryUsageCount(for: subcategory.id),
            lastUsedDate: categoriesViewModel.subcategoryLastUsedDate(for: subcategory.id),
            onEdit: { editingSubcategory = subcategory }
        )
        .contextMenu {
            Button {
                editingSubcategory = subcategory
            } label: {
                Label(String(localized: "button.edit", defaultValue: "Edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                HapticManager.warning()
                subcategoriesToDelete = [subcategory.id]
            } label: {
                Label(String(localized: "button.delete"), systemImage: "trash")
            }
        }
    }

    var body: some View {
        Group {
            if categoriesViewModel.subcategories.isEmpty {
                EmptyState(
                    icon: "list.bullet",
                    title: String(localized: "emptyState.noSubcategories"),
                    description: String(localized: "emptyState.startTracking"),
                    actionTitle: String(localized: "subcategory.new"),
                    action: {
                        showingAddSubcategory = true
                    }
                )
            } else {
                // One glass section of rows (DesignKit 8.0.0's `CardList(layout: .section)`), in
                // the chosen sort: the order is the sort's, so there is no dragging.
                ScrollView {
                    CardList(sortedSubcategories, layout: .section, mode: mode, selection: $selection) { subcategory in
                        subcategoryRow(for: subcategory)
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(String(localized: "settings.subcategories"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if mode == .browsing {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("", selection: $sortOrder) {
                            ForEach(SubcategorySortOrder.allCases) { order in
                                Label(order.label, systemImage: order.icon)
                                    .tag(order)
                            }
                        }
                        .pickerStyle(.inline)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel(String(localized: "subcategory.sort.title"))
                }
            }
        }
        .cardListToolbar(
            mode: $mode,
            selection: $selection,
            allIDs: sortedSubcategories.map(\.id),
            canReorder: false,
            addLabel: String(localized: "subcategory.new"),
            onAdd: { showingAddSubcategory = true },
            onDeleteSelected: { subcategoriesToDelete = selection }
        )
        .onChange(of: sortOrder) { _, newValue in
            handleSortOrderChange(newValue)
        }
        .alert(
            subcategoriesToDelete.count > 1
                ? String(format: String(localized: "bulk.deleteSubcategories.title"), subcategoriesToDelete.count)
                : String(localized: "subcategory.deleteTitle", defaultValue: "Delete subcategory?"),
            isPresented: Binding(get: { !subcategoriesToDelete.isEmpty }, set: { if !$0 { subcategoriesToDelete = [] } })
        ) {
            Button(String(localized: "button.cancel"), role: .cancel) {}
            Button(String(localized: "bulk.deleteSubcategories.confirm"), role: .destructive) {
                HapticManager.warning()
                categoriesViewModel.deleteSubcategories(subcategoriesToDelete)
                subcategoriesToDelete = []
                withAnimation(AppAnimation.contentSpring) {
                    selection.removeAll()
                    mode = .browsing
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
    }
}

// MARK: - Stats Types

private struct SubcategoryStat {
    var usageCount: Int
    var lastUsedDate: Date?
}

struct SubcategoryManagementRow: View {
    let subcategory: Subcategory
    let usageCount: Int
    let lastUsedDate: Date?
    let onEdit: () -> Void

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
            ItemRow(subcategory.name, meta: [MetaLine(usage)], style: .large, titleFont: AppTypography.h4)
        }
        .buttonStyle(.plain)
    }

    /// "Used 14 times · Oct 9, 2026", or "Not used".
    private var usage: [MetaItem] {
        guard usageCount > 0 else { return [.text(String(localized: "subcategory.notUsed"))] }
        var items: [MetaItem] = [.text(String(format: NSLocalizedString("subcategory.usageCount", comment: "Count with plural forms in Localizable.stringsdict"), usageCount))]
        if let lastUsed = lastUsedDate {
            items.append(.text(Self.dateFormatter.string(from: lastUsed)))
        }
        return items
    }
}

struct SubcategoryEditView: View {
    let categoriesViewModel: CategoriesViewModel
    let subcategory: Subcategory?
    let onSave: (Subcategory) -> Void
    let onCancel: () -> Void
    
    @State private var name: String = ""
    
    var body: some View {
        EditSheetContainer(
            title: subcategory == nil ? String(localized: "modal.newSubcategory") : String(localized: "modal.editSubcategory"),
            isSaveDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty,
            wrapInForm: false,
            onSave: {
                let subcategoryToSave = Subcategory(
                    id: subcategory?.id ?? UUID().uuidString,
                    name: name
                )
                onSave(subcategoryToSave)
            },
            onCancel: onCancel
        ) {
            // DesignKit's card form (8.0.0: one look; the system Form before).
            ScrollView {
                FormSection(header: String(localized: "common.name")) {
                    FormTextField(
                        text: $name,
                        placeholder: String(localized: "subcategory.namePlaceholder"),
                        style: .row,
                        autofocus: subcategory == nil
                    )
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
            }
        }
        .task {
            name = subcategory?.name ?? ""
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
                onEdit: {}
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
