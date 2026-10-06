//
//  CategoryRow.swift
//  Tenra
//
//  Category row of the categories list. Adapter over DesignKit's `ProgressRingRow`: the
//  category, its budget, the tap, the swipe-to-delete, the over-budget haptic and the
//  VoiceOver label stay here.
//

import SwiftUI

struct CategoryRow: View, Equatable {
    let category: CustomCategory
    let isDefault: Bool
    let budgetProgress: BudgetProgress?
    let currency: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    /// Optional zoom-transition source. When both id and namespace are non-nil,
    /// the icon (with budget ring) becomes the matched source for
    /// `.navigationTransition(.zoom(...))` on the destination detail view.
    var transitionSourceID: String? = nil
    var transitionNamespace: Namespace.ID? = nil

    /// Equatable conformance compares the rendering-affecting inputs only —
    /// closures are intentionally ignored (their captured state changes don't
    /// alter the rendered output). With `.equatable()` applied at the call site,
    /// SwiftUI can skip body re-evals when neither the category nor its budget
    /// progress changed.
    static func == (lhs: CategoryRow, rhs: CategoryRow) -> Bool {
        lhs.category == rhs.category
            && lhs.isDefault == rhs.isDefault
            && lhs.budgetProgress == rhs.budgetProgress
            && lhs.currency == rhs.currency
            && lhs.transitionSourceID == rhs.transitionSourceID
    }

    private var categoryAccessibilityLabel: String {
        var parts = [category.name]
        if let progress = budgetProgress {
            parts.append(String(format: String(localized: "accessibility.category.budgetProgress"), Int(progress.percentage)))
            if progress.isOverBudget {
                parts.append(String(localized: "accessibility.category.overBudget"))
            }
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: onEdit) {
            ProgressRingRow(
                iconSource: category.iconSource,
                color: category.color,
                title: category.name,
                progress: budgetProgress.map { LimitProgress($0) },
                currency: currency,
                placeholder: category.type == .expense ? String(localized: "category.noBudgetSet") : nil,
                transitionSourceID: transitionSourceID,
                transitionNamespace: transitionNamespace
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(categoryAccessibilityLabel)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isDefault {
                Button(role: .destructive) {
                    HapticManager.warning()
                    onDelete()
                } label: {
                    Label(String(localized: "button.delete"), systemImage: "trash")
                }
            }
        }
        // Budget overflow haptic — fires when spending first crosses 100 %
        .onChange(of: budgetProgress?.isOverBudget) { _, isOver in
            if isOver == true { HapticManager.warning() }
        }
    }
}

#Preview {
    let sampleCategory = CustomCategory(
        id: "test",
        name: "Food",
        iconSource: .sfSymbol("fork.knife"),
        colorHex: "#3b82f6",
        type: .expense
    )

    List {
        CategoryRow(
            category: sampleCategory,
            isDefault: false,
            budgetProgress: nil,
            currency: "KZT",
            onEdit: {},
            onDelete: {}
        )
        .padding(.vertical, AppSpacing.xs)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowSeparator(.hidden)
    }
    .listStyle(PlainListStyle())
}
