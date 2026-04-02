//
//  InfoRow.swift
//  AIFinanceManager
//
//  Reusable info row component (label: value)
//  Migrated to UniversalRow architecture - 2026-02-16
//

import SwiftUI

/// Info row component for displaying label + value pairs
/// Now built on top of UniversalRow for consistency
struct InfoRow: View {
    let icon: String?
    let label: String
    let value: String

    init(icon: String? = nil, label: String, value: String) {
        self.icon = icon
        self.label = label
        self.value = value
    }

    var body: some View {
        UniversalRow(
            config: .info,
            leadingIcon: icon.map { .sfSymbol($0, color: AppColors.textSecondary, size: AppIconSize.md) }
        ) {
            HStack {
                Text(label)
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(value)
                    .font(AppTypography.bodyEmphasis)
            }
        } trailing: {
            EmptyView()
        }
    }
}

#Preview {
    VStack() {
        InfoRow(icon: "tag.fill", label: "Категория", value: "Food")
        InfoRow(icon: "calendar", label: "Частота", value: "Ежемесячно")
        InfoRow(icon: "clock.fill", label: "Следующее списание", value: "15 января 2026")
        InfoRow(label: "Без иконки", value: "Значение")
    }
    .padding()
}
