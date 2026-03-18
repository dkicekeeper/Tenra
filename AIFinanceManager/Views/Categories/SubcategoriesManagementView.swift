//
//  SubcategoriesManagementView.swift
//  AIFinanceManager
//
//  Management view for subcategories
//

import SwiftUI

struct SubcategoriesManagementView: View {
    let categoriesViewModel: CategoriesViewModel
    @Environment(\.dismiss) var dismiss
    @State private var showingAddSubcategory = false
    @State private var editingSubcategory: Subcategory?
    
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
                List {
                    ForEach(categoriesViewModel.subcategories) { subcategory in
                        let usageCount = categoriesViewModel.subcategoryUsageCount(for: subcategory.id)
                        let lastUsed = categoriesViewModel.subcategoryLastUsedDate(for: subcategory.id)
                        SubcategoryManagementRow(
                            subcategory: subcategory,
                            usageCount: usageCount,
                            lastUsedDate: lastUsed,
                            onEdit: { editingSubcategory = subcategory },
                            onDelete: {
                                HapticManager.warning()
                                categoriesViewModel.deleteSubcategory(subcategory.id)
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.subcategories"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { 
                    HapticManager.light()
                    showingAddSubcategory = true 
                }) {
                    Image(systemName: "plus")
                }
                .glassProminentButton()
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
                    .font(AppTypography.body)
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
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
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
