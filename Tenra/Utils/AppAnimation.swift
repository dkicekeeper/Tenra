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

    /// Snappy content spring — for content transitions (amount inputs, list changes, toggles).
    /// response 0.3 + damping 0.7 = quick settle with minimal overshoot.
    static let contentSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Gentle spring — for smooth value animations (amount display, error messages, state changes).
    /// response 0.4 + damping 0.8 = soft deceleration, no visible overshoot.
    static let gentleSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    /// Hero spring — legacy dramatic settle (response 0.6, ~0.9s perceived).
    /// Prefer `heroEntranceAnimation` for icon entrances — it stays in the ≤350ms
    /// entrance budget and is Reduce-Motion aware. Kept for any non-entrance use.
    static let heroSpring = Animation.spring(response: 0.6, dampingFraction: 0.7)

    /// Starting scale for hero icon entrance (grows from this to 1.0).
    /// Never 0 — nothing in the real world appears from nothing.
    static let heroHiddenScale: CGFloat = 0.92

    /// Reduce-Motion-aware hero icon entrance. Snappier than `heroSpring`:
    /// settles within the ~350ms entrance budget.
    static var heroEntranceAnimation: Animation {
        isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: 0.35, dampingFraction: 0.75)
    }

    /// Programmatic carousel scroll-to-selection (account/category selectors).
    static let carouselScroll: Animation = .easeInOut(duration: 0.3)

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

    /// Content reveal animation — for staggered section fade-in during initialization.
    static let contentRevealAnimation = Animation.easeOut(duration: 0.35)

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

    /// Fade for chart selection banner appearance/dismissal. Opacity-only —
    /// deliberately NOT Reduce-Motion-gated: fades aid comprehension and contain
    /// no movement, so they should survive Reduce Motion (AUDIT §6).
    static let chartBannerFade: Animation = .easeInOut(duration: 0.15)

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

    /// Spring-анимация с visible overshoot и учётом Reduce Motion.
    /// Используется в декоративных bounce-эффектах (BounceButtonStyle и т.п.).
    static var adaptiveSpring: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? .linear(duration: 0)
            : .spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)
    }

    /// Reduce-Motion-aware fill animation for ALL progress bars/rings
    /// (ExpenseIncomeProgressBar, BudgetProgressBar, ProportionBar, BudgetProgressCircle).
    /// `nil` under Reduce Motion so the value jumps instantly (no width/arc sweep).
    static var progressFillAnimation: Animation? {
        isReduceMotionEnabled ? nil : progressBarSpring
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
