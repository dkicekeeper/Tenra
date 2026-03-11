//
//  ColorPickerRow.swift
//  AIFinanceManager
//
//  Reusable color picker with preset palette
//  Used for category customization
//

import SwiftUI

/// Color picker row with preset palette and custom color option
/// Shows horizontal scrollable color swatches
struct ColorPickerRow: View {
    @Binding var selectedColorHex: String
    let title: String
    let palette: [String]

    init(
        selectedColorHex: Binding<String>,
        title: String = String(localized: "common.color"),
        palette: [String] = [
            "#3b82f6", "#8b5cf6", "#ec4899", "#f97316", "#eab308",
            "#22c55e", "#14b8a6", "#06b6d4", "#6366f1", "#d946ef",
            "#f43f5e", "#a855f7", "#10b981", "#f59e0b"
        ]
    ) {
        self._selectedColorHex = selectedColorHex
        self.title = title
        self.palette = palette
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Title
            if !title.isEmpty {
                Text(title)
                    .font(AppTypography.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .textCase(.uppercase)
            }

            // Color swatches using UniversalCarousel
            UniversalCarousel(config: .compact) {
                ForEach(palette, id: \.self) { colorHex in
                    ColorSwatch(
                        colorHex: colorHex,
                        isSelected: selectedColorHex == colorHex,
                        onTap: {
                            HapticManager.selection()
                            selectedColorHex = colorHex
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Color Swatch

private struct ColorSwatch: View {
    let colorHex: String
    let isSelected: Bool
    let onTap: () -> Void

    private var color: Color {
        colorFromHex(colorHex)
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)

                if isSelected {
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: AppIconSize.xxl, height: AppIconSize.xxl)

                    Image(systemName: "checkmark")
                        .font(.system(size: AppIconSize.md, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Helper Function

/// Converts hex string to Color
/// Example: "#3b82f6" -> Color(red: 0.23, green: 0.51, blue: 0.96)
private func colorFromHex(_ hex: String) -> Color {
    var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

    var rgb: UInt64 = 0
    Scanner(string: hexSanitized).scanHexInt64(&rgb)

    let r = Double((rgb & 0xFF0000) >> 16) / 255.0
    let g = Double((rgb & 0x00FF00) >> 8) / 255.0
    let b = Double(rgb & 0x0000FF) / 255.0

    return Color(red: r, green: g, blue: b)
}

// MARK: - Previews

#Preview("Default Palette") {
    @Previewable @State var color = "#3b82f6"

    return ColorPickerRow(selectedColorHex: $color)
        .padding()
}

#Preview("Custom Palette") {
    @Previewable @State var color = "#ff0000"

    return ColorPickerRow(
        selectedColorHex: $color,
        title: "Theme Color",
        palette: [
            "#ff0000", "#00ff00", "#0000ff",
            "#ffff00", "#ff00ff", "#00ffff"
        ]
    )
    .padding()
}

#Preview("In Form Context") {
    @Previewable @State var name = ""
    @Previewable @State var color = "#ec4899"

    return ScrollView {
        VStack(spacing: AppSpacing.xxl) {
            FormSection(
                header: "Category Details",
                style: .card
            ) {
                FormTextField(
                    text: $name,
                    placeholder: "Category Name"
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                ColorPickerRow(selectedColorHex: $color)
            }
            .padding(.horizontal, AppSpacing.lg)
        }
        .padding(.vertical)
    }
}

#Preview("With Selected Color") {
    @Previewable @State var color = "#22c55e"

    return VStack(spacing: AppSpacing.lg) {
        // Show selected color
        HStack {
            Text("Selected:")
                .font(AppTypography.bodySmall)
            Circle()
                .fill(colorFromHex(color))
                .frame(width: 30, height: 30)
            Text(color)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
        }

        ColorPickerRow(selectedColorHex: $color)
    }
    .padding()
}

#Preview("All Styles") {
    @Previewable @State var color1 = "#3b82f6"
    @Previewable @State var color2 = "#ec4899"
    @Previewable @State var color3 = "#22c55e"

    return ScrollView {
        VStack(alignment: .leading, spacing: AppSpacing.xxl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("With Title")
                    .font(AppTypography.h4)

                ColorPickerRow(
                    selectedColorHex: $color1,
                    title: "Category Color"
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Without Title")
                    .font(AppTypography.h4)

                ColorPickerRow(
                    selectedColorHex: $color2,
                    title: ""
                )
            }

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("Custom Palette")
                    .font(AppTypography.h4)

                ColorPickerRow(
                    selectedColorHex: $color3,
                    palette: Array(repeating: "#", count: 8).enumerated().map { i, _ in
                        String(format: "#%06x", Int.random(in: 0...0xFFFFFF))
                    }
                )
            }
        }
        .padding()
    }
}
