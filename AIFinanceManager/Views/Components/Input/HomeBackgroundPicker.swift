//
//  HomeBackgroundPicker.swift
//  AIFinanceManager
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
    let onModeSelect: (HomeBackgroundMode) -> Void
    let onPhotoChange: (PhotosPickerItem?) async -> Void

    // MARK: - State

    @State private var selectedPhoto: PhotosPickerItem? = nil

    // MARK: - Layout constants

    private let cardWidth: CGFloat  = 100
    private let cardHeight: CGFloat = 168   // ~9:16 phone aspect ratio

    // MARK: - Body

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: AppSpacing.md) {
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
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
        }
        .animation(AppAnimation.gentleSpring, value: currentMode)
    }

    // MARK: - Mode Card

    private func modeCard(_ mode: HomeBackgroundMode) -> some View {
        let isSelected = currentMode == mode

        return VStack(spacing: AppSpacing.xs) {
            // Card artwork + selection chrome
            ZStack(alignment: .topTrailing) {
                modeArtwork(mode)
                    .frame(width: cardWidth, height: cardHeight)
                    .clipShape(.rect(cornerRadius: AppRadius.xl))

                // Checkmark badge — top-trailing
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: AppIconSize.md, weight: .semibold))
                        .foregroundStyle(.white)
                        .background(Circle().fill(AppColors.accent).padding(-2))
                        .padding(AppSpacing.sm)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .stroke(isSelected ? AppColors.accent : Color.clear, lineWidth: 3)
            )
            .animation(AppAnimation.contentSpring, value: isSelected)

            // Label below the card — always readable
            Text(mode.localizedTitle)
                .font(AppTypography.caption)
                .foregroundStyle(isSelected ? AppColors.accent : AppColors.textSecondary)
                .frame(width: cardWidth)
                .multilineTextAlignment(.center)
                .animation(AppAnimation.contentSpring, value: isSelected)
        }
        .accessibilityLabel(mode.localizedTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
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
            // Static preview using the same palette as the live gradient
            GeometryReader { geo in
                ZStack {
                    Rectangle().fill(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.05, blue: 0.12),
                                     Color(red: 0.08, green: 0.05, blue: 0.18)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // Orb 1 — blue/indigo
                    Ellipse()
                        .fill(Color(red: 0.231, green: 0.510, blue: 0.965).opacity(0.65))
                        .frame(width: geo.size.width * 0.9, height: geo.size.height * 0.5)
                        .offset(x: -geo.size.width * 0.15, y: -geo.size.height * 0.20)
                        .blur(radius: 22)
                    // Orb 2 — purple
                    Ellipse()
                        .fill(Color(red: 0.545, green: 0.361, blue: 0.965).opacity(0.55))
                        .frame(width: geo.size.width * 0.75, height: geo.size.height * 0.45)
                        .offset(x: geo.size.width * 0.20, y: -geo.size.height * 0.05)
                        .blur(radius: 20)
                    // Orb 3 — pink
                    Ellipse()
                        .fill(Color(red: 0.925, green: 0.255, blue: 0.600).opacity(0.50))
                        .frame(width: geo.size.width * 0.85, height: geo.size.height * 0.4)
                        .offset(x: geo.size.width * 0.05, y: geo.size.height * 0.25)
                        .blur(radius: 22)
                }
            }

        case .wallpaper:
            // Photo thumbnail or placeholder; blurred when blur mode is on
            Group {
                if let image = wallpaperImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            Image(systemName: "photo")
                                .font(.system(size: 40, weight: .ultraLight))
                                .foregroundStyle(Color(.tertiaryLabel))
                        )
                }
            }
            // opaque: true prevents transparent blur edges within the card bounds
            .blur(radius: blurWallpaper ? 8 : 0, opaque: true)
            .animation(AppAnimation.gentleSpring, value: blurWallpaper)
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
