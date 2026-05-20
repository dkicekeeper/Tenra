//
//  AppModifiers.swift
//  Tenra
//
//  SwiftUI view modifiers for consistent styling across the app.
//

import SwiftUI

// MARK: - Card & Row Styles

extension View {
    /// Interactive filter chip — uses Liquid Glass on iOS 26+; falls back to tinted `secondaryBackground`.
    ///
    /// The `isSelected` state adds an `accent` tint on both platforms.
    ///
    /// **Use when:** the chip triggers filtering, navigation, or any tap action
    /// (filter buttons, action menu triggers, segmented-style selectors in toolbars).
    @ViewBuilder
    func filterChipStyle(isSelected: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self
                .font(AppTypography.bodySmall.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .clipShape(.rect(cornerRadius: AppRadius.xl))
                .glassEffect(
                    isSelected
                    ? .regular.tint(AppColors.accent.opacity(0.2)).interactive()
                    : .regular.interactive()
                )
                .animation(AppAnimation.contentSpring, value: isSelected)
        } else {
            self
                .font(AppTypography.bodySmall.weight(.medium))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.sm)
                .background(
                    isSelected
                    ? AppColors.accent.opacity(0.2)
                    : AppColors.bgMuted,
                    in: RoundedRectangle(cornerRadius: AppRadius.xl)
                )
                .animation(AppAnimation.contentSpring, value: isSelected)
        }
    }

    /// Применяет glass effect с стандартным cornerRadius для карточек (iOS 26+).
    /// Padding НЕ добавляется — ответственность за отступы лежит на содержимом
    /// (строки используют собственный padding; произвольный контент добавляет .padding перед вызовом).
    ///
    /// **Use this for display cards** (AccountCard, LoanCard, HealthScoreCard, hero
    /// sections, etc.). For interactive form sections that contain `Picker(.menu)` /
    /// `Menu` triggers, use `formCardStyle()` instead — `glassEffect` is the morph
    /// source for iOS 26 menus, and a single-row section collapses the whole row into
    /// the popover at tap.
    @ViewBuilder
    func cardStyle(radius: CGFloat = AppRadius.xl) -> some View {
        if #available(iOS 26, *) {
            self
                .contentShape(Rectangle())
                .clipShape(.rect(cornerRadius: radius))
                .glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else {
            self
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: radius)
                )
        }
    }

    /// Card chrome for form-like containers that host interactive controls
    /// (`Picker(.menu)`, `Menu`, etc.). Uses `.ultraThinMaterial` on every iOS
    /// version instead of `.glassEffect` because iOS 26's Liquid Glass surface
    /// becomes the morph-source for any native menu trigger inside it — in a
    /// single-row `FormSection` the glass-rect ≈ row bounds and the entire row
    /// collapses into the popover at tap.
    ///
    /// **Use this for `FormSection`, `BudgetSettingsSection`, and any other
    /// container that wraps rows users tap to open menus.** Use `cardStyle()`
    /// (above) for non-interactive display cards.
    func formCardStyle(radius: CGFloat = AppRadius.xl) -> some View {
        self
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: radius)
            )
    }
}

// MARK: - Layout Helpers

extension View {
    /// Стандартный horizontal padding для экранов
    func screenPadding() -> some View {
        self.padding(.horizontal, AppSpacing.lg)
    }

    /// Визуально приглушает view для будущих / запланированных транзакций.
    /// Применяй вместо inline `opacity(0.5)` чтобы значение было единым по всему проекту.
    func futureTransactionStyle(isFuture: Bool) -> some View {
        self.opacity(isFuture ? 0.55 : 1.0)
    }

    /// Card padding (внутренний padding карточек) — 16pt, канон для контента карточек (см. design-system §10)
    func cardContentPadding() -> some View {
        self.padding(AppSpacing.lg)
    }
}

// MARK: - Inline Field Styles (deprecated — use FormTextField with .inline style)

extension View {
    /// Deprecated. Use `FormTextField(style: .inline)`.
    /// The new component renders a tinted capsule chip with focus state +
    /// 1pt accent border so an editable field is distinguishable from a static
    /// label in every state.
    @available(*, deprecated, message: "Use FormTextField(style: .inline) — it gives the field a visible chip background and focus state.")
    func inlineFieldStyle(
        keyboard: UIKeyboardType = .default,
        maxWidth: CGFloat? = nil
    ) -> some View {
        self
            .font(AppTypography.body)
            .multilineTextAlignment(.trailing)
            .keyboardType(keyboard)
            .frame(maxWidth: maxWidth ?? .infinity)
    }

    /// Deprecated. Use `FormTextField(style: .inlineMultiline(min:max:))`.
    @available(*, deprecated, message: "Use FormTextField(style: .inlineMultiline(min:max:)) — wraps the multi-line field in a tinted rounded container with focus state.")
    func inlineNoteStyle() -> some View {
        self
            .lineLimit(1...4)
            .multilineTextAlignment(.trailing)
            .font(AppTypography.body)
    }
}

// MARK: - Staggered Entrance Modifier

/// Animates a view's entrance with scale + opacity, typically used for facepile icons.
/// Triggers once on first appearance. Respects Reduce Motion accessibility setting.
///
/// ```swift
/// IconView(source: account.iconSource, style: iconStyle)
///     .staggeredEntrance(delay: Double(index) * AppAnimation.facepileStagger)
/// ```
struct StaggeredEntranceModifier: ViewModifier {
    let delay: Double

    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1 : AppAnimation.facepileHiddenScale)
            .opacity(appeared ? 1 : 0)
            .animation(
                AppAnimation.isReduceMotionEnabled
                    ? .linear(duration: 0)
                    : AppAnimation.facepileSpring.delay(delay),
                value: appeared
            )
            .task { appeared = true }
    }
}

extension View {
    /// Animates entrance with scale + opacity spring, with optional stagger delay.
    /// - Parameter delay: Delay before animation starts (use `Double(index) * AppAnimation.facepileStagger` for facepiles).
    func staggeredEntrance(delay: Double = 0) -> some View {
        modifier(StaggeredEntranceModifier(delay: delay))
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
