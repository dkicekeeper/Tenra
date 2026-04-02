//
//  UniversalFilterButton.swift
//  AIFinanceManager
//
//  Universal filter button component supporting both Button and Menu modes
//  Phase 14: Consolidates FilterChip, CategoryFilterButton, and AccountFilterMenu
//

import SwiftUI

/// Universal filter button/menu component with consistent styling
/// Supports two modes: simple button tap or menu with custom content
struct UniversalFilterButton<Icon: View, MenuContent: View>: View {
    let title: String
    let isSelected: Bool
    let showChevron: Bool
    let icon: () -> Icon
    let mode: FilterMode<MenuContent>

    enum FilterMode<Content: View> {
        case button(() -> Void)
        case menu(() -> Content)
    }

    // MARK: - Initializers

    /// Button mode initializer - for simple tap actions
    init(
        title: String,
        isSelected: Bool = false,
        showChevron: Bool = true,
        onTap: @escaping () -> Void,
        @ViewBuilder icon: @escaping () -> Icon = { EmptyView() }
    ) where MenuContent == EmptyView {
        self.title = title
        self.isSelected = isSelected
        self.showChevron = showChevron
        self.icon = icon
        self.mode = .button(onTap)
    }

    /// Menu mode initializer - for dropdown menus with custom content
    init(
        title: String,
        isSelected: Bool = false,
        showChevron: Bool = true,
        @ViewBuilder icon: @escaping () -> Icon = { EmptyView() },
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.title = title
        self.isSelected = isSelected
        self.showChevron = showChevron
        self.icon = icon
        self.mode = .menu(menuContent)
    }

    // MARK: - Body Components

    /// Shared label view for both button and menu modes
    @ViewBuilder
    private var label: some View {
        HStack(spacing: AppSpacing.sm) {
            // Optional icon
            if !(Icon.self == EmptyView.self) {
                icon()
                    .font(.system(size: AppIconSize.sm))
            }

            // Title text
            Text(title)

            // Optional chevron
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: AppIconSize.xs))
            }
        }
        .filterChipStyle(isSelected: isSelected)
    }

    var body: some View {
        switch mode {
        case .button(let action):
            // Button mode: simple tap action
            Button(action: action) {
                label
            }
            .contentShape(Rectangle())
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityAddTraits(.isButton)

        case .menu(let content):
            // Menu mode: dropdown with custom content
            Menu {
                content()
            } label: {
                label
            }
            .accessibilityLabel(title)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }
}

// MARK: - Convenience Initializers

extension UniversalFilterButton where Icon == EmptyView {
    /// Text-only button (no icon)
    init(
        title: String,
        isSelected: Bool = false,
        showChevron: Bool = true,
        onTap: @escaping () -> Void
    ) where MenuContent == EmptyView {
        self.init(
            title: title,
            isSelected: isSelected,
            showChevron: showChevron,
            onTap: onTap,
            icon: { EmptyView() }
        )
    }

    /// Text-only menu (no icon)
    init(
        title: String,
        isSelected: Bool = false,
        showChevron: Bool = true,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.init(
            title: title,
            isSelected: isSelected,
            showChevron: showChevron,
            icon: { EmptyView() },
            menuContent: menuContent
        )
    }
}

// MARK: - Previews

#Preview("Filter Buttons") {
    VStack(spacing: AppSpacing.lg) {
        // 1. Simple button with icon
        UniversalFilterButton(
            title: "All Time",
            isSelected: false,
            onTap: {}
        ) {
            Image(systemName: "calendar")
        }

        // 2. Selected button with icon
        UniversalFilterButton(
            title: "This Month",
            isSelected: true,
            onTap: {}
        ) {
            Image(systemName: "calendar")
        }

        // 3. Text-only button
        UniversalFilterButton(
            title: "No Icon",
            isSelected: false,
            onTap: {}
        )

        // 4. Menu with items
        UniversalFilterButton(
            title: "Select Account",
            isSelected: false
        ) {
            Image(systemName: "wallet.pass")
        } menuContent: {
            Button("All Accounts") {}
            Button("Cash") {}
            Button("Card") {}
        }

        // 5. Selected menu
        UniversalFilterButton(
            title: "Cash Account",
            isSelected: true
        ) {
            Image(systemName: "banknote")
        } menuContent: {
            Button("All Accounts") {}
            Button("Cash") {}
            Button("Card") {}
        }
    }
    .padding()
}

#Preview("Account Filter Menu Example") {
    @Previewable @State var selectedAccountId: String? = nil

    let coordinator = AppCoordinator()
    let accounts = [
        Account(name: "Cash", currency: "KZT", iconSource: .sfSymbol("banknote"), initialBalance: 50000),
        Account(name: "Card", currency: "KZT", iconSource: .sfSymbol("creditcard"), initialBalance: 150000)
    ]

    return UniversalFilterButton(
        title: selectedAccountId == nil ? "Все счета" : (accounts.first(where: { $0.id == selectedAccountId })?.name ?? "Все счета"),
        isSelected: selectedAccountId != nil
    ) {
        if let account = accounts.first(where: { $0.id == selectedAccountId }) {
            IconView(source: account.iconSource, size: AppIconSize.sm)
        }
    } menuContent: {
        // "All accounts" option
        Button(action: { selectedAccountId = nil }) {
            HStack {
                Text("Все счета")
                Spacer()
                if selectedAccountId == nil {
                    Image(systemName: "checkmark")
                }
            }
        }

        // Account list
        ForEach(accounts) { account in
            Button(action: { selectedAccountId = account.id }) {
                HStack(spacing: AppSpacing.sm) {
                    IconView(source: account.iconSource, size: AppIconSize.md)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.name)
                            .font(AppTypography.bodySmall)
                        Text(Formatting.formatCurrencySmart(50000, currency: account.currency))
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if selectedAccountId == account.id {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
    }
    .padding()
}
