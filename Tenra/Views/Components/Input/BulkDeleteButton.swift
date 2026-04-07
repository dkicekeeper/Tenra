//
//  BulkDeleteButton.swift
//  Tenra
//

import SwiftUI

struct BulkDeleteButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticManager.warning()
            action()
        }) {
            Text(String(format: String(localized: "bulk.deleteCount"), count))
                .font(AppTypography.bodyEmphasis)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.md)
                .background(AppColors.destructive, in: RoundedRectangle(cornerRadius: AppRadius.md))
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
