//
//  OnboardingWelcomeStep.swift
//  Tenra
//
//  NavigationStack root for onboarding. Drives the icon-cycle via TimelineView
//  and stacks the synced title/subtitle just above the primary CTA so the
//  copy reads alongside the action, not floating under the hero.
//
//  When the user advances past welcome (`vm.path` becomes non-empty), the
//  TimelineView and its keyframe animators are torn down — the welcome view
//  is invisible behind the pushed step, no need to keep ticking. They are
//  reconstructed with a fresh `startDate` if the user pops back.
//

import SwiftUI

struct OnboardingWelcomeStep: View {
    @Bindable var vm: OnboardingViewModel

    @State private var startDate: Date = .now

    /// Onboarding hero phase spring — component-local per design-system §9
    /// (no inline `.spring(...)` literals in view bodies).
    private static let phaseSpring: Animation = .spring(response: 0.55, dampingFraction: 0.85)

    private static let phases: [LoopOnBoardingPhase] = [
        LoopOnBoardingPhase(
            symbol: "chart.pie.fill",
            title: String(localized: "onboarding.welcome.page1.title"),
            subtitle: String(localized: "onboarding.welcome.page1.subtitle")
        ),
        LoopOnBoardingPhase(
            symbol: "mic.fill",
            title: String(localized: "onboarding.welcome.page2.title"),
            subtitle: String(localized: "onboarding.welcome.page2.subtitle")
        ),
        LoopOnBoardingPhase(
            symbol: "lock.shield.fill",
            title: String(localized: "onboarding.welcome.page3.title"),
            subtitle: String(localized: "onboarding.welcome.page3.subtitle")
        ),
    ]

    private let config = LoopOnBoardingConfig()

    var body: some View {
        Group {
            if vm.path.isEmpty {
                animatedWelcome
            } else {
                Color.clear
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onboardingAccentGlow()
        .onChange(of: vm.path.isEmpty) { _, isBackOnWelcome in
            if isBackOnWelcome {
                // Restart the phase cycle from index 0 when the user pops back.
                startDate = .now
            }
        }
    }

    private var animatedWelcome: some View {
        let timelineDuration = CGFloat(config.phaseUpdateAfter) * 3.0

        return TimelineView(.periodic(from: startDate, by: timelineDuration)) { ctx in
            let diff = Int(startDate.distance(to: ctx.date)) / (config.phaseUpdateAfter * 3)
            let index = diff % Self.phases.count
            let phase = Self.phases[index]

            VStack(spacing: 0) {
                Spacer()

                LoopOnboardingHero(symbol: phase.symbol, config: config)

                Spacer()

                VStack(spacing: AppSpacing.sm) {
                    Text(phase.title)
                        .font(AppTypography.h3)
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                    Text(phase.subtitle)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .screenPadding()
                .id(index)
                .transition(.blurSlideHero)
                .padding(.bottom, AppSpacing.xl)

                Button {
                    vm.startDataCollection()
                } label: {
                    Text(String(localized: "onboarding.cta.start"))
                        .frame(maxWidth: .infinity)
                }
                .primaryButton()
                .screenPadding()
                .padding(.bottom, AppSpacing.lg)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Self.phaseSpring, value: index)
            .sensoryFeedback(.selection, trigger: index)
        }
    }
}

#Preview("Onboarding — Welcome") {
    let vm = OnboardingViewModel.makeForTesting()
    return NavigationStack {
        OnboardingWelcomeStep(vm: vm)
    }
}
