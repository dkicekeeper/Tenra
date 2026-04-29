//
//  BudgetProgressCircle.swift
//  Tenra
//
//  Phase 33.1: Extracted from CategoryChip + CategoryRow to eliminate duplication
//  A circular progress ring that visualises budget consumption.
//

import SwiftUI

// MARK: - BudgetProgressCircle

/// Circular arc representing how much of a budget period has been consumed.
///
/// Three-tier color palette:
/// - Progress < 80 %                       → `AppColors.success` (green)
/// - 80 % ≤ Progress ≤ 100 %, not over     → `AppColors.warning` (orange) — early warning
/// - Over budget OR Progress > 100 %        → `AppColors.destructive` (red)
///
/// The early-warning band catches the user *before* they breach the limit, instead
/// of jumping from "everything fine" green directly to red on overspend.
///
/// The ring starts at the 12-o'clock position (−90° rotation) and sweeps
/// clockwise.
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
/// BudgetProgressCircle(
///     progress: budgetProgress.percentage / 100,
///     size: AppIconSize.categoryIcon,
///     lineWidth: 3,
///     isOverBudget: budgetProgress.isOverBudget
/// )
///
/// // Standalone — provide label for VoiceOver
/// BudgetProgressCircle(
///     progress: 0.75,
///     size: AppIconSize.budgetRing,
///     lineWidth: 4,
///     isOverBudget: false,
///     accessibilityLabel: String(localized: "75% бюджета использовано")
/// )
/// ```
struct BudgetProgressCircle: View {
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

    /// Метка для VoiceOver. Когда `nil` — элемент скрыт из accessibility дерева
    /// (ожидается, что родительская View несёт семантику). Когда указана —
    /// VoiceOver читает её и помечает элемент `.updatesFrequently`.
    var accessibilityLabel: String? = nil

    /// Threshold (0.0–1.0) at which the arc switches from `success` green to
    /// `warning` orange as an early-warning band before over-budget.
    private static let warningThreshold: Double = 0.8

    private var arcColor: Color {
        if isOverBudget || progress > 1.0 {
            return AppColors.destructive
        }
        if progress >= Self.warningThreshold {
            return AppColors.warning
        }
        return AppColors.success
    }

    var body: some View {
        let arc = Circle()
            .trim(from: 0, to: min(progress, 1.0))
            .stroke(
                arcColor,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .frame(width: size, height: size)
            .animation(.easeInOut(duration: AppAnimation.standard), value: progress)
            .animation(.easeInOut(duration: AppAnimation.standard), value: arcColor)

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
            BudgetProgressCircle(progress: 0, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: false)
            Text("0 %").font(AppTypography.caption).foregroundStyle(.secondary)
        }

        // 50 % spent
        VStack(spacing: AppSpacing.xs) {
            BudgetProgressCircle(progress: 0.5, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: false)
            Text("50 %").font(AppTypography.caption).foregroundStyle(.secondary)
        }

        // 100 % spent (exact)
        VStack(spacing: AppSpacing.xs) {
            BudgetProgressCircle(progress: 1.0, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: false)
            Text("100 %").font(AppTypography.caption).foregroundStyle(.secondary)
        }

        // Over budget
        VStack(spacing: AppSpacing.xs) {
            BudgetProgressCircle(progress: 1.2, size: AppIconSize.categoryIcon, lineWidth: 3, isOverBudget: true)
            Text("120 %").font(AppTypography.caption).foregroundStyle(AppColors.destructive)
        }
    }
    .padding()
}

#Preview("Budget Ring — large (budgetRing)") {
    BudgetProgressCircle(
        progress: 0.73,
        size: AppIconSize.budgetRing,
        lineWidth: 4,
        isOverBudget: false
    )
    .padding()
}
