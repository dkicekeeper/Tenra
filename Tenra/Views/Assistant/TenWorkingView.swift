//
//  TenWorkingView.swift
//  Tenra
//
//  Ten at a long piece of work (plan-ten-gamification.md §11, stage 1): a statement's pages
//  being read on the Import tab, a backup being restored from Settings. He fills with light as
//  the work goes (DesignKit's `.working(progress:)`) and thinks while there is no count yet.
//  Without the assistant on the device, the system's bar or spinner.
//

import SwiftUI

struct TenWorkingView: View {
    /// 0…1, nil while the work has no count yet.
    let progress: Double?

    var body: some View {
        if AssistantAvailability.isAvailable {
            ParticleCreature(mood: mood)
                .frame(width: TenWorkingMetrics.size, height: TenWorkingMetrics.size)
                .accessibilityHidden(true)
        } else if let progress {
            ProgressView(value: min(max(progress, 0), 1))
        } else {
            ProgressView()
        }
    }

    private var mood: ParticleCreature.Mood {
        guard let progress else { return .thinking }
        return .working(progress: min(max(progress, 0), 1))
    }
}

private enum TenWorkingMetrics {
    /// Where the hero style reads well (DesignKit: from about 160 pt).
    static let size: CGFloat = 160
}
