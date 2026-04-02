//
//  ContentRevealModifier.swift
//  AIFinanceManager
//
//  Lightweight modifier that fades content in when data is ready.
//  Replaces SkeletonLoadingModifier — preserves view identity (no if/else branching).
//

import SwiftUI

// MARK: - ContentRevealModifier

/// Fades content in when `isReady` becomes true.
/// Optional `delay` staggers multiple sections so they don't all appear in the same frame.
struct ContentRevealModifier: ViewModifier {
    let isReady: Bool
    var delay: Double = 0

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .animation(AppAnimation.contentRevealAnimation, value: isVisible)
            .onChange(of: isReady) { _, ready in
                guard ready, !isVisible else { return }
                revealAfterDelay()
            }
            .onAppear {
                if isReady && !isVisible {
                    revealAfterDelay()
                }
            }
    }

    private func revealAfterDelay() {
        if delay > 0 {
            Task {
                try? await Task.sleep(for: .milliseconds(Int(delay * 1000)))
                isVisible = true
            }
        } else {
            isVisible = true
        }
    }
}

// MARK: - View Extension

extension View {
    /// Hides this view until `isReady` is true, then fades it in.
    /// Use `delay` to stagger multiple sections for a smooth cascading reveal.
    func contentReveal(isReady: Bool, delay: Double = 0) -> some View {
        modifier(ContentRevealModifier(isReady: isReady, delay: delay))
    }
}
