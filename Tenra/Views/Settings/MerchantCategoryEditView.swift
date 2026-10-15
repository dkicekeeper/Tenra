//
//  MerchantCategoryEditView.swift
//  Tenra
//
//  Reassigns a remembered Wallet merchant (MerchantCategoriesView): the expense
//  category and subcategories its next payments get, with the pickers the
//  transaction forms use. "Forget" drops the merchant, so its next payment asks again.
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
    }

    private var expenseCategories: [CustomCategory] {
        categoriesViewModel.customCategories.filter { $0.type == .expense }
    }

    private var selectedCategoryId: String? {
        expenseCategories.first { $0.name == selectedCategory }?.id
    }

    var body: some View {
        EditSheetContainer(
            title: merchant.displayName,
            isSaveDisabled: selectedCategoryId == nil,
            wrapInForm: false,
            onSave: save,
            onCancel: { dismiss() }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
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
        memory.reassign(
            merchantId: merchant.id,
            categoryId: categoryId,
            subcategoryIds: Array(selectedSubcategoryIds)
        )
        HapticManager.success()
        dismiss()
    }

    private func forget() {
        memory.forget(merchantId: merchant.id)
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
