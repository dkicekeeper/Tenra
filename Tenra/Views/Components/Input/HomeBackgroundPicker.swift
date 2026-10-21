//
//  HomeBackgroundPicker.swift
//  Tenra
//
//  The home screen's background: DesignKit's `OptionCardPicker` (a carousel of large previews
//  since 6.0.0). The three backgrounds (none, the expense colours, a photo) each in a phone's
//  shape, the centred one the choice, the neighbours peeking at the sides; under the carousel
//  what the screen sets for the chosen one (`settings`). The previews are live: the gradient in
//  the person's expense colours at the chosen intensity, the photo saved, blurred when the home
//  blurs it.
//

import SwiftUI

// MARK: - HomeBackgroundPicker

/// The background picker. The mode follows the carousel, except for a photo, which needs one
/// picked first: until then the carousel shows it with its settings ("Choose a Photo") and the
/// home keeps its background.
struct HomeBackgroundPicker<Settings: View>: View {

    // MARK: - Props

    let currentMode: HomeBackgroundMode
    /// Thumbnail of the saved wallpaper (nil when none saved yet).
    let wallpaperImage: UIImage?
    /// Mirrors the home screen blur setting so the card preview matches reality.
    let blurWallpaper: Bool
    /// Current opacity for the expense-colour gradient.
    let gradientOpacity: Double
    /// Real top-expense weights so the gradient card reflects actual data.
    let gradientWeights: [CategoryColorWeight]
    /// Custom categories — needed to resolve orb tints.
    let customCategories: [CustomCategory]
    let onModeSelect: (HomeBackgroundMode) -> Void
    let settings: (HomeBackgroundMode) -> Settings

    /// The option in the carousel's middle.
    @State private var shown: HomeBackgroundMode

    init(
        currentMode: HomeBackgroundMode,
        wallpaperImage: UIImage?,
        blurWallpaper: Bool,
        gradientOpacity: Double = 0.35,
        gradientWeights: [CategoryColorWeight] = [],
        customCategories: [CustomCategory] = [],
        onModeSelect: @escaping (HomeBackgroundMode) -> Void,
        @ViewBuilder settings: @escaping (HomeBackgroundMode) -> Settings
    ) {
        self.currentMode = currentMode
        self.wallpaperImage = wallpaperImage
        self.blurWallpaper = blurWallpaper
        self.gradientOpacity = gradientOpacity
        self.gradientWeights = gradientWeights
        self.customCategories = customCategories
        self.onModeSelect = onModeSelect
        self.settings = settings
        _shown = State(initialValue: currentMode)
    }

    // MARK: - Body

    var body: some View {
        OptionCardPicker(
            HomeBackgroundMode.allCases,
            selection: Binding(
                get: { shown },
                set: { mode in
                    shown = mode
                    if mode != .wallpaper || wallpaperImage != nil { onModeSelect(mode) }
                }
            ),
            title: { $0.localizedTitle }
        ) { mode in
            modeArtwork(mode)
        } settings: { mode in
            settings(mode)
        }
        // A photo picked, or the mode changed elsewhere.
        .onChange(of: currentMode) { _, mode in shown = mode }
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
                .fill(AppColors.Background.baseAlt)

        case .gradient:
            // Live preview: same CategoryGradientBackground as the home screen,
            // with the user's real expense-colour weights + current opacity.
            // Adapts to light/dark via Color(.systemGroupedBackground) underlay.
            ZStack {
                AppColors.Background.baseAlt
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
                    .fill(AppColors.Background.neutral1)
                    .overlay(
                        Icon("photo", size: AppIconSize.xl)
                            .fontWeight(.ultraLight)
                            .foregroundStyle(AppColors.Text.tertiary)
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

        var body: some View {
            ScrollView {
                HomeBackgroundPicker(
                    currentMode: mode,
                    wallpaperImage: nil,
                    blurWallpaper: false,
                    onModeSelect: { mode = $0 }
                ) { _ in
                    EmptyView()
                }
            }
        }
    }
    return PreviewWrapper()
}
