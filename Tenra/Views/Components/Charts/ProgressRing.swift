//
//  ProgressRing.swift
//  Tenra
//
//  Phase 33.1: Extracted from CategoryChip + CategoryRow to eliminate duplication
//  A circular progress ring that visualises budget consumption.
//

import SwiftUI

// MARK: - ProgressRing

/// Circular arc representing how much of a budget period has been consumed.
///
/// Color model — a "trajectory" AngularGradient over the full circle; the animated
/// trim reveals it, so the arc TIP continuously heats up with the fill level
/// (no threshold snapping):
/// - 0 – 45 %   → solid `AppColors.success` (green — calm zone)
/// - 45 – 80 %  → blend `success` → `warning`
/// - 80 – 100 % → blend `warning` → `destructive` (the red tip appears exactly at the limit)
/// - `isOverBudget` → red-dominant gradient (`warning` start → `destructive`)
///
/// Because the gradient is static and only `trim` animates, the entrance sweep and
/// value changes recolor the tip for free — no color interpolation code.
///
/// The ring starts at the 12-o'clock position (−90° rotation) and sweeps
/// clockwise; the gradient rotates with the arc, so location 0 = trim start.
///
/// **VoiceOver behaviour:**
/// - `accessibilityLabel: nil` (default) — элемент скрыт из дерева VoiceOver.
///   Используй когда родительская строка уже несёт семантику (CategoryRow, CategoryChip).
/// - `accessibilityLabel: "75 % бюджета использовано"` — VoiceOver читает метку.
///   Используй в standalone-контекстах (BudgetDetail, CardsGrid).
///
/// Usage:
/// ```swift
/// // Embedded in row — parent row carries accessibility meaning
/// ProgressRing(
///     progress: budgetProgress.percentage / 100,
///     size: AppIconSize.categoryIcon,
///     lineWidth: 3,
///     isOverBudget: budgetProgress.isOverBudget
/// )
///
/// // Standalone — provide label for VoiceOver
/// ProgressRing(
///     progress: 0.75,
///     size: AppIconSize.budgetRing,
///     lineWidth: 4,
///     isOverBudget: false,
///     accessibilityLabel: String(localized: "75% бюджета использовано")
/// )
/// ```
struct ProgressRing: View {
    /// Normalised progress value (0.0 – 1.0+). Values above 1.0 are clamped at
    /// 1.0 visually but `isOverBudget` still drives the colour choice.
    let progress: Double

    /// Width and height of the circular ring frame.
    var size: CGFloat = AppIconSize.categoryIcon

    /// Stroke line width.
    var lineWidth: CGFloat = 3

    /// Whether spending exceeds the budget limit.
    /// When `true` the arc is rendered in `AppColors.destructive`.
    var isOverBudget: Bool = false

    /// Explicit arc color. When set, it overrides the budget-semantic three-tier
    /// palette entirely — the caller owns the meaning of "fuller". Used by the loan
    /// hero, where a fuller ring means *more debt paid off* and must stay green
    /// regardless of fraction.
    var overrideColor: Color? = nil

    /// Метка для VoiceOver. Когда `nil` — элемент скрыт из accessibility дерева
    /// (ожидается, что родительская View несёт семантику). Когда указана —
    /// VoiceOver читает её и помечает элемент `.updatesFrequently`.
    var accessibilityLabel: String? = nil

    /// Sweep-from-zero entrance. Disable in lazy lists/rows (CategoryRow,
    /// CategoryChip) — `onAppear` re-fires on every row re-materialisation
    /// during scroll.
    var animatesOnAppear: Bool = true

    @State private var displayProgress: Double = 0
    /// Reduce-Motion-aware (nil under Reduce Motion → instant jump, no sweep).
    private var fillAnimation: Animation? { AppAnimation.progressFillAnimation }

    /// Static full-circle gradient — the trimmed arc reveals it, so the tip color
    /// always matches the fill level. Stops are gradient locations = progress
    /// fractions (0.45 / 0.8 / 1.0), NOT tied to the animated display value
    /// (gradient stops aren't animatable; the trim animation does the work).
    private var arcGradient: AngularGradient {
        let stops: [Gradient.Stop]
        if let overrideColor {
            // Caller owns the semantics (loan hero) — keep one hue, add depth.
            stops = [
                .init(color: overrideColor.opacity(0.55), location: 0),
                .init(color: overrideColor, location: 1)
            ]
        } else if isOverBudget || progress > 1.0 {
            // Over the limit — unmistakably red, with a warning-colored tail.
            stops = [
                .init(color: AppColors.warning, location: 0),
                .init(color: AppColors.destructive, location: 1)
            ]
        } else {
            // Trajectory palette: calm green half, heating up toward the limit.
            stops = [
                .init(color: AppColors.success, location: 0),
                .init(color: AppColors.success, location: 0.45),
                .init(color: AppColors.warning, location: 0.8),
                .init(color: AppColors.destructive, location: 1)
            ]
        }
        return AngularGradient(stops: stops, center: .center)
    }

    var body: some View {
        // Round caps protrude half a lineWidth BEYOND the trimmed path ends. An
        // un-inset start cap therefore bleeds counter-clockwise past 12 o'clock
        // and paints green over the red arc tip at ~100% (visible bug). Insetting
        // the trim start by exactly that arc-fraction keeps the start rounded AND
        // makes its cap begin precisely at 12 o'clock.
        let end = min(displayProgress, 1.0)
        let capFraction = (lineWidth / 2) / (.pi * size)
        let arc = Circle()
            .trim(from: min(capFraction, end / 2), to: end)
            .stroke(
                arcGradient,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: size, height: size)
            .animation(AppAnimation.progressFillAnimation, value: isOverBudget)
            .onAppear {
                if animatesOnAppear {
                    withAnimation(fillAnimation) { displayProgress = progress }
                } else {
                    displayProgress = progress
                }
            }
            .onChange(of: progress) { _, newValue in
                withAnimation(fillAnimation) { displayProgress = newValue }
            }

        if let label = accessibilityLabel {
            arc
                .accessibilityLabel(label)
                .accessibilityAddTraits(.updatesFrequently)
        } else {
            arc
                .accessibilityHidden(true) // decorative — the row label carries semantic meaning
        }
    }
}

// MARK: - Preview

#Preview("Budget Progress Ring") {
    HStack(spacing: AppSpacing.xl) {
        // 0 % spent
        VStack(spacing: AppSpacing.xs) {
            ProgressRing(progress: 0, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: false)
            Text("0 %").font(AppTypography.caption).foregroundStyle(.secondary)
        }

        // 50 % spent
        VStack(spacing: AppSpacing.xs) {
            ProgressRing(progress: 0.5, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: false)
            Text("50 %").font(AppTypography.caption).foregroundStyle(.secondary)
        }

        // 100 % spent (exact)
        VStack(spacing: AppSpacing.xs) {
            ProgressRing(progress: 1.0, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: false)
            Text("100 %").font(AppTypography.caption).foregroundStyle(.secondary)
        }

        // Over budget
        VStack(spacing: AppSpacing.xs) {
            ProgressRing(progress: 1.2, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: true)
            Text("120 %").font(AppTypography.caption).foregroundStyle(AppColors.destructive)
        }
    }
    .padding()
}

#Preview("Budget Ring — large (budgetRing)") {
    ProgressRing(
        progress: 0.73,
        size: AppIconSize.budgetRing,
        lineWidth: 4,
        isOverBudget: false
    )
    .padding()
}
