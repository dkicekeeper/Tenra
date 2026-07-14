//
//  AccentGlow.swift
//  Tenra
//
//  Ambient blurred glow rising from a screen edge — a gradient-filled circle
//  offset mostly off-screen and heavily blurred. Static (no animation loop),
//  hit-testing disabled, hidden from VoiceOver.
//
//  Presets:
//  • `.onboardingAccentGlow()` — full-intensity glow from the bottom edge,
//    the onboarding-screen background.
//  • `.heroAccentGlow(icon:tint:)` — softer glow from the top edge behind
//    entity-detail hero sections. Tint resolves from the hero icon: explicit
//    `IconTint` colour for SF Symbols, dominant logo colour (async, via
//    `DominantColorExtractor`) for `.brandService`, `AppColors.accent`
//    otherwise. The brand colour fades in over the fallback when ready.
//

import SwiftUI

extension View {
    /// Soft tinted glow rising from a screen edge. Sits in `background`,
    /// ignores safe areas, never intercepts touches.
    func accentGlow(
        _ tint: Color,
        edge: VerticalEdge = .bottom,
        intensity: Double = 1
    ) -> some View {
        background {
            AccentGlowBackground(tint: tint, edge: edge, intensity: intensity)
        }
    }

    /// Onboarding background: full-intensity accent glow from the bottom edge.
    func onboardingAccentGlow(tint: Color = AppColors.accent) -> some View {
        accentGlow(tint)
    }

    /// Ambient top glow for entity-detail screens, tinted from the hero icon.
    /// Apply to the screen container (e.g. `EntityDetailScaffold`), passing
    /// the same `icon`/`tint` the `HeroSection` receives.
    func heroAccentGlow(
        icon: IconSource?,
        tint: IconTint? = nil,
        intensity: Double = GlowMetrics.heroIntensity
    ) -> some View {
        modifier(HeroAccentGlowModifier(icon: icon, tint: tint, intensity: intensity))
    }
}

/// Shared glow tunables. Not `AppAnimation` material — the glow is static.
enum GlowMetrics {
    static let blurRadius: CGFloat = 120
    /// Fraction of the circle's own height pushed past the screen edge,
    /// leaving only a soft crown visible.
    static let offScreenFraction: CGFloat = 0.85
    /// Hero glow sits under title/amount text — keep it well below full
    /// intensity so text contrast survives in both themes.
    static let heroIntensity: Double = 1
}

// MARK: - Glow background

private struct AccentGlowBackground: View {
    let tint: Color
    let edge: VerticalEdge
    let intensity: Double

    var body: some View {
        Circle()
            .fill(tint.gradient)
            .visualEffect { [edge] content, proxy in
                let direction: CGFloat = edge == .bottom ? 1 : -1
                return content.offset(y: direction * proxy.size.height * GlowMetrics.offScreenFraction)
            }
            .frame(
                maxHeight: .infinity,
                alignment: edge == .bottom ? .bottom : .top
            )
            .blur(radius: GlowMetrics.blurRadius)
            .opacity(intensity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: - Hero icon tint resolution

private struct HeroAccentGlowModifier: ViewModifier {
    let icon: IconSource?
    let tint: IconTint?
    let intensity: Double

    /// Dominant logo colour, resolved asynchronously for `.brandService`.
    @State private var brandColor: Color?

    private var brandName: String? {
        if case .brandService(let name) = icon { return name }
        return nil
    }

    /// Synchronous tint shown immediately (and kept when no brand colour
    /// can be extracted — e.g. pure black/white logos).
    private var fallbackColor: Color {
        switch tint {
        case .monochrome(let color), .hierarchical(let color):
            return color
        case .palette(let colors) where !colors.isEmpty:
            return colors[0]
        default:
            return AppColors.accent
        }
    }

    func body(content: Content) -> some View {
        content
            .accentGlow(brandColor ?? fallbackColor, edge: .top, intensity: intensity)
            // Keyed on the brand so an icon edit re-resolves (or clears) the
            // colour; same-value re-renders don't re-fire.
            .task(id: brandName) {
                guard let brandName else {
                    brandColor = nil
                    return
                }
                guard let color = await DominantColorExtractor.accentColor(forBrand: brandName) else {
                    brandColor = nil
                    return
                }
                withAnimation(AppAnimation.gentleSpring) {
                    brandColor = color
                }
            }
    }
}

// MARK: - Previews

#Preview("Onboarding — bottom") {
    NavigationStack {
        VStack {
            Text("Sample content")
                .foregroundStyle(AppColors.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onboardingAccentGlow()
    }
}

#Preview("Hero — SF Symbol tint") {
    NavigationStack {
        ScrollView {
            HeroSection(
                icon: .sfSymbol("fork.knife"),
                title: "Food & Drinks",
                iconTint: .monochrome(.orange)
            )
            .padding(.top, 40)
        }
        .heroAccentGlow(icon: .sfSymbol("fork.knife"), tint: .monochrome(.orange))
    }
}

#Preview("Hero — brand logo (dominant color)") {
    NavigationStack {
        ScrollView {
            HeroSection(
                icon: .brandService("kaspi.kz"),
                title: "Kaspi Gold"
            )
            .padding(.top, 40)
        }
        .heroAccentGlow(icon: .brandService("kaspi.kz"))
    }
}
