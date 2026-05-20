//
//  BulkDeleteButton.swift
//  Tenra
//

import SwiftUI

struct BulkDeleteButton: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: {
            HapticManager.warning()
            action()
        }) {
            Text(String(format: String(localized: "bulk.deleteCount"), count))
                .font(AppTypography.bodyEmphasis)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.xs)
        }
        .buttonStyle(.glassProminent)
        .tint(AppColors.destructive)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .screenPadding()
        .padding(.bottom, AppSpacing.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
