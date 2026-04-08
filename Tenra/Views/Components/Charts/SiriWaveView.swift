//
//  SiriWaveView.swift
//  Tenra
//
//  Aurora-style Metal wave (Phase 50).
//  Uses SiriWaveMetalView (MTKView + SiriWaveShader.metal) for GPU rendering.
//  Falls back to SwiftUI Canvas if Metal is unavailable.
//

import SwiftUI
import Metal

// MARK: - SiriWaveView

/// Single Metal-backed Aurora wave.
/// `amplitude` maps the old 0–60 range; internally normalized to 0–1.
struct SiriWaveView: View {

    let amplitude: Double
    /// Kept for API compatibility; not used in Metal path.
    var color: Color = AppColors.accent
    /// Kept for API compatibility; not used in Metal path.
    var frequency: Double = 4
    /// Kept for API compatibility; not used in Metal path.
    var animationSpeed: Double = 1.5

    init(
        amplitude: Double = 30,
        frequency: Double = 4,
        color: Color = AppColors.accent,
        animationSpeed: Double = 1.5
    ) {
        self.amplitude = amplitude
        self.frequency = frequency
        self.color = color
        self.animationSpeed = animationSpeed
    }

    var body: some View {
        waveContent
    }

    @ViewBuilder
    private var waveContent: some View {
        if MTLCreateSystemDefaultDevice() != nil {
            let ref = AudioLevelRef()
            let _ = { ref.value = Float(amplitude / 60.0).clamped(to: 0.1...1.0) }()
            SiriWaveMetalView(amplitudeRef: ref, isPaused: AppAnimation.isReduceMotionEnabled)
        } else {
            canvasFallback
        }
    }

    // Simple Canvas fallback for cases where Metal isn't available
    private var canvasFallback: some View {
        TimelineView(.periodic(from: .now, by: 0.016)) { timeline in
            Canvas { ctx, size in
                let elapsed = timeline.date.timeIntervalSince1970
                let phase = (elapsed * 2 * .pi / animationSpeed).truncatingRemainder(dividingBy: 2 * .pi)
                var path = Path()
                let mid = size.height / 2
                path.move(to: CGPoint(x: 0, y: mid))
                for x in stride(from: 0.0, through: size.width, by: 1.0) {
                    let y = mid + sin(x / size.width * frequency * 2 * .pi + phase) * amplitude
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - SiriWaveRecordingView

/// Apple Intelligence–style edge glow overlay.
/// Pass `amplitudeRef` from `VoiceInputService` — renderer reads `.value` directly every frame.
/// Designed to be used as a full-screen `.overlay()` — passes through all touches.
struct SiriWaveRecordingView: View {

    var amplitudeRef: AudioLevelRef

    var body: some View {
        SiriWaveMetalView(
            amplitudeRef: amplitudeRef,
            isPaused: AppAnimation.isReduceMotionEnabled
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Float helper

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        Swift.max(range.lowerBound, Swift.min(range.upperBound, self))
    }
}

// MARK: - Previews

#Preview("Static Wave") {
    ZStack {
        VStack(spacing: 40) {
            Text("Static Wave (Legacy)")
                .font(AppTypography.bodyEmphasis)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay {
        SiriWaveView(amplitude: 30, frequency: 4, color: .blue)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

#Preview("Edge Glow") {
    let ref = AudioLevelRef()
    ref.value = 0.7
    return ZStack {
        VStack(spacing: 40) {
            Text("Edge Glow Recording")
                .font(AppTypography.bodyEmphasis)
            Text("Amplitude: 0.7")
                .font(AppTypography.caption)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay {
        SiriWaveRecordingView(amplitudeRef: ref)
            .ignoresSafeArea()
    }
}
