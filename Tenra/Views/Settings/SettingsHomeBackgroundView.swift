//
//  SettingsHomeBackgroundView.swift
//  Tenra
//
//  Dedicated page for home screen background settings.
//  Hero live preview + mode picker + per-mode controls (blur / opacity).
//

import SwiftUI
import PhotosUI

/// Full-page background settings:
///   • Hero preview — mirrors what the home screen will look like (adapts L/D)
///   • Mode picker — none / gradient / photo
///   • Opacity slider for the "expense colour" gradient (when mode == .gradient)
///   • Blur toggle + remove photo (when mode == .wallpaper)
struct SettingsHomeBackgroundView: View {

    // MARK: - Props

    let currentMode: HomeBackgroundMode
    let wallpaperImage: UIImage?
    let blurWallpaper: Bool
    let backgroundOpacity: Double
    /// Top-expense weights, used by the gradient preview. Empty ⇒ demo fallback palette.
    let categoryWeights: [CategoryColorWeight]
    /// Custom categories — needed to resolve tints for the orbs.
    let customCategories: [CustomCategory]
    let onModeSelect: (HomeBackgroundMode) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onWallpaperRemove: () async -> Void
    let onBlurChange: (Bool) -> Void
    let onOpacityChange: (Double) -> Void

    // MARK: - Body

    var body: some View {
        List {
            // Mode picker — cards themselves act as live previews (gradient uses
            // the real category colours + current opacity; wallpaper uses the
            // saved photo with blur). No separate hero preview.
            Section {
                HomeBackgroundPicker(
                    currentMode: currentMode,
                    wallpaperImage: wallpaperImage,
                    blurWallpaper: blurWallpaper,
                    gradientOpacity: backgroundOpacity,
                    gradientWeights: categoryWeights,
                    customCategories: customCategories,
                    onModeSelect: onModeSelect,
                    onPhotoChange: onPhotoChange
                )
                .listRowInsets(EdgeInsets(top: AppSpacing.sm,
                                          leading: 0,
                                          bottom: AppSpacing.sm,
                                          trailing: 0))
            }

            // Gradient-specific control: opacity of the expense colour layer
            if currentMode == .gradient {
                Section(header: SectionHeader(String(localized: "settings.background.opacityTitle",
                                  defaultValue: "Expense colour"), style: .list)) {
                    OpacitySliderRow(
                        value: backgroundOpacity,
                        onChange: onOpacityChange
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Wallpaper-specific controls
            if currentMode == .wallpaper {
                Section {
                    ToggleSettingsRow(
                        icon: "camera.filters",
                        title: String(localized: "settings.background.blurWallpaper"),
                        isOn: Binding(
                            get: { blurWallpaper },
                            set: { onBlurChange($0) }
                        )
                    )

                    if wallpaperImage != nil {
                        UniversalRow(
                            config: .settings,
                            leadingIcon: .sfSymbol("trash", color: AppColors.destructive, size: AppIconSize.md)
                        ) {
                            Text(String(localized: "settings.background.removePhoto"))
                                .font(AppTypography.body)
                                .foregroundStyle(AppColors.destructive)
                        } trailing: {
                            EmptyView()
                        }
                        .actionRow(role: .destructive) {
                            Task { await onWallpaperRemove() }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .navigationTitle(String(localized: "settings.background"))
        .navigationBarTitleDisplayMode(.inline)
        .animation(AppAnimation.gentleSpring, value: currentMode)
    }
}

// MARK: - Opacity Slider Row

/// The expense colour's intensity: DesignKit's `SliderRow` over the stored opacity.
private struct OpacitySliderRow: View {
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        SliderRow(
            String(localized: "settings.background.opacity", defaultValue: "Colour intensity"),
            systemImage: "circle.lefthalf.filled",
            value: Binding(
                get: { value },
                set: { onChange($0) }
            ),
            in: 0.05...1.0,
            valueText: "\(Int((value * 100).rounded()))%"
        )
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var mode: HomeBackgroundMode = .gradient
        @State private var blur = false
        @State private var opacity: Double = 0.35

        var body: some View {
            NavigationStack {
                SettingsHomeBackgroundView(
                    currentMode: mode,
                    wallpaperImage: nil,
                    blurWallpaper: blur,
                    backgroundOpacity: opacity,
                    categoryWeights: [],
                    customCategories: [],
                    onModeSelect: { mode = $0 },
                    onPhotoChange: { _ in },
                    onWallpaperRemove: {},
                    onBlurChange: { blur = $0 },
                    onOpacityChange: { opacity = $0 }
                )
            }
        }
    }
    return PreviewWrapper()
}
