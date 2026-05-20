//
//  OnboardingPageContainer.swift
//  Tenra
//
//  Shared layout for onboarding data-collection steps. Mirrors the welcome
//  screen's vertical rhythm: content lives at the top under the toolbar step
//  indicator, then title + subtitle sit just above the primary CTA at the
//  bottom. No forced page background — the accent-glow background shows through.
//

import SwiftUI

struct OnboardingPageContainer<Content: View>: View {
    let progressStep: Int            // 1, 2, or 3
    let title: String
    let subtitle: String?
    let primaryButtonTitle: String
    let primaryButtonEnabled: Bool
    let onPrimaryTap: () -> Void
    /// Optional trailing «Skip» action. When provided, a text button is added
    /// to `.topBarTrailing` — used on data-collection steps so the user can
    /// bail out to MainTabView with defaults applied.
    var onSkip: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomChrome
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    OnboardingStepIndicator(currentStep: progressStep)
                }
                if let onSkip {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onSkip) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "onboarding.cta.skip"))
                        .tint(AppColors.textSecondary)
                    }
                }
            }
            // Empty inline navigationTitle: the principal ToolbarItem (step indicator)
            // visually replaces the title, and inline display mode keeps the bar compact.
            // The transparent nav bar (no scroll-edge plate over the accent-glow) is
            // achieved by the step content wrapping CurrencyListContent in its own
            // ScrollView — see OnboardingCurrencyStep.
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
    }

    private var bottomChrome: some View {
        VStack(spacing: AppSpacing.md) {
            VStack(alignment: .center, spacing: AppSpacing.sm) {
                Text(title)
                    .font(AppTypography.h3)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                if let subtitle {
                    Text(subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .screenPadding()

            Button(action: onPrimaryTap) {
                Text(primaryButtonTitle)
                    .frame(maxWidth: .infinity)
            }
            .primaryButton()
            .disabled(!primaryButtonEnabled)
            .screenPadding()
        }
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.sm)
        .background {
            // Frosted-glass backdrop that fades in from clear at the top so the
            // accent-glow stays visible and the title/button don't visually
            // collide with the scroll content above. Material alone (без opaque
            // overlay) пропускает свечение снизу.
            Rectangle()
                .fill(AppColors.bgBase)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.3),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    // Accent-glow поверх rectangle, но под title/button
                    // (background-слой рисуется ниже content).
                    Circle()
                        .fill(AppColors.accent.gradient)
                        .visualEffect { content, proxy in
                            content.offset(y: proxy.size.height * 0.5)
                        }
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .blur(radius: 120)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

#Preview("Onboarding Page Container") {
    NavigationStack {
        OnboardingPageContainer(
            progressStep: 2,
            title: "Step title goes here",
            subtitle: "Short supporting copy that explains the step.",
            primaryButtonTitle: "Next",
            primaryButtonEnabled: true,
            onPrimaryTap: {}
        ) {
            ScrollView {
                ForEach(0..<30) { i in
                    Text("Row \(i)").frame(maxWidth: .infinity).padding()
                }
            }
        }
    }
}
