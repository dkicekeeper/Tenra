//
//  LoopOnBoardingView.swift
//  Tenra
//
//  Animated hero block for onboarding-style screens. Renders a bouncing icon
//  with three staggered pulse rings that swell, peak, then fade before the
//  next loop. Stateless about phase cycling — callers drive the symbol via
//  their own TimelineView (see `OnboardingWelcomeStep`).
//
//  The synced title/subtitle block uses the shared `.blurSlideHero`
//  transition (see `BlurSlideTransition.swift`).
//

import SwiftUI

struct LoopOnBoardingPhase: Hashable {
    let symbol: String
    let title: String
    let subtitle: String
}

struct LoopOnBoardingConfig {
    var tint: Color = AppColors.accent
    var pulseTint: Color = AppColors.accent.opacity(0.65)
    var pulseWidth: CGFloat = 1.3
    var pulseScale: CGFloat = 12
    var iconSize: CGFloat = 100
    var iconScale: CGFloat = 1.25
    /// Seconds per phase. Each phase takes `phaseUpdateAfter * 3` seconds
    /// so the bounce + pulse keyframe track completes exactly once.
    var phaseUpdateAfter: Int = 1
}

// MARK: - Hero (icon + pulse rings only)

/// Animated icon with three staggered pulse rings, driven by `keyframeAnimator`.
/// Stateless about phase cycling — caller hands in the current symbol.
struct LoopOnboardingHero: View {
    let symbol: String
    var config: LoopOnBoardingConfig = LoopOnBoardingConfig()

    private struct Pulse {
        var scale: CGFloat = 1.0
        var opacity: CGFloat = 1.0
    }

    /// Bell curve over the ring's scale progress: ramp opacity up over the first
    /// ~35% of the expansion, hold briefly, then fade fully to 0 before the ring
    /// reaches `maxScale`. Caller multiplies by the keyframe's own opacity track.
    private static func bellOpacity(scale: CGFloat, maxScale: CGFloat) -> CGFloat {
        let denom = max(maxScale - 1, 0.001)
        let progress = min(max((scale - 1) / denom, 0), 1)
        if progress < 0.35 {
            return progress / 0.35
        } else if progress < 0.7 {
            return 1
        } else {
            return max(0, 1 - (progress - 0.7) / 0.3)
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: symbol)
                .font(.system(size: config.iconSize - 20))
                .foregroundStyle(config.tint.gradient)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: config.iconSize, height: config.iconSize)
                .keyframeAnimator(initialValue: 1.0, repeating: true) { content, scale in
                    content.scaleEffect(scale)
                } keyframes: { _ in
                    let scale = config.iconScale
                    SpringKeyframe(1, duration: 0.25)
                    SpringKeyframe(scale, duration: 0.25)
                    SpringKeyframe(1, duration: 0.25)
                    SpringKeyframe(scale, duration: 0.25)
                    SpringKeyframe(1, duration: 0.25)
                    SpringKeyframe(scale, duration: 0.25)
                    SpringKeyframe(1, duration: 0.25)
                    CubicKeyframe(1, duration: 1.25)
                }

            pulseRing(delay: 0, expand: 1.5, hold: 1.5)
            pulseRing(delay: 0.5, expand: 1.5, hold: 1.0)
            pulseRing(delay: 1.0, expand: 1.5, hold: 0.5)
        }
        .frame(width: config.iconSize, height: config.iconSize)
        // Pulse rings and icon are pure decoration — the synced title/subtitle
        // is the meaningful element for VoiceOver.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func pulseRing(delay: CGFloat, expand: CGFloat, hold: CGFloat) -> some View {
        let size = config.iconSize / 2
        let safeDelay = max(delay, 0.001)
        let safeHold = max(hold, 0.001)

        KeyframeAnimator(initialValue: Pulse(), repeating: true) { pulse in
            // Cubic interpolation can briefly overshoot below the start value;
            // clamp so we never feed a negative dimension to `frame`.
            let scale = max(pulse.scale, 0)
            let opacity = Self.bellOpacity(scale: scale, maxScale: config.pulseScale) * pulse.opacity
            Circle()
                .stroke(config.pulseTint, lineWidth: config.pulseWidth)
                .frame(width: size * scale, height: size * scale)
                .opacity(opacity)
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                LinearKeyframe(1, duration: safeDelay)
                // Cubic ramp gives a smoother ease-out feel than linear.
                CubicKeyframe(config.pulseScale, duration: expand)
                LinearKeyframe(config.pulseScale, duration: safeHold)
            }
            KeyframeTrack(\.opacity) {
                LinearKeyframe(1, duration: safeDelay)
                LinearKeyframe(1, duration: expand)
                LinearKeyframe(0, duration: safeHold)
            }
        }
    }
}

// MARK: - Previews

#Preview("Loop Hero — globe") {
    LoopOnboardingHero(symbol: "globe")
        .padding(40)
}
