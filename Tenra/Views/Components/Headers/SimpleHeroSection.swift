//
//  SimpleHeroSection.swift
//  Tenra
//
//  Read-only hero display for views that need icon + title context
//  without editing (e.g. AddTransactionModal, EditTransactionView).
//
//  Use EditableHeroSection when the user needs to edit icon/name.
//
//  NOTE: Renamed from HeroSection (2026-04-23) to make room for the new
//  entity-detail HeroSection at Views/Components/EntityDetail/HeroSection.swift
//  which is richer (icon + title + amount + progress + conversion). This simpler
//  icon+title variant remains used by TransactionAddModal, TransactionEditView,
//  and InsightDeepDiveView.
//

import SwiftUI

/// Read-only hero section displaying an icon and title with a spring entrance animation.
/// Always uses the glass-hero icon style.
struct SimpleHeroSection: View {

    let iconSource: IconSource?
    let title: String

    @State private var iconScale: CGFloat = 0

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            IconView(
                source: iconSource ?? .sfSymbol("tag.fill"),
                style: .glassHero()
            )
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
    }
}

// MARK: - Previews

#Preview("Glass Hero") {
    ScrollView {
        VStack(spacing: AppSpacing.lg) {
            SimpleHeroSection(
                iconSource: .sfSymbol("fork.knife"),
                title: "Food & Drinks"
            )
            Divider()
            SimpleHeroSection(
                iconSource: .sfSymbol("car.fill"),
                title: "Transport"
            )
            Divider()
            SimpleHeroSection(
                iconSource: .brandService("kaspi.kz"),
                title: "Kaspi Gold"
            )
        }
    }
}

#Preview("Nil Icon") {
    SimpleHeroSection(
        iconSource: nil,
        title: "Unknown Category"
    )
}
