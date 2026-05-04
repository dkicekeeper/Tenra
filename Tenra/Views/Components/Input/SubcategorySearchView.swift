//
//  SubcategorySearchView.swift
//  Tenra
//
//  Created on 2024
//

import SwiftUI

struct SubcategorySearchView: View {
    let categoriesViewModel: CategoriesViewModel
    let categoryId: String
    @Binding var selectedSubcategoryIds: Set<String>
    @Binding var searchText: String
    @Environment(\.dismiss) var dismiss
    
    // Режим работы: множественный выбор (для транзакций) или одиночный (для привязки к категории)
    let selectionMode: SelectionMode
    let onSingleSelect: ((String) -> Void)?
    
    
    enum SelectionMode {
        case multiple // Множественный выбор для транзакций
        case single // Одиночный выбор для привязки к категории
    }
    
    init(
        categoriesViewModel: CategoriesViewModel,
        categoryId: String,
        selectedSubcategoryIds: Binding<Set<String>>,
        searchText: Binding<String>,
        selectionMode: SelectionMode = .multiple,
        onSingleSelect: ((String) -> Void)? = nil
    ) {
        self.categoriesViewModel = categoriesViewModel
        self.categoryId = categoryId
        self._selectedSubcategoryIds = selectedSubcategoryIds
        self._searchText = searchText
        self.selectionMode = selectionMode
        self.onSingleSelect = onSingleSelect
    }
    
    private var searchResults: [Subcategory] {
        let allSubcategories: [Subcategory]
        if searchText.isEmpty {
            allSubcategories = categoriesViewModel.subcategories
        } else {
            allSubcategories = categoriesViewModel.searchSubcategories(query: searchText)
        }
        
        // В режиме одиночного выбора показываем только непривязанные подкатегории
        if selectionMode == .single {
            let linkedSubcategoryIds = categoriesViewModel.categorySubcategoryLinks
                .filter { $0.categoryId == categoryId }
                .map { $0.subcategoryId }
            return allSubcategories.filter { !linkedSubcategoryIds.contains($0.id) }
        }
        
        return allSubcategories
    }
    
    // Проверяем, можно ли создать новую подкатегорию из текста поиска
    private var canCreateFromSearch: Bool {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmedSearch.isEmpty else { return false }
        
        // Проверяем, что такой подкатегории еще нет
        let searchLower = trimmedSearch.lowercased()
        let exists = categoriesViewModel.subcategories.contains { subcategory in
            subcategory.name.lowercased() == searchLower
        }
        
        return !exists
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if !searchText.isEmpty && searchResults.isEmpty {
                    // Empty state когда поиск не нашел результатов
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: String(localized: "emptyState.searchNoResults"),
                        description: String(localized: "emptyState.tryDifferentSearch")
                    )
                } else {
                    List {
                        ForEach(searchResults) { subcategory in
                            Button {
                                if selectionMode == .single {
                                    // Одиночный выбор - вызываем callback и закрываем
                                    onSingleSelect?(subcategory.id)
                                    dismiss()
                                } else {
                                    // Множественный выбор
                                    if selectedSubcategoryIds.contains(subcategory.id) {
                                        selectedSubcategoryIds.remove(subcategory.id)
                                    } else {
                                        selectedSubcategoryIds.insert(subcategory.id)
                                        // Автоматически привязываем к категории, если еще не привязана
                                        if !categoryId.isEmpty {
                                            categoriesViewModel.linkSubcategoryToCategory(
                                                subcategoryId: subcategory.id,
                                                categoryId: categoryId
                                            )
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(subcategory.name)
                                    Spacer()
                                    if selectionMode == .multiple && selectedSubcategoryIds.contains(subcategory.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(AppColors.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if !categoryId.isEmpty && selectionMode == .multiple {
                                    Button {
                                        categoriesViewModel.unlinkSubcategoryFromCategory(
                                            subcategoryId: subcategory.id,
                                            categoryId: categoryId
                                        )
                                    } label: {
                                        Label(String(localized: "subcategorySearch.unlink"), systemImage: "link.slash")
                                    }
                                    .tint(AppColors.warning)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(selectionMode == .single
                ? String(localized: "subcategorySearch.titleSingle")
                : String(localized: "navigation.subcategorySearch"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: String(localized: "subcategorySearch.searchPrompt"))
            .safeAreaBar(edge: .bottom) {
                // Кнопка создания внизу над полем поиска
                if canCreateFromSearch {
                    let subcategoryName = searchText.trimmingCharacters(in: .whitespaces)
                    Group {
                        if #available(iOS 26, *) {
                            VStack(spacing: 0) { createButton(subcategoryName: subcategoryName) }
                                .glassEffect(.regular)
                        } else {
                            VStack(spacing: 0) { createButton(subcategoryName: subcategoryName) }
                                .background(.ultraThinMaterial)
                        }
                    }
                    .padding(.horizontal, AppSpacing.lg)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
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
                        .glassProminentButton()
                    }
                }
            }
        }
    }

    private func createButton(subcategoryName: String) -> some View {
        Button(action: createSubcategoryFromSearch) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "plus.circle.fill")
                Text(String(format: String(localized: "transactionForm.createSubcategory"), subcategoryName))
                    .font(AppTypography.body)
            }
            .frame(maxWidth: .infinity)
            .padding(AppSpacing.lg)
        }
        .foregroundStyle(.primary)
    }
    
    private func createSubcategoryFromSearch() {
        let trimmedName = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }
        
        let newSubcategory = categoriesViewModel.addSubcategory(name: trimmedName)
        
        // Автоматически привязываем к категории
        if !categoryId.isEmpty {
            categoriesViewModel.linkSubcategoryToCategory(
                subcategoryId: newSubcategory.id,
                categoryId: categoryId
            )
        }
        
        if selectionMode == .single {
            // Одиночный выбор - вызываем callback и закрываем
            onSingleSelect?(newSubcategory.id)
            dismiss()
        } else {
            // Множественный выбор - добавляем в выбранные
            selectedSubcategoryIds.insert(newSubcategory.id)
            // Очищаем поле поиска после создания
            searchText = ""
        }
    }
}

#Preview {
    let coordinator = AppCoordinator()
    SubcategorySearchView(
        categoriesViewModel: coordinator.categoriesViewModel,
        categoryId: "",
        selectedSubcategoryIds: .constant([]),
        searchText: .constant("")
    )
}
