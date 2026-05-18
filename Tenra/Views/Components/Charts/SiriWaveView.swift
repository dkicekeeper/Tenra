//
//  SiriWaveView.swift
//  Tenra
//
//  Voice recording glow overlay wrapper.
//  Uses SiriGlowView (MeshGradient-based) for the visual effect.
//

import SwiftUI

/// Apple Intelligence–style edge glow overlay.
/// Designed as a full-screen `.overlay()` — passes through all touches.
/// Fades in on appear for smooth transition.
struct SiriWaveRecordingView: View {

    @State private var isVisible = false

    var body: some View {
        SiriGlowView()
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(AppAnimation.gentleSpring) {
                    isVisible = true
                }
            }
    }
}

// MARK: - Preview

#Preview("Edge Glow") {
    ZStack {
        Color.white
        VStack(spacing: 20) {
            Text("Edge Glow Recording")
                .font(AppTypography.bodyEmphasis)
        }
    }
    .overlay {
        SiriWaveRecordingView()
            .ignoresSafeArea()
    }
}
