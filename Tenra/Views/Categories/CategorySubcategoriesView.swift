//
//  CategorySubcategoriesView.swift
//  Tenra
//
//  Per-category subcategory management — lets the user link / unlink / reorder
//  subcategories scoped to a single category, instead of jumping into the
//  global SubcategoriesManagementView.
//

import SwiftUI

struct CategorySubcategoriesView: View {
    let categoriesViewModel: CategoriesViewModel
    let category: CustomCategory

    @State private var showingAddNew = false
    @State private var showingLinkExisting = false
    @State private var editingSubcategory: Subcategory?
    @State private var linkSearchText = ""

    private var linkedSubcategories: [Subcategory] {
        categoriesViewModel.getSubcategoriesForCategory(category.id)
    }

    var body: some View {
        Group {
            if linkedSubcategories.isEmpty {
                EmptyStateView(
                    icon: "tag",
                    title: String(localized: "category.subcategories.empty.title", defaultValue: "No subcategories linked"),
                    description: String(localized: "category.subcategories.empty.description", defaultValue: "Link subcategories to this category to organize transactions further."),
                    actionTitle: String(localized: "category.subcategories.empty.action", defaultValue: "Add subcategory"),
                    action: { showingAddNew = true }
                )
            } else {
                List {
                    ForEach(linkedSubcategories) { subcategory in
                        row(for: subcategory)
                    }
                    .onDelete(perform: unlink(at:))
                    .onMove(perform: move(from:to:))
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(String(localized: "category.subcategories.title", defaultValue: "Subcategories"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        HapticManager.light()
                        showingAddNew = true
                    } label: {
                        Label(
                            String(localized: "category.subcategories.addNew", defaultValue: "Create new"),
                            systemImage: "plus.circle"
                        )
                    }
                    Button {
                        HapticManager.light()
                        showingLinkExisting = true
                    } label: {
                        Label(
                            String(localized: "category.subcategories.linkExisting", defaultValue: "Link existing"),
                            systemImage: "link"
                        )
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .glassProminentButton()
            }
        }
        .sheet(isPresented: $showingAddNew) {
            SubcategoryEditView(
                categoriesViewModel: categoriesViewModel,
                subcategory: nil,
                onSave: { newSub in
                    HapticManager.success()
                    let created = categoriesViewModel.addSubcategory(name: newSub.name)
                    categoriesViewModel.linkSubcategoryToCategory(
                        subcategoryId: created.id,
                        categoryId: category.id
                    )
                    showingAddNew = false
                },
                onCancel: { showingAddNew = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $editingSubcategory) { subcategory in
            SubcategoryEditView(
                categoriesViewModel: categoriesViewModel,
                subcategory: subcategory,
                onSave: { updated in
                    HapticManager.success()
                    categoriesViewModel.updateSubcategory(updated)
                    editingSubcategory = nil
                },
                onCancel: { editingSubcategory = nil }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingLinkExisting) {
            NavigationStack {
                SubcategorySearchView(
                    categoriesViewModel: categoriesViewModel,
                    categoryId: category.id,
                    selectedSubcategoryIds: .constant(Set()),
                    searchText: $linkSearchText,
                    selectionMode: .single,
                    onSingleSelect: { subcategoryId in
                        HapticManager.success()
                        categoriesViewModel.linkSubcategoryToCategory(
                            subcategoryId: subcategoryId,
                            categoryId: category.id
                        )
                        showingLinkExisting = false
                    }
                )
                .navigationTitle(String(localized: "category.subcategories.linkExisting", defaultValue: "Link existing"))
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private func row(for subcategory: Subcategory) -> some View {
        let usageCount = categoriesViewModel.subcategoryUsageCount(for: subcategory.id)
        Button {
            HapticManager.selection()
            editingSubcategory = subcategory
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(subcategory.name)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textPrimary)
                Text(
                    usageCount > 0
                        ? String(format: String(localized: "subcategory.usageCount"), usageCount)
                        : String(localized: "subcategory.notUsed")
                )
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func unlink(at offsets: IndexSet) {
        HapticManager.warning()
        for index in offsets {
            let subcategory = linkedSubcategories[index]
            categoriesViewModel.unlinkSubcategoryFromCategory(
                subcategoryId: subcategory.id,
                categoryId: category.id
            )
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = linkedSubcategories.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        categoriesViewModel.reorderSubcategories(
            categoryId: category.id,
            orderedSubcategoryIds: ids
        )
    }
}

#Preview {
    let coordinator = AppCoordinator()
    let sample = coordinator.categoriesViewModel.customCategories.first
        ?? CustomCategory(name: "Groceries", iconSource: .sfSymbol("cart.fill"), colorHex: "#34C759", type: .expense)
    return NavigationStack {
        CategorySubcategoriesView(
            categoriesViewModel: coordinator.categoriesViewModel,
            category: sample
        )
    }
}
