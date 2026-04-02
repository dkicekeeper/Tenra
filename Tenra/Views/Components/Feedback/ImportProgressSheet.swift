//
//  ImportProgressSheet.swift
//  AIFinanceManager
//
//  Created on 2026-02-04
//  Settings Refactoring Phase 3 - UI Components
//

import SwiftUI

/// Props-based import progress sheet for Settings
/// Single Responsibility: Display import progress with cancellation
struct ImportProgressSheet: View {
    // MARK: - Props

    let currentRow: Int
    let totalRows: Int
    let progress: Double
    let onCancel: () -> Void

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Text(String(localized: "progress.importing"))
                .font(AppTypography.h4)
                .foregroundStyle(AppColors.textPrimary)

            VStack(spacing: AppSpacing.sm) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(AppColors.accent)
                    .scaleEffect(y: 2.0)

                HStack {
                    Text("\(currentRow) / \(totalRows)")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Text("\(Int(progress * 100))%")
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)
                        .fontWeight(.semibold)
                }
            }

            Button(String(localized: "button.cancel")) {
                onCancel()
            }
            .buttonStyle(.bordered)
            .tint(AppColors.destructive)
        }
        .padding(AppSpacing.xxl)
        .interactiveDismissDisabled()
    }
}

// MARK: - Preview

#Preview {
    ImportProgressSheet(
        currentRow: 42,
        totalRows: 100,
        progress: 0.42,
        onCancel: {
        }
    )
}
