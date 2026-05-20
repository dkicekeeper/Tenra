//
//  HomeBackgroundPicker.swift
//  Tenra
//
//  Apple Wallpaper-style mode picker for the home screen background.
//  Three cards in a horizontal scroll — None / Gradient / Photo.
//  - Labels rendered below cards (always legible, not overlaid on artwork)
//  - Wallpaper card tap opens PhotosPicker directly; photo becomes the thumbnail
//  - Blur applied to wallpaper thumbnail when blurWallpaper is enabled
//

import SwiftUI
import PhotosUI

// MARK: - HomeBackgroundPicker

/// Horizontal card picker for choosing the home screen background mode.
///
/// Design:
/// - Scrollable row of thumbnail cards with labels below (not overlaid)
/// - Selected card gets an accent border + ✓ badge
/// - None/Gradient cards: tap to select
/// - Wallpaper card: tap always opens PhotosPicker; selected photo becomes thumbnail;
///   thumbnail is blurred when `blurWallpaper` is `true`
struct HomeBackgroundPicker: View {

    // MARK: - Props

    let currentMode: HomeBackgroundMode
    /// Thumbnail of the saved wallpaper (nil when none saved yet).
    let wallpaperImage: UIImage?
    /// Mirrors the home screen blur setting so the card preview matches reality.
    let blurWallpaper: Bool
    /// Current opacity for the expense-colour gradient (default used if unset).
    var gradientOpacity: Double = 0.35
    /// Real top-expense weights so the gradient card reflects actual data.
    var gradientWeights: [CategoryColorWeight] = []
    /// Custom categories — needed to resolve orb tints.
    var customCategories: [CustomCategory] = []
    let onModeSelect: (HomeBackgroundMode) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void

    // MARK: - State

    @State private var selectedPhoto: PhotosPickerItem? = nil

    // MARK: - Layout constants

    private let cardHeight: CGFloat = 168   // ~9:16 phone aspect ratio

    // MARK: - Body

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            ForEach(HomeBackgroundMode.allCases, id: \.self) { mode in
                if mode == .wallpaper {
                    // Wallpaper card — tap always opens photo picker
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        modeCard(mode)
                    }
                    .onChange(of: selectedPhoto) { _, newItem in
                        guard newItem != nil else { return }
                        onModeSelect(.wallpaper)
                        Task { await onPhotoChange(newItem) }
                    }
                } else {
                    Button { onModeSelect(mode) } label: {
                        modeCard(mode)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .screenPadding()
        .padding(.vertical, AppSpacing.sm)
        .animation(AppAnimation.gentleSpring, value: currentMode)
    }

    // MARK: - Mode Card

    private func modeCard(_ mode: HomeBackgroundMode) -> some View {
        let isSelected = currentMode == mode

        return HStack(spacing: AppSpacing.md) {
            // Card artwork thumbnail
            ZStack(alignment: .topTrailing) {
                modeArtwork(mode)
                    .frame(width: 80, height: 120)
                    .clipShape(.rect(cornerRadius: AppRadius.lg))

                // Checkmark badge — top-trailing
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: AppIconSize.sm, weight: .semibold))
                        .foregroundStyle(.white)
                        .background(Circle().fill(AppColors.accent).padding(-2))
                        .padding(AppSpacing.xs)
                }
            }

            // Label to the right
            Text(mode.localizedTitle)
                .font(AppTypography.body)
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.textPrimary)

            Spacer()
        }
        .padding(AppSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .fill(Color(.secondarySystemGroupedBackground))
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xl)
                .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 3)
        )
        .animation(AppAnimation.contentSpring, value: isSelected)
        .accessibilityLabel(mode.localizedTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    // MARK: - Gradient Preview Fallback

    /// When real weights aren't available yet (empty tx dataset or cold start),
    /// synthesize a representative palette from the user's custom categories so
    /// the gradient card never renders flat.
    private var effectiveGradientWeights: [CategoryColorWeight] {
        if !gradientWeights.isEmpty { return gradientWeights }
        let names = customCategories.prefix(5).map(\.name)
        guard !names.isEmpty else {
            return [
                CategoryColorWeight(category: "food",          weight: 1.0),
                CategoryColorWeight(category: "transport",     weight: 0.75),
                CategoryColorWeight(category: "entertainment", weight: 0.55),
                CategoryColorWeight(category: "shopping",      weight: 0.40),
                CategoryColorWeight(category: "utilities",     weight: 0.30)
            ]
        }
        let step = 1.0 / Double(names.count)
        return names.enumerated().map { idx, name in
            CategoryColorWeight(category: name, weight: 1.0 - Double(idx) * step)
        }
    }

    // MARK: - Card Artwork

    @ViewBuilder
    private func modeArtwork(_ mode: HomeBackgroundMode) -> some View {
        switch mode {
        case .none:
            // Plain system background — shows what the app looks like without any background
            Rectangle()
                .fill(Color(.systemGroupedBackground))

        case .gradient:
            // Live preview: same CategoryGradientBackground as the home screen,
            // with the user's real expense-colour weights + current opacity.
            // Adapts to light/dark via Color(.systemGroupedBackground) underlay.
            ZStack {
                Color(.systemGroupedBackground)
                CategoryGradientBackground(
                    weights: effectiveGradientWeights,
                    customCategories: customCategories
                )
                .opacity(gradientOpacity)
            }

        case .wallpaper:
            // Photo thumbnail or placeholder; blur only applied to real photos
            if let image = wallpaperImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: blurWallpaper ? 8 : 0, opaque: true)
                    .animation(AppAnimation.gentleSpring, value: blurWallpaper)
            } else {
                Rectangle()
                    .fill(Color(.tertiarySystemGroupedBackground))
                    .overlay(
                        Image(systemName: "photo")
                            .font(AppTypography.h2.weight(.ultraLight))
                            .foregroundStyle(Color(.tertiaryLabel))
                    )
            }
        }
    }
}

// MARK: - HomeBackgroundMode + display helpers

extension HomeBackgroundMode {
    var localizedTitle: String {
        switch self {
        case .none:      return String(localized: "settings.background.none")
        case .gradient:  return String(localized: "settings.background.gradient")
        case .wallpaper: return String(localized: "settings.background.photo")
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var mode: HomeBackgroundMode = .none
        @State private var blur = false

        var body: some View {
            List {
                Section("Background") {
                    HomeBackgroundPicker(
                        currentMode: mode,
                        wallpaperImage: nil,
                        blurWallpaper: blur,
                        onModeSelect: { mode = $0 },
                        onPhotoChange: { _ in }
                    )
                    .listRowInsets(EdgeInsets())
                }
            }
        }
    }
    return PreviewWrapper()
}
