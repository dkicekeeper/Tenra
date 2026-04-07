//
//  ProportionBar.swift
//  Tenra
//
//  Horizontal bar showing two proportions side by side
//  (e.g. principal vs interest, spent vs remaining).
//

import SwiftUI

struct ProportionBar: View {
    let ratio: Double
    let leftColor: Color
    let rightColor: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: AppSpacing.xxs) {
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .fill(leftColor)
                    .frame(width: geo.size.width * max(0, min(1, ratio)))
                RoundedRectangle(cornerRadius: AppRadius.xs)
                    .fill(rightColor)
            }
        }
        .frame(height: height)
    }
}
