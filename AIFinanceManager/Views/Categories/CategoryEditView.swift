//
//  CategoryEditView.swift
//  AIFinanceManager
//
//  Migrated to hero-style UI (Phase 16 - 2026-02-16)
//  Uses EditableHeroSection with color picker and beautiful animations
//

import SwiftUI

struct CategoryEditView: View {
    let categoriesViewModel: CategoriesViewModel
    let transactionsViewModel: TransactionsViewModel
    let category: CustomCategory?
    let type: TransactionType
    let onSave: (CustomCategory) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @State private var selectedIconSource: IconSource? = .sfSymbol("banknote.fill")
    @State private var selectedColor: String = "#3b82f6"
    @State private var showingSubcategoryPicker = false
    @State private var validationError: String? = nil

    // Budget fields (only for expense categories)
    @State private var budgetAmount: String = ""
    @State private var selectedPeriod: CustomCategory.BudgetPeriod = .monthly
    @State private var resetDay: Int = 1

    private var parsedBudget: Double? {
        guard type == .expense, !budgetAmount.isEmpty, let amount = Double(budgetAmount), amount > 0 else {
            return nil
        }
        return amount
    }

    private var linkedSubcategories: [Subcategory] {
        guard let category = category else { return [] }
        return categoriesViewModel.getSubcategoriesForCategory(category.id)
    }

    var body: some View {
        EditSheetContainer(
            title: category == nil ? String(localized: "modal.newCategory") : String(localized: "modal.editCategory"),
            isSaveDisabled: name.isEmpty,
            wrapInForm: false,
            onSave: saveCategory,
            onCancel: onCancel
        ) {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    // Hero Section with Icon, Name, and Color Picker
                    EditableHeroSection(
                        iconSource: $selectedIconSource,
                        title: $name,
                        selectedColor: $selectedColor,
                        titlePlaceholder: String(localized: "category.namePlaceholder"),
                        config: .categoryHero
                    )

                    // Validation Error
                    if let error = validationError {
                        InlineStatusText(message: error, type: .error)
                            .padding(.horizontal, AppSpacing.lg)
                    }

                    // Budget Settings Section (expense categories only)
                    if type == .expense {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                SectionHeaderView(
                                    String(localized: "category.budget", defaultValue: "Budget"),
                                    style: .default
                                )
                                Spacer()
                            }
                            BudgetSettingsSection(
                                budgetAmount: $budgetAmount,
                                selectedPeriod: $selectedPeriod,
                                resetDay: $resetDay
                            )
                        }
                    }

                    // Subcategories Section (edit mode only)
                    if let category = category {
                        FormSection(header: String(localized: "category.subcategories")) {
                            ForEach(linkedSubcategories) { subcategory in
                                UniversalRow(config: .standard) {
                                    Text(subcategory.name)
                                        .font(AppTypography.body)
                                        .foregroundStyle(AppColors.textPrimary)
                                } trailing: {
                                    Button(action: {
                                        HapticManager.light()
                                        categoriesViewModel.unlinkSubcategoryFromCategory(subcategoryId: subcategory.id, categoryId: category.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(AppColors.destructive)
                                    }
                                }
                                Divider()
                            }

                            UniversalRow(config: .standard, leadingIcon: .sfSymbol("plus.circle.fill", color: AppColors.accent)) {
                                Text(String(localized: "category.addSubcategory"))
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.accent)
                            }
                            .actionRow {
                                HapticManager.light()
                                showingSubcategoryPicker = true
                            }
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
            }
        }
        .sheet(isPresented: $showingSubcategoryPicker) {
            SubcategorySearchView(
                categoriesViewModel: categoriesViewModel,
                categoryId: category?.id ?? "",
                selectedSubcategoryIds: .constant([]),
                searchText: .constant(""),
                selectionMode: .single,
                onSingleSelect: { subcategoryId in
                    if let categoryId = category?.id {
                        categoriesViewModel.linkSubcategoryToCategory(subcategoryId: subcategoryId, categoryId: categoryId)
                    }
                    showingSubcategoryPicker = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            if let category = category {
                name = category.name
                selectedIconSource = category.iconSource
                selectedColor = category.colorHex

                // Load budget fields if exists
                if let amount = category.budgetAmount {
                    budgetAmount = String(Int(amount))
                } else {
                    budgetAmount = ""
                }
                selectedPeriod = category.budgetPeriod
                resetDay = category.budgetResetDay
            }
        }
    }

    // MARK: - Save Category

    private func saveCategory() {
        // Validate name
        guard !name.isEmpty else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                validationError = String(localized: "error.categoryNameRequired")
            }
            HapticManager.error()
            return
        }

        // Clear validation error
        validationError = nil

        let newCategory = CustomCategory(
            id: category?.id ?? UUID().uuidString,
            name: name,
            iconSource: selectedIconSource ?? .sfSymbol("star.fill"),
            colorHex: selectedColor,
            type: type,
            budgetAmount: parsedBudget,
            budgetPeriod: selectedPeriod,
            budgetResetDay: resetDay,
            order: category?.order
        )

        HapticManager.success()
        onSave(newCategory)
    }
}

#Preview("Category Edit View - New") {
    let coordinator = AppCoordinator()

    return CategoryEditView(
        categoriesViewModel: coordinator.categoriesViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        category: nil,
        type: .expense,
        onSave: { _ in },
        onCancel: {}
    )
}

#Preview("Category Edit View - Edit") {
    let coordinator = AppCoordinator()
    let sampleCategory = CustomCategory(
        id: "preview",
        name: "Food",
        iconSource: .sfSymbol("fork.knife"),
        colorHex: "#ec4899",
        type: .expense,
        budgetAmount: 10000,
        budgetPeriod: .monthly,
        budgetResetDay: 1
    )

    return CategoryEditView(
        categoriesViewModel: coordinator.categoriesViewModel,
        transactionsViewModel: coordinator.transactionsViewModel,
        category: sampleCategory,
        type: .expense,
        onSave: { _ in },
        onCancel: {}
    )
}
