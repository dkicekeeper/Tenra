//
//  MerchantCategoriesView.swift
//  Tenra
//
//  Settings → Siri & Shortcuts → Wallet merchants: the merchants the Wallet
//  automation (AddExpenseIntent) remembered, each with its category and
//  subcategory. Tap a merchant to reassign them (MerchantCategoryEditView), swipe
//  to forget it: its next payment asks for a category again.
//

import SwiftUI

struct MerchantCategoriesView: View {
    let categoriesViewModel: CategoriesViewModel

    @State private var memory = MerchantCategoryMemory.shared
    @State private var editing: MerchantCategoryMemory.Merchant?

    var body: some View {
        Group {
            if memory.merchants.isEmpty {
                EmptyState(
                    icon: "wallet.pass",
                    title: String(localized: "settings.merchants.emptyTitle"),
                    description: String(localized: "settings.merchants.emptyMessage")
                )
            } else {
                List {
                    Section {
                        ForEach(memory.merchants) { merchant in
                            row(merchant)
                        }
                    } footer: {
                        Text(String(localized: "settings.merchants.footer"))
                    }
                }
            }
        }
        .navigationTitle(String(localized: "settings.merchants.title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { merchant in
            MerchantCategoryEditView(
                merchant: merchant,
                categoriesViewModel: categoriesViewModel,
                memory: memory
            )
        }
    }

    // MARK: - Row

    private func row(_ merchant: MerchantCategoryMemory.Merchant) -> some View {
        let category = expenseCategory(id: merchant.categoryId)
        return Button {
            editing = merchant
        } label: {
            UniversalRow(config: .settings, leadingIcon: iconConfig(for: category)) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(MerchantName.displayName(merchant.displayName))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(assignment(of: merchant, category: category))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            } trailing: {
                DisclosureChevron()
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.warning()
                memory.forget(merchantId: merchant.id)
            } label: {
                Label(String(localized: "settings.merchants.forget"), systemImage: "trash")
            }
        }
    }

    private func expenseCategory(id: String) -> CustomCategory? {
        categoriesViewModel.customCategories.first { $0.id == id && $0.type == .expense }
    }

    /// "Category · Subcategory", or that the category was deleted (the merchant is then asked
    /// about again, until reassigned here).
    private func assignment(of merchant: MerchantCategoryMemory.Merchant, category: CustomCategory?) -> String {
        guard let category else { return String(localized: "settings.merchants.categoryDeleted") }
        let ids = Set(merchant.subcategoryIds ?? [])
        let subcategoryNames = categoriesViewModel.subcategories
            .filter { ids.contains($0.id) }
            .map(\.name)
        guard !subcategoryNames.isEmpty else { return category.name }
        return ([category.name] + [subcategoryNames.joined(separator: ", ")]).joined(separator: " · ")
    }

    /// Plated like the category filter rows: the icon in the category's colour on a pale
    /// circle of it; a deleted category shows the neutral folder.
    private func iconConfig(for category: CustomCategory?) -> IconConfig {
        if let category {
            return .custom(
                source: category.iconSource,
                style: .circle(
                    size: AppIconSize.xl,
                    tint: .monochrome(category.color),
                    backgroundColor: AppColors.pale(category.color)
                )
            )
        }
        return .custom(
            source: .sfSymbol("folder"),
            style: .circle(
                size: AppIconSize.xl,
                tint: .monochrome(AppColors.textSecondary),
                backgroundColor: AppColors.Status.neutralPale
            )
        )
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        MerchantCategoriesView(categoriesViewModel: coordinator.categoriesViewModel)
    }
}
