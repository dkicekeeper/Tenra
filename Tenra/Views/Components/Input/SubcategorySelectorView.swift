//
//  SubcategorySelectorView.swift
//  AIFinanceManager
//
//  Horizontal scrollable subcategory selector with FilterChip style
//

import SwiftUI

struct SubcategorySelectorView: View {
    let categoriesViewModel: CategoriesViewModel
    let categoryId: String?
    @Binding var selectedSubcategoryIds: Set<String>
    let onSearchTap: () -> Void
    var onReorderTap: (() -> Void)?

    private var availableSubcategories: [Subcategory] {
        guard let categoryId = categoryId else { return [] }
        let linkedSubcategories = categoriesViewModel.getSubcategoriesForCategory(categoryId)

        // Добавляем выбранные подкатегории, которые могут быть не привязаны к категории
        let selectedSubcategories = categoriesViewModel.subcategories.filter { selectedSubcategoryIds.contains($0.id) }

        // Объединяем и убираем дубликаты
        var allSubcategories = linkedSubcategories
        for selected in selectedSubcategories {
            if !allSubcategories.contains(where: { $0.id == selected.id }) {
                allSubcategories.append(selected)
            }
        }

        return allSubcategories
    }

    var body: some View {
        if !availableSubcategories.isEmpty {
            UniversalCarousel(config: .filter) {
                ForEach(availableSubcategories) { subcategory in
                    UniversalFilterButton(
                        title: subcategory.name,
                        isSelected: selectedSubcategoryIds.contains(subcategory.id),
                        showChevron: false,
                        onTap: {
                            if selectedSubcategoryIds.contains(subcategory.id) {
                                selectedSubcategoryIds.remove(subcategory.id)
                            } else {
                                selectedSubcategoryIds.insert(subcategory.id)
                            }
                            HapticManager.selection()
                        }
                    )
                }

                // Кнопка поиска
                Button(action: onSearchTap) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppIconSize.sm))
                }
                .filterChipStyle()
                .accessibilityLabel(String(localized: "transactionForm.searchSubcategories"))

                // Кнопка сортировки
                if let onReorderTap {
                    Button(action: onReorderTap) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: AppIconSize.sm))
                    }
                    .filterChipStyle()
                    .accessibilityLabel(String(localized: "subcategory.reorder"))
                }
            }
        } else {
            // Если нет подкатегорий, показываем только кнопку поиска на всю ширину
            Button(action: onSearchTap) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: AppIconSize.sm))
                    Text(String(localized: "transactionForm.addSubcategory"))
                }
            }
            .filterChipStyle()
            .accessibilityLabel(String(localized: "transactionForm.addSubcategory"))
            .padding(.horizontal, AppSpacing.lg)
        }
    }
}

#Preview {
    @Previewable @State var selectedIds: Set<String> = []
    let coordinator = AppCoordinator()

    return VStack {
        SubcategorySelectorView(
            categoriesViewModel: coordinator.categoriesViewModel,
            categoryId: nil,
            selectedSubcategoryIds: $selectedIds,
            onSearchTap: {},
            onReorderTap: {}
        )
    }
    .padding()
}
