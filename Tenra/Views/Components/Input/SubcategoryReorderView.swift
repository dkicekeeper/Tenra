//
//  SubcategoryReorderView.swift
//  Tenra
//
//  A category's subcategories, with DesignKit 8.0.0's one set of actions on a list: a long
//  press unlinks one, the toolbar selects several to unlink, changes the order by dragging and
//  adds a subcategory. Every change applies at once.
//

import SwiftUI

struct SubcategoryReorderView: View {
    let categoriesViewModel: CategoriesViewModel
    let categoryId: String
    @Environment(\.dismiss) private var dismiss

    @State private var orderedSubcategories: [Subcategory] = []
    @State private var showingSubcategorySearch = false
    @State private var mode: CardListMode = .browsing
    @State private var selection: Set<String> = []

    private nonisolated static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if orderedSubcategories.isEmpty {
                    EmptyState(
                        icon: "list.bullet",
                        title: String(localized: "emptyState.noSubcategories"),
                        description: String(localized: "emptyState.startTracking"),
                        actionTitle: String(localized: "category.addSubcategory"),
                        action: { showingSubcategorySearch = true }
                    )
                } else {
                    ScrollView {
                        CardList(
                            orderedSubcategories,
                            layout: .section,
                            mode: mode,
                            selection: $selection,
                            onMove: moveSubcategory
                        ) { subcategory in
                            row(for: subcategory)
                        }
                        .screenPadding()
                    }
                }
            }
            .navigationTitle(String(localized: "subcategory.reorder"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .browsing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String(localized: "button.close"), systemImage: "xmark") {
                            dismiss()
                        }
                    }
                }
            }
            .cardListToolbar(
                mode: $mode,
                selection: $selection,
                allIDs: orderedSubcategories.map(\.id),
                addLabel: String(localized: "category.addSubcategory"),
                onAdd: { showingSubcategorySearch = true },
                onDeleteSelected: unlinkSelected
            )
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

    // MARK: - Row

    private func row(for subcategory: Subcategory) -> some View {
        let usageCount = categoriesViewModel.subcategoryUsageCount(for: subcategory.id)
        let lastUsed = categoriesViewModel.subcategoryLastUsedDate(for: subcategory.id)
        return VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(subcategory.name)
                .font(AppTypography.body)
            HStack(spacing: AppSpacing.sm) {
                if usageCount > 0 {
                    Text(String(format: NSLocalizedString("subcategory.usageCount", comment: "Count with plural forms in Localizable.stringsdict"), usageCount))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
        .contextMenu {
            Button(role: .destructive) {
                unlink([subcategory.id])
            } label: {
                Label(String(localized: "subcategorySearch.unlink"), systemImage: "link.slash")
            }
        }
    }

    // MARK: - Actions

    private func moveSubcategory(from source: IndexSet, to destination: Int) {
        orderedSubcategories.move(fromOffsets: source, toOffset: destination)
        categoriesViewModel.reorderSubcategories(
            categoryId: categoryId,
            orderedSubcategoryIds: orderedSubcategories.map(\.id)
        )
    }

    /// Unlinking keeps the subcategory itself, so it asks for no confirmation.
    private func unlinkSelected() {
        unlink(selection)
        withAnimation(AppAnimation.contentSpring) {
            selection.removeAll()
            mode = .browsing
        }
    }

    private func unlink(_ ids: Set<String>) {
        for id in ids {
            categoriesViewModel.unlinkSubcategoryFromCategory(subcategoryId: id, categoryId: categoryId)
        }
        withAnimation(AppAnimation.contentSpring) {
            orderedSubcategories.removeAll { ids.contains($0.id) }
        }
        HapticManager.warning()
    }

    private func reloadSubcategories() {
        orderedSubcategories = categoriesViewModel.getSubcategoriesForCategory(categoryId)
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubcategoryReorderView(
        categoriesViewModel: coordinator.categoriesViewModel,
        categoryId: "preview"
    )
}
