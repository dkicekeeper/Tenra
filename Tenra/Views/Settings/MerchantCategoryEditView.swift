//
//  MerchantCategoryEditView.swift
//  Tenra
//
//  Reassigns a remembered Wallet merchant (MerchantCategoriesView): the expense
//  category and subcategories its next payments get, with the pickers the
//  transaction forms use. A merchant of the history the memory does not hold yet
//  (MerchantDetailView) is remembered on save. On top, the merchant's name and logo (MerchantLogoStore):
//  a name the user types replaces the bank's text in its transaction rows, an icon
//  they pick replaces the logo Tenra found, and "Show logo" off keeps the category icon. "Forget" drops all of it.
//  For a point of a brand (MerchantGroupStore) the name is the brand's. The category and the
//  subcategories are the carousels alone, without headers (the owner's call, 2026-10-30).
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
    /// Off: "no logo", the merchant's rows keep the category icon (MerchantLogoStore.setHidden).
    @State private var showsLogo: Bool
    private let initiallyShowsLogo: Bool
    /// What the hero showed when the sheet opened: only a change is saved.
    private let initialName: String
    private let initialIcon: IconSource?
    /// The name Tenra makes from the bank's text (MerchantName), or a brand's shared words.
    private let automaticName: String
    /// The brand the merchant is a point of: the name field names the brand.
    private let groupId: String?

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
        let groups = MerchantGroupStore.shared
        let group = groups.group(forMerchant: merchant.displayName)
        let automatic: String
        let startName: String
        if var unnamed = group {
            let typed = unnamed.name
            unnamed.name = nil
            automatic = groups.displayName(of: unnamed)
            startName = typed ?? automatic
        } else {
            automatic = MerchantName.displayName(merchant.displayName)
            startName = store.customName(forDescription: merchant.displayName) ?? automatic
        }
        groupId = group?.id
        let startIcon = store.iconSource(forDescription: merchant.displayName)
        automaticName = automatic
        initialName = startName
        initialIcon = startIcon
        _name = State(initialValue: startName)
        _icon = State(initialValue: startIcon)
        let startShowsLogo = store.state(forMerchant: merchant.displayName) != .hidden
        initiallyShowsLogo = startShowsLogo
        _showsLogo = State(initialValue: startShowsLogo)
    }

    private var expenseCategories: [CustomCategory] {
        categoriesViewModel.customCategories.filter { $0.type == .expense }
    }

    private var selectedCategoryId: String? {
        expenseCategories.first { $0.name == selectedCategory }?.id
    }

    var body: some View {
        EditSheetContainer(
            title: String(localized: "settings.merchants.editTitle"),
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

                    FormSection(footer: String(localized: "settings.merchants.showLogo.footer")) {
                        UniversalRow(
                            String(localized: "settings.merchants.showLogo"),
                            icon: "storefront",
                            accessory: .toggle($showsLogo)
                        )
                    }
                    .screenPadding()

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
        .onChange(of: showsLogo) { _, shows in
            if !shows { icon = nil }
        }
        // A logo picked in the hero is a logo to show.
        .onChange(of: icon) { _, picked in
            if picked != nil { showsLogo = true }
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

    /// The categories' carousel, as on the transaction form.
    private var categorySection: some View {
        CategorySelectorView(
            categories: expenseCategories.map(\.name),
            type: .expense,
            customCategories: categoriesViewModel.customCategories,
            selectedCategory: $selectedCategory
        )
    }

    /// The chosen category's subcategories as chips; nothing until a category is chosen.
    @ViewBuilder
    private var subcategorySection: some View {
        if selectedCategoryId != nil {
            SubcategorySelectorView(
                categoriesViewModel: categoriesViewModel,
                categoryId: selectedCategoryId,
                selectedSubcategoryIds: $selectedSubcategoryIds,
                onSearchTap: {
                    withAnimation(AppAnimation.snappy) { showingSubcategorySearch = true }
                }
            )
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
        if !showsLogo {
            if initiallyShowsLogo { store.setHidden(true, forMerchant: merchant.displayName) }
        } else {
            if !initiallyShowsLogo { store.setHidden(false, forMerchant: merchant.displayName) }
            if icon != initialIcon { store.setCustomIcon(icon, forMerchant: merchant.displayName) }
        }
        if name != initialName {
            // Back to Tenra's own name when cleared or typed as it was.
            let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let custom = typed == automaticName ? nil : typed
            if let groupId {
                MerchantGroupStore.shared.rename(groupId: groupId, to: custom)
            } else {
                store.setCustomName(custom, forMerchant: merchant.displayName)
            }
        }
        HapticManager.success()
        dismiss()
    }

    private func forget() {
        memory.forget(merchantId: merchant.id)
        let store = MerchantLogoStore.shared
        store.setCustomName(nil, forMerchant: merchant.displayName)
        // A picked icon and "no logo" go; a found logo would only be found again.
        switch store.state(forMerchant: merchant.displayName) {
        case .custom?: store.setCustomIcon(nil, forMerchant: merchant.displayName)
        case .hidden?: store.setHidden(false, forMerchant: merchant.displayName)
        default: break
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
