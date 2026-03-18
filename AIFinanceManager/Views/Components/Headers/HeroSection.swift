//
//  HeroSection.swift
//  AIFinanceManager
//
//  Read-only hero display for views that need icon + title context
//  without editing (e.g. AddTransactionModal, EditTransactionView).
//
//  Use EditableHeroSection when the user needs to edit icon/name.
//

import SwiftUI

/// Read-only hero section displaying an icon and title with a spring entrance animation.
///
/// - When `colorHex` is provided: renders a colored circle icon (category style).
/// - When `colorHex` is nil: renders the glass-hero icon (account / subscription style).
struct HeroSection: View {

    let iconSource: IconSource?
    let title: String
    /// Pass the category `colorHex` to use the colored circle style.
    /// Omit (nil) to use the glass-hero style.
    let colorHex: String?

    @State private var iconScale: CGFloat = 0.8

    init(iconSource: IconSource?, title: String, colorHex: String? = nil) {
        self.iconSource = iconSource
        self.title = title
        self.colorHex = colorHex
    }

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            iconContent
                .scaleEffect(iconScale)
                .onAppear {
                    withAnimation(AppAnimation.heroSpring) {
                        iconScale = 1.0
                    }
                }

            Text(title)
                .font(AppTypography.h2)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.lg)
        }
//        .padding(.vertical, AppSpacing.xl)
    }

    @ViewBuilder
    private var iconContent: some View {
        if let colorHex {
            IconView(
                source: iconSource ?? .sfSymbol("tag.fill"),
                style: .circle(
                    size: AppIconSize.ultra,
                    tint: .monochrome(Color(hex: colorHex)),
                    backgroundColor: AppColors.surface
                )
            )
        } else if #available(iOS 18.0, *) {
            IconView(source: iconSource, style: .glassHero())
        } else {
            IconView(source: iconSource, size: AppIconSize.ultra)
        }
    }
}

// MARK: - Previews

#Preview("Category Style") {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            HeroSection(
                iconSource: .sfSymbol("fork.knife"),
                title: "Food & Drinks",
                colorHex: "#ec4899"
            )
            Divider()
            HeroSection(
                iconSource: .sfSymbol("car.fill"),
                title: "Transport",
                colorHex: "#3b82f6"
            )
        }
    }
}

#Preview("Glass Style") {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            HeroSection(
                iconSource: .sfSymbol("arrow.left.arrow.right"),
                title: "Transfer"
            )
            Divider()
            HeroSection(
                iconSource: .brandService("kaspi.kz"),
                title: "Kaspi Gold"
            )
        }
    }
}

#Preview("Nil Icon") {
    HeroSection(
        iconSource: nil,
        title: "Unknown Category",
        colorHex: "#8b5cf6"
    )
}
