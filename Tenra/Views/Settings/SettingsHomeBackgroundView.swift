//
//  SettingsHomeBackgroundView.swift
//  Tenra
//
//  The home screen's background: DesignKit's option carousel (HomeBackgroundPicker), each
//  background a large preview, and under it the chosen one's settings in DesignKit's form rows
//  (docs/migration-6.0.md in DesignKit): the intensity of the expense colours, or a photo to
//  pick, its blur and a way to remove it.
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
        // The grouped background: the settings are FormSection cards. "None" previews this
        // colour, the home's plain one; the preview's hairline keeps its shape.
        .background(AppColors.Background.baseAlt)
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
            // DesignKit's rows in a FormSection card (`.standard`, inset dividers); the photo
            // picker's label is a UniversalRow in the accent.
            FormSection {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    UniversalRow(
                        wallpaperImage == nil
                            ? String(localized: "settings.background.choosePhoto")
                            : String(localized: "settings.background.changePhoto"),
                        icon: "photo.on.rectangle",
                        titleColor: AppColors.accent
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if wallpaperImage != nil {
                    Divider().padding(.leading, AppSpacing.lg)
                    UniversalRow(
                        String(localized: "settings.background.blurWallpaper"),
                        icon: "camera.filters",
                        accessory: .toggle(Binding(
                            get: { blurWallpaper },
                            set: { onBlurChange($0) }
                        ))
                    )
                    Divider().padding(.leading, AppSpacing.lg)
                    UniversalRow(
                        String(localized: "settings.background.removePhoto"),
                        icon: "trash",
                        role: .destructive,
                        accessory: .action { Task { await onWallpaperRemove() } }
                    )
                }
            }
        }
    }
}

// MARK: - Opacity Slider Row

/// The expense colour's intensity: DesignKit's slider row over the stored opacity.
private struct OpacitySliderRow: View {
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        UniversalRow(
            String(localized: "settings.background.opacity", defaultValue: "Colour intensity"),
            icon: "circle.lefthalf.filled",
            accessory: .slider(Binding(
                get: { value },
                set: { onChange($0) }
            ), in: 0.05...1.0, valueText: "\(Int((value * 100).rounded()))%")
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
