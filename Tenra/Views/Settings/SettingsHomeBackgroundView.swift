//
//  SettingsHomeBackgroundView.swift
//  Tenra
//
//  Dedicated page for home screen background settings.
//  Mode cards (with inline photo picking for wallpaper) + blur toggle.
//

import SwiftUI
import PhotosUI

/// Full-page background settings: mode cards + blur toggle.
///
/// Photo selection is handled directly by the wallpaper card in `HomeBackgroundPicker` —
/// no separate "select photo" row is shown here.
struct SettingsHomeBackgroundView: View {

    // MARK: - Props

    let currentMode: HomeBackgroundMode
    let wallpaperImage: UIImage?
    let blurWallpaper: Bool
    let onModeSelect: (HomeBackgroundMode) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void
    let onWallpaperRemove: () async -> Void
    let onBlurChange: (Bool) -> Void

    // MARK: - Body

    var body: some View {
        List {
            // Mode cards — wallpaper card opens photo picker on tap
            Section {
                HomeBackgroundPicker(
                    currentMode: currentMode,
                    wallpaperImage: wallpaperImage,
                    blurWallpaper: blurWallpaper,
                    onModeSelect: onModeSelect,
                    onPhotoChange: onPhotoChange
                )
                .listRowInsets(EdgeInsets(top: AppSpacing.sm,
                                          leading: 0,
                                          bottom: AppSpacing.sm,
                                          trailing: 0))
            }

            // Wallpaper-specific controls — visible only when wallpaper mode is active
            if currentMode == .wallpaper {
                Section {
                    // Blur toggle
                    Toggle(isOn: Binding(
                        get: { blurWallpaper },
                        set: { onBlurChange($0) }
                    )) {
                        Label(
                            String(localized: "settings.background.blurWallpaper"),
                            systemImage: "camera.filters"
                        )
                    }

                    // Remove — only shown when a photo is saved
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

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var mode: HomeBackgroundMode = .wallpaper
        @State private var blur = false

        var body: some View {
            NavigationStack {
                SettingsHomeBackgroundView(
                    currentMode: mode,
                    wallpaperImage: nil,
                    blurWallpaper: blur,
                    onModeSelect: { mode = $0 },
                    onPhotoChange: { _ in },
                    onWallpaperRemove: {},
                    onBlurChange: { blur = $0 }
                )
            }
        }
    }
    return PreviewWrapper()
}
