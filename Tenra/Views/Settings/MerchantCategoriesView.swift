//
//  MerchantCategoriesView.swift
//  Tenra
//
//  Settings → Wallet → Merchants: the merchants the Wallet
//  automation remembered, each with its category and subcategory. Tap a merchant to
//  open its screen (MerchantDetailView), whose Edit reassigns them
//  (MerchantCategoryEditView); swipe to forget it.
//

import SwiftUI

struct MerchantCategoriesView: View {
    let transactionsViewModel: TransactionsViewModel
    let categoriesViewModel: CategoriesViewModel
    let accountsViewModel: AccountsViewModel

    @State private var memory = MerchantCategoryMemory.shared
    @State private var opened: MerchantCategoryMemory.Merchant?
    /// Settings → Wallet → "Merchant logos" (on by default), as on the merchant's transaction rows.
    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    var body: some View {
        Group {
            if memory.merchants.isEmpty {
                EmptyState(
                    icon: "wallet.pass",
                    title: String(localized: "settings.merchants.emptyTitle"),
                    description: String(localized: "settings.merchants.emptyMessage")
                )
            } else {
                // DesignKit 8.0.0: a glass section on the page (a List before).
                ScrollView {
                    FormSection(footer: String(localized: "settings.merchants.footer")) {
                        ForEach(memory.merchants) { merchant in
                            row(merchant)
                        }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.md)
                }
            }
        }
        .navigationTitle(String(localized: "settings.merchants.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $opened) { merchant in
            MerchantDetailView(
                merchant: merchant.displayName,
                transactionsViewModel: transactionsViewModel,
                categoriesViewModel: categoriesViewModel,
                accountsViewModel: accountsViewModel
            )
        }
    }

    // MARK: - Row

    private func row(_ merchant: MerchantCategoryMemory.Merchant) -> some View {
        let category = expenseCategory(id: merchant.categoryId)
        return Button {
            opened = merchant
        } label: {
            UniversalRow(leadingIcon: iconConfig(for: merchant, category: category)) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(MerchantLogoStore.shared.customName(forDescription: merchant.displayName)
                         ?? MerchantName.displayName(merchant.displayName))
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
        .accessibilityIdentifier("merchants.row.\(merchant.id)")
        // The button keeps the row's divider inset to itself: the 44 pt tile and its space.
        .rowDividerInset(AppIconSize.Tile.sm + AppSpacing.md)
        // A long press forgets the merchant (DesignKit 8.0.0: no swipe actions).
        .contextMenu {
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

    /// The merchant's logo, found or picked (when logos are on), as its transaction rows show
    /// it; else plated like the category filter rows: the icon in the category's colour on a
    /// pale circle of it; a deleted category shows the neutral folder. 44 pt (`Tile.sm`), the
    /// size of the accounts, deposits and categories lists.
    private func iconConfig(for merchant: MerchantCategoryMemory.Merchant, category: CustomCategory?) -> IconConfig {
        if showsMerchantLogos,
           let logo = MerchantLogoStore.shared.iconSource(forDescription: merchant.displayName) {
            return .custom(
                source: logo,
                style: .circle(
                    size: AppIconSize.Tile.sm,
                    tint: .original,
                    backgroundColor: category.map { AppColors.pale($0.color) } ?? AppColors.Status.neutralPale
                )
            )
        }
        if let category {
            return .custom(
                source: category.iconSource,
                style: .circle(
                    size: AppIconSize.Tile.sm,
                    tint: .monochrome(category.color),
                    backgroundColor: AppColors.pale(category.color)
                )
            )
        }
        return .custom(
            source: .sfSymbol("folder"),
            style: .circle(
                size: AppIconSize.Tile.sm,
                tint: .monochrome(AppColors.textSecondary),
                backgroundColor: AppColors.Status.neutralPale
            )
        )
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        MerchantCategoriesView(
            transactionsViewModel: coordinator.transactionsViewModel,
            categoriesViewModel: coordinator.categoriesViewModel,
            accountsViewModel: coordinator.accountsViewModel
        )
    }
    .environment(coordinator.transactionStore)
    .environment(TimeFilterManager())
}
