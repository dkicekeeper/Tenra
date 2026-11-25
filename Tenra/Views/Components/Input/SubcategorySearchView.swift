//
//  SubcategorySearchView.swift
//  Tenra
//
//  The subcategory picker of the transaction forms, adapter over DesignKit's `SearchablePicker`
//  (8.9.0): the person's subcategories in a glass card, the system search narrowing them, and
//  "Create “…”" for a name none has. Several are picked for a transaction (`.multiple`, each one
//  picked is linked to the transaction's category); one is linked to a category from its
//  subcategories screen (`.single`, only those not linked yet, the sheet closes on a pick).
//  What stays here: the options from `CategoriesViewModel`, the links, and what "Create" stores.
//  Unlinking is the category's subcategories screen's (`SubcategoryReorderView`).
//

import SwiftUI

struct SubcategorySearchView: View {
    let categoriesViewModel: CategoriesViewModel
    let categoryId: String
    @Binding var selectedSubcategoryIds: Set<String>
    @Environment(\.dismiss) private var dismiss

    /// Several for a transaction, or one to link to the category.
    let selectionMode: SelectionMode
    let onSingleSelect: ((String) -> Void)?

    enum SelectionMode {
        /// A transaction's subcategories: a tap picks or unpicks one.
        case multiple
        /// A subcategory to link to the category: a tap picks it and closes the sheet.
        case single
    }

    init(
        categoriesViewModel: CategoriesViewModel,
        categoryId: String,
        selectedSubcategoryIds: Binding<Set<String>>,
        selectionMode: SelectionMode = .multiple,
        onSingleSelect: ((String) -> Void)? = nil
    ) {
        self.categoriesViewModel = categoriesViewModel
        self.categoryId = categoryId
        self._selectedSubcategoryIds = selectedSubcategoryIds
        self.selectionMode = selectionMode
        self.onSingleSelect = onSingleSelect
    }

    var body: some View {
        NavigationStack {
            picker
                .navigationTitle(selectionMode == .single
                    ? String(localized: "subcategorySearch.titleSingle")
                    : String(localized: "navigation.subcategorySearch"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if selectionMode == .single {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                            }
                        } else {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "checkmark")
                            }
                            .dsButton()
                        }
                    }
                }
        }
        .softScrollEdges()
    }

    @ViewBuilder
    private var picker: some View {
        switch selectionMode {
        case .multiple:
            SearchablePicker(options, selection: multipleSelection, prompt: searchPrompt, onCreate: create)
        case .single:
            SearchablePicker(options, selection: singleSelection, prompt: searchPrompt,
                             dismissesOnSelection: true, onCreate: create)
        }
    }

    private var searchPrompt: String {
        String(localized: "subcategorySearch.searchPrompt")
    }

    // MARK: - Options

    /// Every subcategory in its stored order; to link one, only those the category has not got.
    private var options: [SearchablePickerOption<String>] {
        var subcategories = categoriesViewModel.subcategories
        if selectionMode == .single {
            let linked = Set(categoriesViewModel.categorySubcategoryLinks
                .filter { $0.categoryId == categoryId }
                .map(\.subcategoryId))
            subcategories.removeAll { linked.contains($0.id) }
        }
        return subcategories.map { SearchablePickerOption($0.name, value: $0.id) }
    }

    // MARK: - Picking

    /// The transaction's subcategories; one picked is linked to its category.
    private var multipleSelection: Binding<Set<String>> {
        Binding(
            get: { selectedSubcategoryIds },
            set: { picked in
                let added = picked.subtracting(selectedSubcategoryIds)
                selectedSubcategoryIds = picked
                guard !categoryId.isEmpty else { return }
                for id in added {
                    categoriesViewModel.linkSubcategoryToCategory(subcategoryId: id, categoryId: categoryId)
                }
            }
        )
    }

    /// Nothing is shown picked; a pick goes to `onSingleSelect` (SearchablePicker closes the sheet).
    private var singleSelection: Binding<String?> {
        Binding(
            get: { nil },
            set: { id in
                guard let id else { return }
                onSingleSelect?(id)
            }
        )
    }

    /// "Create “name”": a new subcategory, linked to the category when there is one, then picked.
    /// A name that exists (a subcategory already linked is not among the options to link) picks
    /// that one instead of a second of the same name.
    private func create(_ name: String) -> String? {
        if let existing = categoriesViewModel.subcategories.first(where: {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return existing.id
        }
        let subcategory = categoriesViewModel.addSubcategory(name: name)
        // `.multiple` links it once it is picked (multipleSelection).
        if selectionMode == .single, !categoryId.isEmpty {
            categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategory.id, categoryId: categoryId)
        }
        return subcategory.id
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubcategorySearchView(
        categoriesViewModel: coordinator.categoriesViewModel,
        categoryId: "",
        selectedSubcategoryIds: .constant([])
    )
}
