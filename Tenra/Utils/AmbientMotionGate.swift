//
//  AmbientMotionGate.swift
//  Tenra
//
//  Single answer to "may this view keep redrawing an ambient animation right now?"
//
//  Two signals turn ambient motion off:
//  - Reduce Motion — the accessibility setting these views already honored.
//  - `systemPrefersReducedResourceUsage` (iOS 27) — the system telling apps to back
//    off, e.g. under thermal or power pressure. Continuously redrawing decoration is
//    exactly the work worth dropping first: it carries no information.
//
//  Only views driven by a `TimelineView` (display-rate or 30 fps) need this. A
//  one-shot transition is not ambient motion.
//

import SwiftUI

struct AmbientMotionGate<Content: View>: View {

    /// Receives `false` when ambient motion should be suspended; render a static
    /// frame in that case rather than removing the view, so layout does not shift.
    @ViewBuilder var content: (_ allowsAmbientMotion: Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if #available(iOS 27, *) {
            ResourceAwareAmbientMotionGate(reduceMotion: reduceMotion, content: content)
        } else {
            content(!reduceMotion)
        }
    }
}

/// Split into its own type because `@Environment(\.systemPrefersReducedResourceUsage)`
/// is iOS 27-only: a stored property cannot carry an availability annotation, so the
/// type carries it instead.
@available(iOS 27, *)
private struct ResourceAwareAmbientMotionGate<Content: View>: View {

    let reduceMotion: Bool
    @ViewBuilder var content: (_ allowsAmbientMotion: Bool) -> Content

    @Environment(\.systemPrefersReducedResourceUsage) private var prefersReducedResourceUsage

    var body: some View {
        content(!reduceMotion && !prefersReducedResourceUsage)
    }
}
