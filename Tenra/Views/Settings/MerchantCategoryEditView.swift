//
//  MerchantCategoryEditView.swift
//  Tenra
//
//  Reassigns a remembered Wallet merchant (MerchantCategoriesView): the expense
//  category and subcategories its next payments get, with the pickers the
//  transaction forms use. A merchant of the history the memory does not hold yet
//  (MerchantDetailView) is remembered on save. On top, the merchant's name and logo (MerchantLogoStore):
//  a name the user types replaces the bank's text in its transaction rows, an icon
//  they pick replaces the logo Tenra found. "Forget" drops all of it.
//

import SwiftUI

struct MerchantCategoryEditView: View {
    let merchant: MerchantCategoryMemory.Merchant
    let categoriesViewModel: CategoriesViewModel
    let memory: MerchantCategoryMemory

    @Environment(\.dismiss) private var dismiss

    /// The category picker works with names; the memory stores ids.
    @State private var selectedCategory: String?
    @State private var selectedSubcategoryIds: Set<String>
    @State private var showingSubcategorySearch = false
    @State private var subcategorySearchText = ""
    @State private var name: String
    @State private var icon: IconSource?
    /// What the hero showed when the sheet opened: only a change is saved.
    private let initialName: String
    private let initialIcon: IconSource?
    /// The name Tenra makes from the bank's text (MerchantName).
    private let automaticName: String

    init(
        merchant: MerchantCategoryMemory.Merchant,
        categoriesViewModel: CategoriesViewModel,
        memory: MerchantCategoryMemory
    ) {
        self.merchant = merchant
        self.categoriesViewModel = categoriesViewModel
        self.memory = memory
        // Initial values here, not in onAppear: the subcategory reset below follows
        // the user's category changes only.
        let current = categoriesViewModel.customCategories
            .first { $0.id == merchant.categoryId && $0.type == .expense }
        _selectedCategory = State(initialValue: current?.name)
        _selectedSubcategoryIds = State(initialValue: Set(current == nil ? [] : merchant.subcategoryIds ?? []))

        let store = MerchantLogoStore.shared
        let automatic = MerchantName.displayName(merchant.displayName)
        let startName = store.customName(forDescription: merchant.displayName) ?? automatic
        let startIcon = store.iconSource(forDescription: merchant.displayName)
        automaticName = automatic
        initialName = startName
        initialIcon = startIcon
        _name = State(initialValue: startName)
        _icon = State(initialValue: startIcon)
    }

    private var expenseCategories: [CustomCategory] {
        categoriesViewModel.customCategories.filter { $0.type == .expense }
    }

    private var selectedCategoryId: String? {
        expenseCategories.first { $0.name == selectedCategory }?.id
    }

    var body: some View {
        EditSheetContainer(
            title: initialName,
            isSaveDisabled: selectedCategoryId == nil,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    EditableHeroSection(
                        iconSource: $icon,
                        title: $name,
                        titlePlaceholder: automaticName
                    )

                    categorySection
                    subcategorySection

                    Text(String(localized: "settings.merchants.editFooter"))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .screenPadding()

                    DSButton(
                        String(localized: "settings.merchants.forgetMerchant"),
                        systemImage: "trash",
                        appearance: .secondary,
                        role: .destructive,
                        fullWidth: true,
                        action: forget
                    )
                    .screenPadding()
                }
                .padding(.vertical, AppSpacing.lg)
            }
        }
        .onChange(of: selectedCategory) { _, _ in
            // Another category's subcategories don't apply.
            selectedSubcategoryIds.removeAll()
        }
        .sheet(isPresented: $showingSubcategorySearch) {
            if let categoryId = selectedCategoryId {
                SubcategorySearchView(
                    categoriesViewModel: categoriesViewModel,
                    categoryId: categoryId,
                    selectedSubcategoryIds: $selectedSubcategoryIds,
                    searchText: $subcategorySearchText
                )
                .onAppear { subcategorySearchText = "" }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Sections

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            SectionHeader(String(localized: "transactionForm.category"))
                .screenPadding()

            CategorySelectorView(
                categories: expenseCategories.map(\.name),
                type: .expense,
                customCategories: categoriesViewModel.customCategories,
                selectedCategory: $selectedCategory
            )
        }
    }

    private var subcategorySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            SectionHeader(String(localized: "loan.subcategoryHeader"))
                .screenPadding()

            if selectedCategoryId != nil {
                SubcategorySelectorView(
                    categoriesViewModel: categoriesViewModel,
                    categoryId: selectedCategoryId,
                    selectedSubcategoryIds: $selectedSubcategoryIds,
                    onSearchTap: {
                        withAnimation(AppAnimation.snappy) { showingSubcategorySearch = true }
                    }
                )
            } else {
                Text(String(localized: "loan.subcategoryEmpty"))
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .screenPadding()
            }
        }
    }

    // MARK: - Actions

    private func save() {
        guard let categoryId = selectedCategoryId else { return }
        if memory.merchant(forDescription: merchant.displayName) != nil {
            memory.reassign(
                merchantId: merchant.id,
                categoryId: categoryId,
                subcategoryIds: Array(selectedSubcategoryIds)
            )
        } else {
            memory.remember(
                categoryId: categoryId,
                subcategoryIds: Array(selectedSubcategoryIds),
                forMerchant: merchant.displayName
            )
        }
        let store = MerchantLogoStore.shared
        if icon != initialIcon {
            store.setCustomIcon(icon, forMerchant: merchant.displayName)
        }
        if name != initialName {
            // Back to Tenra's own name when cleared or typed as it was.
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            store.setCustomName(typed == automaticName ? nil : typed, forMerchant: merchant.displayName)
        }
        HapticManager.success()
        dismiss()
    }

    private func forget() {
        memory.forget(merchantId: merchant.id)
        let store = MerchantLogoStore.shared
        store.setCustomName(nil, forMerchant: merchant.displayName)
        // A picked icon goes; a found logo would only be found again.
        if case .custom? = store.state(forMerchant: merchant.displayName) {
            store.setCustomIcon(nil, forMerchant: merchant.displayName)
        }
        dismiss()
    }
}

#Preview {
    let coordinator = AppCoordinator()
    MerchantCategoryEditView(
        merchant: MerchantCategoryMemory.Merchant(
            id: "greenmart",
            displayName: "GREENMART 12",
            categoryId: "",
            subcategoryIds: nil
        ),
        categoriesViewModel: coordinator.categoriesViewModel,
        memory: MerchantCategoryMemory.shared
    )
}
