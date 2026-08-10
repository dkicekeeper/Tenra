//
//  ImportSourcePicker.swift
//  Tenra
//
//  Two entry points for the Import tab: a PDF statement, or a paper receipt.
//  Built on UniversalRow (icon + title + hint + trailing chevron, wrapped in
//  `.actionRow`) rather than hand-rolling another icon/title/subtitle HStack
//  (see docs/design-system.md — "Don't hand-roll card/row shells").
//

import SwiftUI

struct ImportSourcePicker: View {
    let onPickPDF: () -> Void
    let onScanReceipt: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            sourceRow(
                icon: "doc.text.viewfinder",
                title: String(localized: "import.source.statement.title"),
                subtitle: String(localized: "import.source.statement.subtitle"),
                action: onPickPDF
            )

            sourceRow(
                icon: "camera.viewfinder",
                title: String(localized: "import.source.receipt.title"),
                subtitle: String(localized: "import.source.receipt.subtitle"),
                action: onScanReceipt
            )
        }
        .padding(.horizontal, AppSpacing.lg)
    }

    private func sourceRow(
        icon: String,
        title: String,
        subtitle: String,
        action: @escaping () -> Void
    ) -> some View {
        UniversalRow(
            config: .standard,
            leadingIcon: .custom(
                source: .sfSymbol(icon),
                style: .circle(size: AppIconSize.xxl,
                               tint: .monochrome(AppColors.accent),
                               backgroundColor: AppColors.accent.opacity(0.15))
            ),
            hint: subtitle,
            title: title
        ) {
            Image(systemName: "chevron.right")
                .font(.system(size: AppIconSize.sm, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .cardStyle()
        .actionRow {
            HapticManager.light()
            action()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
    }
}

#Preview {
    ImportSourcePicker(onPickPDF: {}, onScanReceipt: {})
}
