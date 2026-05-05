//
//  AppAnimation.swift
//  Tenra
//
//  Animation tokens and interactive button style.
//

import SwiftUI

// MARK: - Animation Durations

/// Консистентные длительности анимаций
enum AppAnimation {
    // MARK: - Basic Durations

    /// Быстрая анимация (button press, selection)
    static let fast: Double = 0.1

    /// Стандартная анимация (transitions, state changes)
    static let standard: Double = 0.25

    /// Медленная анимация (modals, large transitions)
    static let slow: Double = 0.35

    /// Spring animation для bounce эффекта (iOS 16+ style)
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)

    /// Snappy content spring — for content transitions (amount inputs, list changes, toggles).
    /// response 0.3 + damping 0.7 = quick settle with minimal overshoot.
    static let contentSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Gentle spring — for smooth value animations (amount display, error messages, state changes).
    /// response 0.4 + damping 0.8 = soft deceleration, no visible overshoot.
    static let gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Hero spring — for hero icon entrance animations (slower, dramatic settle).
    /// response 0.6 + damping 0.7 = visible overshoot with smooth settle.
    static let heroSpring = Animation.spring(response: 0.6, dampingFraction: 0.7)

    /// Progress bar spring — for animated bar width changes.
    /// response 0.55 + damping 0.72 = smooth bar expansion with slight bounce.
    static let progressBarSpring = Animation.spring(response: 0.55, dampingFraction: 0.72)

    /// Facepile entrance spring — for staggered icon pop-in animations.
    /// response 0.4 + damping 0.7 = visible pop with smooth settle.
    static let facepileSpring = Animation.spring(response: 0.4, dampingFraction: 0.7)

    /// Starting scale for facepile icon entrance (grows from this to 1.0).
    static let facepileHiddenScale: CGFloat = 0.5

    /// Delay increment per facepile icon (each icon delays by `index * facepileStagger`).
    static let facepileStagger: Double = 0.06

    /// Breathing animation for packed circle idle state.
    /// 3% scale oscillation, Reduce Motion-aware.
    static let breathingScale: CGFloat = 1.03

    /// Base duration for breathing cycle (each circle offsets by +0.4s per index).
    static let breathingBaseDuration: Double = 3.0

    /// Per-index duration offset for desynchronized breathing.
    static let breathingStagger: Double = 0.4

    /// Reduce-Motion-aware breathing animation factory.
    static func breathingAnimation(index: Int) -> Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: breathingBaseDuration + Double(index) * breathingStagger)
                .repeatForever(autoreverses: true)
    }

    // MARK: - Gradient Background Orbs

    /// Breathing scale range for gradient orbs — weight=1.0 → 1.15, weight=0.4 → 1.05.
    static func orbBreathScale(weight: CGFloat) -> CGFloat {
        1.0 + (0.05 + weight * 0.10)
    }

    /// Breathing duration for gradient orbs — weight=1.0 → 4s, weight=0.4 → 7s.
    /// Heavier categories breathe faster (more visual prominence).
    static func orbBreathDuration(weight: CGFloat) -> Double {
        7.0 - weight * 3.0
    }

    /// Drift radius for gradient orbs. Back layer drifts less than front layer.
    static func orbDriftRadius(isBackLayer: Bool) -> CGFloat {
        isBackLayer ? 15 : 25
    }

    /// Drift duration per orb — randomised per index to prevent synchronisation.
    /// Base 8s + index offset creates lava lamp desynchronisation.
    static func orbDriftDuration(index: Int) -> Double {
        8.0 + Double(index) * 1.2
    }

    /// Opacity for gradient orbs — weight=1.0 → 0.45, weight=0.4 → 0.25.
    static func orbOpacity(weight: CGFloat) -> Double {
        0.25 + Double(weight) * 0.20
    }

    /// Blur radius per layer. Back layer = deeper blur (farther), front = sharper (closer).
    /// Reduced from 60/35 to 44/28: the original radii were eating GPU during scroll
    /// without adding visual softness — at this size the perceptual difference is small
    /// but the blur convolution cost scales with radius squared.
    static func orbBlur(isBackLayer: Bool) -> CGFloat {
        isBackLayer ? 44 : 28
    }

    /// Reduce-Motion-aware orb breathing animation factory.
    static func orbBreathAnimation(weight: CGFloat) -> Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: orbBreathDuration(weight: weight))
                .repeatForever(autoreverses: true)
    }

    /// Reduce-Motion-aware orb drift animation factory.
    static func orbDriftAnimation(index: Int) -> Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: orbDriftDuration(index: index))
                .repeatForever(autoreverses: true)
    }

    /// Content reveal animation — for staggered section fade-in during initialization.
    static let contentRevealAnimation = Animation.easeOut(duration: 0.35)

    // MARK: - MessageBanner

    /// Banner entrance spring response
    static let bannerEntranceResponse: Double = 0.6

    /// Banner entrance spring damping fraction
    static let bannerEntranceDamping: Double = 0.7

    /// Icon bounce spring response
    static let bannerIconResponse: Double = 0.5

    /// Icon bounce spring damping fraction
    static let bannerIconDamping: Double = 0.6

    /// Icon bounce animation delay (after banner entrance)
    static let bannerIconDelay: Double = 0.1

    /// Banner scale when hidden (entrance starts from this value)
    static let bannerHiddenScale: CGFloat = 0.85

    /// Banner Y-offset when hidden (slides in from above)
    static let bannerHiddenOffset: CGFloat = -20

    // MARK: - Chart Animations

    /// Spring response for chart appearance (marks entering the viewport).
    static let chartAppearResponse: Double = 0.55

    /// Damping fraction for chart appearance spring.
    static let chartAppearDamping: Double = 0.82

    /// Spring response for chart data update (marks repositioning when data changes).
    static let chartUpdateResponse: Double = 0.5

    /// Damping fraction for chart data update spring.
    static let chartUpdateDamping: Double = 0.85

    /// Delay before chart appearance animation starts (lets layout settle).
    static let chartAppearDelay: Double = 0.05

    /// Starting scale for chart appearance (grows from this to 1.0, anchored at bottom).
    static let chartHiddenScale: CGFloat = 0.94

    /// Reduce-Motion-aware spring for chart appearance.
    static var chartAppearAnimation: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: chartAppearResponse, dampingFraction: chartAppearDamping)
    }

    /// Reduce-Motion-aware spring for chart data updates.
    static var chartUpdateAnimation: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: chartUpdateResponse, dampingFraction: chartUpdateDamping)
    }

    /// Reduce-Motion-aware fade for chart selection banner appearance/dismissal.
    /// Short duration to feel responsive to selection changes (drag across bars).
    static var chartBannerFade: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: 0.15)
    }

    // MARK: - Reduce Motion Aware Animations

    /// `true` когда пользователь включил "Reduce Motion" в Настройках → Универсальный доступ.
    /// Используй для условного отключения декоративных анимаций (shimmer, bounce и т.д.).
    static var isReduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    /// `Animation` для быстрых переходов с учётом Reduce Motion.
    /// Замена для `.easeInOut(duration: AppAnimation.fast)` в местах, где анимация декоративная.
    static var fastAnimation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: fast)
    }

    /// `Animation` для стандартных переходов с учётом Reduce Motion.
    /// Замена для `.easeInOut(duration: AppAnimation.standard)`.
    static var standardAnimation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: standard)
    }

    /// `Animation` для медленных переходов (модальные экраны) с учётом Reduce Motion.
    static var slowAnimation: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .easeInOut(duration: slow)
    }

    /// Spring-анимация с учётом Reduce Motion.
    /// Замена для `AppAnimation.spring` в декоративных bounce-эффектах.
    static var adaptiveSpring: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : spring
    }

}

// MARK: - Interactive Button Style

/// Интерактивный стиль кнопки с эффектом увеличения и bounce (iOS 16+ style)
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0.0)
            .animation(AppAnimation.adaptiveSpring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BounceButtonStyle {
    /// Применяет iOS 16+ стиль с эффектом увеличения и bounce при нажатии
    static var bounce: BounceButtonStyle {
        BounceButtonStyle()
    }
}
