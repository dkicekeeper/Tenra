//
//  UniversalRow.swift
//  AIFinanceManager
//
//  Universal row component with IconView integration and Design System compliance
//  Created: 2026-02-16
//
//  Architecture:
//  - Generic ViewBuilders for content and trailing elements
//  - IconView integration for leading icons
//  - Presets for common use cases (settings, selectable, info)
//  - Modifiers for interactive behavior (navigation, action, selectable)
//
//  Usage Examples:
//
//  1. Settings Action Row:
//  ```swift
//  UniversalRow(
//      config: .settings,
//      leadingIcon: .sfSymbol("trash", color: .red)
//  ) {
//      Text("Delete All")
//  } trailing: {
//      EmptyView()
//  }
//  .actionRow(role: .destructive) { deleteAll() }
//  ```
//
//  2. Navigation Row:
//  ```swift
//  UniversalRow(
//      config: .settings,
//      leadingIcon: .sfSymbol("tag")
//  ) {
//      Text("Categories")
//  } trailing: {
//      EmptyView() // NavigationLink adds chevron automatically
//  }
//  .navigationRow { CategoriesView() }
//  ```
//
//  3. Selectable Row:
//  ```swift
//  UniversalRow(
//      config: .selectable,
//      leadingIcon: .brandService("kaspi.kz")
//  ) {
//      Text("Kaspi Bank")
//  } trailing: {
//      if isSelected {
//          Image(systemName: "checkmark")
//      }
//  }
//  .selectableRow(isSelected: isSelected) { select() }
//  ```
//

import SwiftUI

// MARK: - Universal Row Component

/// Universal row component for consistent UI patterns across the app
/// Integrates with IconView for leading icons and supports flexible content
struct UniversalRow<Content: View, Trailing: View>: View {

    // MARK: - Properties

    let config: RowConfiguration
    let leadingIcon: IconConfig?

    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing

    // MARK: - Initializer

    init(
        config: RowConfiguration = .standard,
        leadingIcon: IconConfig? = nil,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.config = config
        self.leadingIcon = leadingIcon
        self.content = content
        self.trailing = trailing
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: config.spacing) {
            // Leading icon через IconView
            if let iconConfig = leadingIcon {
                IconView(
                    source: iconConfig.source,
                    style: iconConfig.style
                )
            }

            // Content expands to fill available space, pushing trailing to the right edge.
            // Using frame(maxWidth:) instead of a Spacer avoids competing spacers when
            // content itself contains an inner Spacer (e.g. infoRow HStack).
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing element
            trailing()
        }
        .padding(.vertical, config.verticalPadding)
        .padding(.horizontal, config.horizontalPadding)
        .background(config.backgroundColor)
        .clipShape(.rect(cornerRadius: config.cornerRadius))
    }
}

// MARK: - Icon Configuration

/// Configuration for leading icon in UniversalRow
/// Wraps IconSource and IconStyle for convenient usage
struct IconConfig {
    let source: IconSource?
    let style: IconStyle

    // MARK: - Convenience Initializers

    /// SF Symbol with color
    /// - Parameters:
    ///   - name: SF Symbol name
    ///   - color: Tint color (default: textPrimary)
    ///   - size: Icon size (default: AppIconSize.md)
    static func sfSymbol(
        _ name: String,
        color: Color = AppColors.textPrimary,
        size: CGFloat = AppIconSize.md
    ) -> IconConfig {
        IconConfig(
            source: .sfSymbol(name),
            style: .circle(size: size, tint: .monochrome(color))
        )
    }

    /// Brand service logo
    /// - Parameters:
    ///   - brandName: Service name (e.g., "netflix")
    ///   - size: Icon size (default: AppIconSize.xl)
    static func brandService(
        _ brandName: String,
        size: CGFloat = AppIconSize.xl
    ) -> IconConfig {
        IconConfig(
            source: .brandService(brandName),
            style: .serviceLogo(size: size)
        )
    }

    /// Custom IconSource with IconStyle
    /// - Parameters:
    ///   - source: IconSource
    ///   - style: IconStyle
    static func custom(source: IconSource?, style: IconStyle) -> IconConfig {
        IconConfig(source: source, style: style)
    }

    /// Auto-select style based on source type
    /// Mirrors IconView convenience init: sfSymbol→categoryIcon, brandService→serviceLogo
    /// - Parameters:
    ///   - source: IconSource
    ///   - size: Icon size (default: AppIconSize.xl)
    static func auto(source: IconSource, size: CGFloat = AppIconSize.xl) -> IconConfig {
        switch source {
        case .sfSymbol:
            return IconConfig(source: source, style: .categoryIcon(size: size))
        case .brandService:
            return IconConfig(source: source, style: .serviceLogo(size: size))
        }
    }
}

// MARK: - Row Configuration

/// Configuration for UniversalRow layout and styling
struct RowConfiguration {
    let spacing: CGFloat
    let verticalPadding: CGFloat
    let horizontalPadding: CGFloat
    let backgroundColor: Color
    let cornerRadius: CGFloat

    // MARK: - Presets

    /// Standard form row (default)
    /// V: 12pt / H: 16pt — rows own their padding; cardStyle() adds no padding.
    /// Used for: MenuPickerRow, DatePickerRow, InfoRow, BudgetSettingsSection rows.
    static let standard = RowConfiguration(
        spacing: AppSpacing.md,
        verticalPadding: AppSpacing.md,
        horizontalPadding: AppSpacing.lg,
        backgroundColor: .clear,
        cornerRadius: 0
    )

    /// Settings row style
    /// Used for ActionSettingsRow, NavigationSettingsRow
    /// No horizontal padding (managed by List)
    static let settings = RowConfiguration(
        spacing: AppSpacing.md,
        verticalPadding: AppSpacing.xs,
        horizontalPadding: 0,
        backgroundColor: .clear,
        cornerRadius: 0
    )

    /// Selectable row — for single-select lists (checkmark pattern).
    /// V: 12pt / H: 16pt — same rhythm as .standard; semantic distinction only.
    /// Use `.selectableRow(isSelected:action:)` modifier on top.
    /// Used for: TimeFilterView selectable rows
    static let selectable = RowConfiguration(
        spacing: AppSpacing.md,
        verticalPadding: AppSpacing.md,
        horizontalPadding: AppSpacing.lg,
        backgroundColor: .clear,
        cornerRadius: 0
    )

    /// Sheet / form-list row — wider horizontal inset for modal selection sheets.
    /// V: 12pt / H: 16pt — gives breathing room in full-width sheet lists.
    /// Used for: modal selection sheets with wider horizontal inset
    static let sheetList = RowConfiguration(
        spacing: AppSpacing.md,
        verticalPadding: AppSpacing.md,
        horizontalPadding: AppSpacing.lg,
        backgroundColor: .clear,
        cornerRadius: 0
    )

    /// Info row style — display-only component, always inside a padded container.
    /// V: 8pt / H: 0 — container (detail card VStack with .padding(.lg)) owns horizontal spacing.
    /// Used for InfoRow (read-only label + value) inside LoanDetailView, DepositDetailView, etc.
    static let info = RowConfiguration(
        spacing: AppSpacing.md,
        verticalPadding: AppSpacing.sm,
        horizontalPadding: 0,
        backgroundColor: .clear,
        cornerRadius: 0
    )

    /// Card row style — available for standalone rows outside FormSection context.
    /// Currently unused in production.
    static let card = RowConfiguration(
        spacing: AppSpacing.md,
        verticalPadding: AppSpacing.lg,
        horizontalPadding: AppSpacing.lg,
        backgroundColor: AppColors.surface,
        cornerRadius: AppRadius.xl
    )
}

// MARK: - Row Modifiers

extension View {
    /// Applies navigation row behavior
    /// Wraps the row in NavigationLink
    /// - Parameter destination: Destination view
    func navigationRow<Destination: View>(
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            self
        }
    }

    /// Applies action row behavior
    /// Wraps the row in Button
    /// - Parameters:
    ///   - role: Button role (e.g., .destructive)
    ///   - action: Action to perform
    func actionRow(
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            self
        }
    }

    /// Applies selectable row behavior
    /// Makes row tappable with contentShape
    /// - Parameters:
    ///   - isSelected: Whether the row is selected
    ///   - action: Action to perform on tap
    func selectableRow(
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}

// MARK: - Convenience Initializers

extension UniversalRow where Trailing == EmptyView {
    /// Initializer without trailing element
    init(
        config: RowConfiguration = .standard,
        leadingIcon: IconConfig? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.config = config
        self.leadingIcon = leadingIcon
        self.content = content
        self.trailing = { EmptyView() }
    }
}

extension UniversalRow where Content == Text, Trailing == EmptyView {
    /// Initializer with text content and no trailing
    /// Useful for simple labeled rows
    init(
        config: RowConfiguration = .standard,
        leadingIcon: IconConfig? = nil,
        title: String,
        titleColor: Color = AppColors.textPrimary
    ) {
        self.config = config
        self.leadingIcon = leadingIcon
        self.content = {
            Text(title)
                .font(AppTypography.body)
                .foregroundStyle(titleColor)
        }
        self.trailing = { EmptyView() }
    }
}

// Note: Removed overly-specific convenience initializer for navigation rows
// Use the standard UniversalRow initializer with explicit trailing view instead

// MARK: - Previews

#Preview("Basic Rows") {
    List {
        // Standard row with icon
        UniversalRow(
            config: .standard,
            leadingIcon: .sfSymbol("star.fill", color: .yellow)
        ) {
            Text("Standard Row")
        } trailing: {
            EmptyView()
        }

        // Row with trailing text
        UniversalRow(
            config: .standard,
            leadingIcon: .sfSymbol("calendar")
        ) {
            Text("Date")
                .foregroundStyle(AppColors.textSecondary)
        } trailing: {
            Text("Today")
        }

        // Row without icon
        UniversalRow(config: .standard) {
            Text("No Icon Row")
        } trailing: {
            Text("Value")
        }
    }
    .listStyle(.plain)
}

#Preview("Settings Rows") {
    NavigationStack {
        List {
            Section("Navigation") {
                // NavigationLink автоматически добавляет chevron, не нужно явно указывать
                UniversalRow(
                    config: .settings,
                    leadingIcon: .sfSymbol("tag", color: AppColors.accent)
                ) {
                    Text("Categories")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                } trailing: {
                    EmptyView()
                }
                .navigationRow {
                    Text("Categories View")
                }

                UniversalRow(
                    config: .settings,
                    leadingIcon: .sfSymbol("creditcard", color: AppColors.accent)
                ) {
                    Text("Accounts")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                } trailing: {
                    EmptyView()
                }
                .navigationRow {
                    Text("Accounts View")
                }
            }

            Section("Actions") {
                UniversalRow(
                    config: .settings,
                    leadingIcon: .sfSymbol("square.and.arrow.up", color: AppColors.accent)
                ) {
                    Text("Export Data")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                } trailing: {
                    EmptyView()
                }
                .actionRow {
                }

                UniversalRow(
                    config: .settings,
                    leadingIcon: .sfSymbol("trash", color: AppColors.destructive)
                ) {
                    Text("Delete All")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.destructive)
                } trailing: {
                    EmptyView()
                }
                .actionRow(role: .destructive) {
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview("Selectable Rows") {
    @Previewable @State var selectedBank: String? = "kaspi.kz"
    let banks = [("kaspi.kz", "Kaspi"), ("halykbank.kz", "Halyk Bank"), ("jusan.kz", "Jusan Bank"), ("homecredit.kz", "Home Credit")]

    List {
        ForEach(banks, id: \.0) { domain, name in
            UniversalRow(
                config: .selectable,
                leadingIcon: .brandService(domain)
            ) {
                Text(name)
                    .foregroundStyle(AppColors.textPrimary)
            } trailing: {
                if selectedBank == domain {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppColors.accent)
                }
            }
            .selectableRow(isSelected: selectedBank == domain) {
                HapticManager.selection()
                selectedBank = domain
            }
        }
    }
    .listStyle(.plain)
}

#Preview("Info Rows") {
    List {
        UniversalRow(
            config: .info,
            leadingIcon: .sfSymbol("tag.fill", color: AppColors.textSecondary, size: AppIconSize.md)
        ) {
            HStack {
                Text("Category")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Food")
                    .font(AppTypography.bodyEmphasis)
            }
        } trailing: {
            EmptyView()
        }

        UniversalRow(
            config: .info,
            leadingIcon: .sfSymbol("calendar", color: AppColors.textSecondary, size: AppIconSize.md)
        ) {
            HStack {
                Text("Frequency")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Monthly")
                    .font(AppTypography.bodyEmphasis)
            }
        } trailing: {
            EmptyView()
        }

        UniversalRow(config: .info) {
            HStack {
                Text("No Icon")
                    .font(AppTypography.bodyEmphasis)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Value")
                    .font(AppTypography.bodyEmphasis)
            }
        } trailing: {
            EmptyView()
        }
    }
    .listStyle(.plain)
}

#Preview("Card Rows") {
    VStack(spacing: AppSpacing.lg) {
        UniversalRow(
            config: .card,
            leadingIcon: .sfSymbol("star.fill", color: .yellow, size: AppIconSize.lg)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Premium Feature")
                    .font(AppTypography.h4)
                Text("Unlock advanced analytics")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        } trailing: {
            Image(systemName: "chevron.right")
                .foregroundStyle(AppColors.textSecondary)
        }
        .actionRow {
        }

        UniversalRow(
            config: .card,
            leadingIcon: .brandService("netflix", size: AppIconSize.avatar)
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("Netflix")
                    .font(AppTypography.h4)
                Text("Subscription")
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(.secondary)
            }
        } trailing: {
            Text("$9.99")
                .font(AppTypography.bodyEmphasis)
                .fontWeight(.semibold)
        }
    }
    .padding()
}

#Preview("Sheet List Rows") {
    @Previewable @State var selectedItem: String? = "Kaspi Gold"

    NavigationStack {
        ScrollView {
            VStack(spacing: 0) {
                // "All" option (no icon, like TimeFilterView)
                UniversalRow(config: .sheetList) {
                    Text("All Accounts")
                        .fontWeight(.medium)
                } trailing: {
                    if selectedItem == nil {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .selectableRow(isSelected: selectedItem == nil) {
                    selectedItem = nil
                }

                Divider()
                    .padding(.leading, AppSpacing.lg)

                // Row with icon + subtitle (like AccountFilterView)
                UniversalRow(
                    config: .sheetList,
                    leadingIcon: .sfSymbol("creditcard.fill", color: AppColors.accent, size: AppIconSize.lg)
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kaspi Gold")
                            .font(AppTypography.bodySmall)
                        Text("125 400 KZT")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                } trailing: {
                    if selectedItem == "Kaspi Gold" {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .selectableRow(isSelected: selectedItem == "Kaspi Gold") {
                    selectedItem = "Kaspi Gold"
                }

                Divider()
                    .padding(.leading, AppSpacing.lg)

                // Row with icon, text only (like CategoryFilterView)
                UniversalRow(
                    config: .sheetList,
                    leadingIcon: .sfSymbol("cart.fill", color: AppColors.accent, size: AppIconSize.lg)
                ) {
                    Text("Shopping")
                } trailing: {
                    if selectedItem == "Shopping" {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .selectableRow(isSelected: selectedItem == "Shopping") {
                    selectedItem = "Shopping"
                }

                Divider()
                    .padding(.leading, AppSpacing.lg)

                // Text-only row (like TimeFilterView presets)
                UniversalRow(config: .sheetList) {
                    Text("This Month")
                } trailing: {
                    if selectedItem == "This Month" {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppColors.accent)
                    }
                }
                .selectableRow(isSelected: selectedItem == "This Month") {
                    selectedItem = "This Month"
                }
            }
        }
        .navigationTitle("Sheet List")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Convenience Initializers") {
    List {
        Section("Simple Text Row") {
            UniversalRow(
                leadingIcon: .sfSymbol("bell"),
                title: "Notifications"
            )

            UniversalRow(
                leadingIcon: .sfSymbol("lock"),
                title: "Privacy"
            )
        }

        Section("Navigation Row") {
            UniversalRow(
                leadingIcon: .sfSymbol("gear"),
                title: "Settings"
            )
            .navigationRow {
                Text("Settings View")
            }
        }
    }
}

#Preview("Icon Variations") {
    List {
        UniversalRow(
            leadingIcon: .sfSymbol("heart.fill", color: .red, size: AppIconSize.lg)
        ) {
            Text("SF Symbol")
        } trailing: {
            EmptyView()
        }

        UniversalRow(
            leadingIcon: .brandService("kaspi.kz", size: AppIconSize.xl)
        ) {
            Text("Bank Logo")
        } trailing: {
            EmptyView()
        }

        UniversalRow(
            leadingIcon: .brandService("spotify", size: AppIconSize.avatar)
        ) {
            Text("Brand Service")
        } trailing: {
            EmptyView()
        }

        UniversalRow(
            leadingIcon: .custom(
                source: .sfSymbol("star"),
                style: .circle(
                    size: AppIconSize.xl,
                    tint: .hierarchical(.purple),
                    backgroundColor: .purple.opacity(0.2)
                )
            )
        ) {
            Text("Custom Style")
        } trailing: {
            EmptyView()
        }
    }
    .listStyle(.plain)
}
