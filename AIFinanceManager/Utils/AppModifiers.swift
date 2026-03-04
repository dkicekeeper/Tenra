//
//  AppModifiers.swift
//  AIFinanceManager
//
//  SwiftUI view modifiers for consistent styling across the app.
//

import SwiftUI

// MARK: - Card & Row Styles

extension View {
    /// Применяет стандартный стиль карточки
    func cardStyle(radius: CGFloat = AppRadius.pill, padding: CGFloat = AppSpacing.md) -> some View {
        self
//            .padding(padding)
            .background(AppColors.cardBackground)
            .clipShape(.rect(cornerRadius: radius))
    }

    /// Применяет стандартный стиль для list row
    func rowStyle() -> some View {
        self
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
    }

    /// Static display chip — non-interactive label/tag.
    ///
    /// Background: `secondaryBackground` fill (no glass effect). The chip is visually inert —
    /// it does **not** receive hover/press treatment and has no `.interactive()` glass modifier.
    ///
    /// **Use when:** showing read-only tags, category badges, info labels, inline chips that
    /// do not trigger any action on tap.
    ///
    /// **Do NOT use for:** tappable filter controls or action triggers — use `filterChipStyle` instead.
    ///
    /// Current call sites: `CategoryChip`, general-purpose info tags.
    func chipStyle(isSelected: Bool = false) -> some View {
        self
            .font(AppTypography.label)
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .background(isSelected ? AppColors.accent.opacity(0.2) : AppColors.secondaryBackground)
            .clipShape(.rect(cornerRadius: AppRadius.pill))
    }

    /// Interactive filter chip — uses Liquid Glass on iOS 26+; falls back to tinted `secondaryBackground`.
    ///
    /// Unlike `chipStyle`, this modifier applies `.interactive()` to the glass effect so the chip
    /// responds correctly to hover/press. The `isSelected` state adds an `accent` tint on both platforms.
    ///
    /// **Use when:** the chip triggers filtering, navigation, or any tap action
    /// (filter buttons, action menu triggers, segmented-style selectors in toolbars).
    ///
    /// **Do NOT use for:** static read-only tags with no tap behavior — use `chipStyle` instead.
    ///
    /// Current call sites: `FilterChip`, `AccountFilterMenu`, `CategoryFilterButton`, `UniversalFilterButton`.
    @ViewBuilder
    func filterChipStyle(isSelected: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .clipShape(.rect(cornerRadius: AppRadius.pill))
                .glassEffect(
                    isSelected
                    ? .regular.tint(AppColors.accent.opacity(0.2)).interactive()
                    : .regular.interactive()
                )
        } else {
            self
                .font(AppTypography.label)
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    isSelected
                    ? AppColors.accent.opacity(0.2)
                    : AppColors.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: AppRadius.pill)
                )
        }
    }

    /// Применяет тень
    func shadowStyle(_ shadow: Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    /// Применяет glass effect с стандартным cornerRadius для карточек (iOS 26+)
    @ViewBuilder
    func glassCardStyle(radius: CGFloat = AppRadius.pill) -> some View {
        if #available(iOS 26, *) {
            self
                .padding(AppSpacing.lg)
                .contentShape(Rectangle())
                .clipShape(.rect(cornerRadius: radius))
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .padding(AppSpacing.lg)
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius)
                )
        }
    }

    /// Применяет glass/material background без clipShape поверх контента.
    /// Используется для карточек с встроенными Swift Charts — clipShape обрезает Metal-слои Charts.
    @ViewBuilder
    func cardBackground(radius: CGFloat = AppRadius.pill) -> some View {
        if #available(iOS 26, *) {
            // ⚠️ Намеренно НЕ применяем clipShape — он обрезает Swift Charts слои.
            self
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius)
                )
                .clipShape(.rect(cornerRadius: radius))
        }
    }

    /// Стиль для fallback иконок (используется в BrandLogoView, SubscriptionCard)
    func fallbackIconStyle(size: CGFloat) -> some View {
        self
            .font(.system(size: size * 0.6))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

// MARK: - Layout Helpers

extension View {
    /// Стандартный horizontal padding для экранов
    func screenPadding() -> some View {
        self.padding(.horizontal, AppSpacing.pageHorizontal)
    }

    /// Визуально приглушает view для будущих / запланированных транзакций.
    /// Применяй вместо inline `opacity(0.5)` чтобы значение было единым по всему проекту.
    func futureTransactionStyle(isFuture: Bool) -> some View {
        self.opacity(isFuture ? 0.55 : 1.0)
    }

    /// Стандартный vertical spacing для sections
    func sectionSpacing() -> some View {
        self.padding(.vertical, AppSpacing.sectionVertical)
    }

    /// Card padding (внутренний padding карточек)
    func cardContentPadding() -> some View {
        self.padding(AppSpacing.cardPadding)
    }

    /// List row padding (padding для строк списка)
    func listRowPadding() -> some View {
        self.padding(.horizontal, AppSpacing.pageHorizontal)
            .padding(.vertical, AppSpacing.listRowSpacing)
    }
}

// MARK: - Chart Appear Modifier

/// Animates a chart's entrance: fades in + scales up from the bottom edge.
///
/// Apply to any chart container view. Triggers once on first appearance.
/// Respects the user's Reduce Motion accessibility setting.
///
/// ```swift
/// SpendingTrendChart(dataPoints: points, currency: "KZT")
///     .chartAppear()
/// ```
struct ChartAppearModifier: ViewModifier {
    @State private var appeared = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : AppAnimation.chartHiddenScale, anchor: .bottom)
            .onAppear {
                withAnimation(
                    AppAnimation.chartAppearAnimation
                        .delay(AppAnimation.chartAppearDelay + delay)
                ) {
                    appeared = true
                }
            }
    }
}

extension View {
    /// Animates chart entrance with opacity + scale spring from the bottom.
    /// - Parameter delay: Extra delay before animation starts (use to stagger multiple charts).
    func chartAppear(delay: Double = 0) -> some View {
        modifier(ChartAppearModifier(delay: delay))
    }
}

// MARK: - Transaction Row Styles

/// Варианты стилизации строк транзакций
enum TransactionRowVariant {
    /// Стандартный стиль с фоном
    case standard
    /// Прозрачный фон
    case transparent
    /// Карточный стиль с тенью
    case card
}

extension View {
    /// Стилизует view как строку транзакции
    func transactionRowStyle(
        isPlanned: Bool = false,
        variant: TransactionRowVariant = .standard
    ) -> some View {
        self
            .padding(AppSpacing.sm)
            .background(backgroundForVariant(isPlanned: isPlanned, variant: variant))
            .clipShape(.rect(cornerRadius: AppRadius.sm))
    }

    private func backgroundForVariant(isPlanned: Bool, variant: TransactionRowVariant) -> Color {
        if isPlanned { return AppColors.planned.opacity(0.1) }
        switch variant {
        case .standard:   return AppColors.secondaryBackground
        case .transparent: return .clear
        case .card:       return AppColors.surface
        }
    }

    /// Liquid Glass стиль для карточек транзакций (iOS 26+)
    @ViewBuilder
    func glassTransactionRowStyle(
        isPlanned: Bool = false,
        radius: CGFloat = AppRadius.sm
    ) -> some View {
        if #available(iOS 26, *) {
            self
                .padding(.vertical, AppSpacing.sm)
                .clipShape(.rect(cornerRadius: radius))
                .glassEffect(
                    isPlanned
                        ? .regular.tint(AppColors.planned.opacity(0.12))
                        : .regular,
                    in: .rect(cornerRadius: radius)
                )
        } else {
            self
                .padding(.vertical, AppSpacing.sm)
                .background(
                    isPlanned ? AppColors.planned.opacity(0.1) : AppColors.secondaryBackground,
                    in: RoundedRectangle(cornerRadius: radius)
                )
        }
    }
}
