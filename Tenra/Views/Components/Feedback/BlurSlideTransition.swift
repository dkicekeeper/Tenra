//
//  BlurSlideTransition.swift
//  Tenra
//
//  Canonical text-reveal transition. Insertion: slides up from below +
//  un-blurs + fades in. Removal: keeps sliding up off-screen + blurs +
//  fades out. Originally built for the onboarding hero title/subtitle
//  loop; now the shared style for any animated text appearance.
//
//  Use the presets instead of hand-tuning parameters:
//  • `.blurSlideHero` — block-level text (onboarding title/subtitle).
//  • `.blurSlideWord` — per-word streaming text (voice transcription).
//    Deliberately shorter travel + lighter blur: many words can be
//    transitioning at once and per-word blur is the dominant GPU cost.
//

import SwiftUI

struct BlurSlideTransition: Transition {
    var slideDistance: CGFloat = 24
    var blurRadius: CGFloat = 10

    func body(content: Content, phase: TransitionPhase) -> some View {
        let yOffset: CGFloat = {
            switch phase {
            case .willAppear: return slideDistance      // start below identity
            case .identity: return 0
            case .didDisappear: return -slideDistance   // exit upward
            }
        }()

        return content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : blurRadius)
            .offset(y: yOffset)
    }
}

extension Transition where Self == BlurSlideTransition {
    /// Block-level text reveal — onboarding hero title/subtitle blocks.
    static var blurSlideHero: BlurSlideTransition { BlurSlideTransition() }

    /// Per-word reveal for streaming text (voice transcription).
    /// Shorter travel + lighter blur than `blurSlideHero` — tuned for many
    /// small views transitioning simultaneously.
    static var blurSlideWord: BlurSlideTransition {
        BlurSlideTransition(slideDistance: 18, blurRadius: 6)
    }
}

// MARK: - Preview

#Preview("BlurSlide — hero vs word") {
    struct Demo: View {
        @State private var visible = true
        var body: some View {
            VStack(spacing: 40) {
                if visible {
                    Text("Hero block reveal")
                        .font(.title2.weight(.semibold))
                        .transition(.blurSlideHero)
                    HStack {
                        ForEach(["per", "word", "reveal"], id: \.self) { word in
                            Text(word).transition(.blurSlideWord)
                        }
                    }
                }
                Button("Toggle") {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        visible.toggle()
                    }
                }
            }
            .padding(40)
        }
    }
    return Demo()
}
