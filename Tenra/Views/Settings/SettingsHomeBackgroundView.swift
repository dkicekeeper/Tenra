//
//  SettingsHomeBackgroundView.swift
//  Tenra
//
//  The home screen's background: DesignKit's option carousel (HomeBackgroundPicker), the
//  chosen background large over the row of options, and under it that option's settings: the
//  intensity of the expense colours, or a photo to pick, its blur and a way to remove it.
//

import SwiftUI
import PhotosUI

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

    @State private var selectedPhoto: PhotosPickerItem?

    // MARK: - Body

    var body: some View {
        ScrollView {
            HomeBackgroundPicker(
                currentMode: currentMode,
                wallpaperImage: wallpaperImage,
                blurWallpaper: blurWallpaper,
                gradientOpacity: backgroundOpacity,
                gradientWeights: categoryWeights,
                customCategories: customCategories,
                onModeSelect: onModeSelect
            ) { mode in
                settings(for: mode)
                    .screenPadding()
            }
            .padding(.vertical, AppSpacing.lg)
        }
        .navigationTitle(String(localized: "settings.background"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            onModeSelect(.wallpaper)
            Task { await onPhotoChange(item) }
        }
    }

    // MARK: - Settings

    @ViewBuilder
    private func settings(for mode: HomeBackgroundMode) -> some View {
        switch mode {
        case .none:
            EmptyView()
        case .gradient:
            FormSection(header: String(localized: "settings.background.opacityTitle", defaultValue: "Expense colour")) {
                OpacitySliderRow(value: backgroundOpacity, onChange: onOpacityChange)
            }
        case .wallpaper:
            FormSection {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    UniversalRow(
                        config: .settings,
                        leadingIcon: .sfSymbol("photo.on.rectangle", color: AppColors.accent, size: AppIconSize.md)
                    ) {
                        Text(wallpaperImage == nil
                             ? String(localized: "settings.background.choosePhoto")
                             : String(localized: "settings.background.changePhoto"))
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.Text.primary)
                    } trailing: {
                        DisclosureChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if wallpaperImage != nil {
                    Divider()
                    ToggleSettingsRow(
                        icon: "camera.filters",
                        title: String(localized: "settings.background.blurWallpaper"),
                        isOn: Binding(
                            get: { blurWallpaper },
                            set: { onBlurChange($0) }
                        )
                    )
                    Divider()
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
        }
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
