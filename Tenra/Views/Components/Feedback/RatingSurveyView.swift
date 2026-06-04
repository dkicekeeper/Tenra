//
//  RatingSurveyView.swift
//  Tenra
//
//  Neutral pre-prompt survey shown at a success moment. Filters satisfied users into
//  the native App Store rating prompt and routes unhappy users to private feedback,
//  so 1–2★ ratings are caught before they reach the store.
//
//  Presented by MainTabView, driven by `RatingPromptService.shouldShowSurvey`.
//

import SwiftUI

struct RatingSurveyView: View {

    @Environment(\.dismiss) private var dismiss

    /// Feedback inbox — keep in sync with the support page contact email.
    private let feedbackEmail = "dakacom@gmail.com"

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.accent)
                .padding(.top, AppSpacing.xl)

            VStack(spacing: AppSpacing.sm) {
                Text(String(localized: "rating.survey.title"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(String(localized: "rating.survey.message"))
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, AppSpacing.lg)

            Spacer(minLength: 0)

            VStack(spacing: AppSpacing.sm) {
                Button {
                    RatingPromptService.shared.requestNativeReview()
                    dismiss()
                } label: {
                    Text(String(localized: "rating.survey.love"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .background(AppColors.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                Button {
                    openFeedback()
                    RatingPromptService.shared.markPromptedThisVersion()
                    dismiss()
                } label: {
                    Text(String(localized: "rating.survey.notReally"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.md)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .background(AppColors.bgBase.ignoresSafeArea())
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
    }

    private func openFeedback() {
        let subject = "Tenra Feedback"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let body = "\n\n—\nTenra \(version) (\(build)) · iOS \(UIDevice.current.systemVersion)"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            RatingSurveyView()
        }
}
