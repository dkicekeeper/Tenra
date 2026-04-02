//
//  SubcategoryReorderView.swift
//  AIFinanceManager
//
//  Unified sheet for reordering and managing subcategories within a category.
//  Supports drag-to-reorder, swipe-to-unlink, and adding new subcategories.
//

import SwiftUI

struct SubcategoryReorderView: View {
    let categoriesViewModel: CategoriesViewModel
    let categoryId: String
    @Environment(\.dismiss) private var dismiss

    @State private var orderedSubcategories: [Subcategory] = []
    @State private var showingSubcategorySearch = false

    private nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        EditSheetContainer(
            title: String(localized: "subcategory.reorder"),
            isSaveDisabled: false,
            wrapInForm: false,
            onSave: saveAndDismiss,
            onCancel: { dismiss() }
        ) {
            Group {
                if orderedSubcategories.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet",
                        title: String(localized: "emptyState.noSubcategories"),
                        description: String(localized: "emptyState.startTracking"),
                        actionTitle: String(localized: "category.addSubcategory"),
                        action: { showingSubcategorySearch = true }
                    )
                } else {
                    List {
                        ForEach(orderedSubcategories) { subcategory in
                            let usageCount = categoriesViewModel.subcategoryUsageCount(for: subcategory.id)
                            let lastUsed = categoriesViewModel.subcategoryLastUsedDate(for: subcategory.id)
                            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                Text(subcategory.name)
                                    .font(AppTypography.body)
                                HStack(spacing: AppSpacing.sm) {
                                    if usageCount > 0 {
                                        Text(String(format: String(localized: "subcategory.usageCount"), usageCount))
                                        if let lastUsed {
                                            Text("·")
                                            Text(Self.dateFormatter.string(from: lastUsed))
                                        }
                                    } else {
                                        Text(String(localized: "subcategory.notUsed"))
                                    }
                                }
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary)
                            }
                        }
                        .onMove(perform: moveSubcategory)
                        .onDelete(perform: unlinkSubcategory)

                        Button {
                            showingSubcategorySearch = true
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: "plus.circle.fill")
                                Text(String(localized: "category.addSubcategory"))
                            }
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.accent)
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
        }
        .sheet(isPresented: $showingSubcategorySearch) {
            SubcategorySearchView(
                categoriesViewModel: categoriesViewModel,
                categoryId: categoryId,
                selectedSubcategoryIds: .constant([]),
                searchText: .constant(""),
                selectionMode: .single,
                onSingleSelect: { subcategoryId in
                    categoriesViewModel.linkSubcategoryToCategory(
                        subcategoryId: subcategoryId,
                        categoryId: categoryId
                    )
                    reloadSubcategories()
                    showingSubcategorySearch = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task {
            reloadSubcategories()
        }
    }

    // MARK: - Actions

    private func moveSubcategory(from source: IndexSet, to destination: Int) {
        orderedSubcategories.move(fromOffsets: source, toOffset: destination)
    }

    private func unlinkSubcategory(at offsets: IndexSet) {
        for index in offsets {
            let subcategory = orderedSubcategories[index]
            categoriesViewModel.unlinkSubcategoryFromCategory(
                subcategoryId: subcategory.id,
                categoryId: categoryId
            )
        }
        orderedSubcategories.remove(atOffsets: offsets)
        HapticManager.warning()
    }

    private func reloadSubcategories() {
        orderedSubcategories = categoriesViewModel.getSubcategoriesForCategory(categoryId)
    }

    private func saveAndDismiss() {
        let orderedIds = orderedSubcategories.map { $0.id }
        categoriesViewModel.reorderSubcategories(
            categoryId: categoryId,
            orderedSubcategoryIds: orderedIds
        )
        HapticManager.success()
        dismiss()
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubcategoryReorderView(
        categoriesViewModel: coordinator.categoriesViewModel,
        categoryId: "preview"
    )
}
