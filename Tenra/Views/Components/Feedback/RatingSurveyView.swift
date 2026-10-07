//
//  RatingSurveyView.swift
//  Tenra
//
//  Neutral pre-prompt survey shown at a success moment. Filters satisfied users into
//  the native App Store rating prompt and routes unhappy users to private feedback,
//  so 1–2★ ratings are caught before they reach the store.
//
//  Presented by MainTabView, driven by `RatingPromptService.shouldShowSurvey`. Adapter over
//  DesignKit's `PromptSheet` (which closes itself after either answer): the copy, the rating
//  service and the feedback e-mail (to `SupportContact`'s inbox) stay here.
//

import SwiftUI

struct RatingSurveyView: View {

    var body: some View {
        PromptSheet(
            systemImage: "sparkles",
            title: String(localized: "rating.survey.title"),
            message: String(localized: "rating.survey.message"),
            primaryTitle: String(localized: "rating.survey.love"),
            secondaryTitle: String(localized: "rating.survey.notReally"),
            onPrimary: {
                RatingPromptService.shared.requestNativeReview()
            },
            onSecondary: {
                openFeedback()
                RatingPromptService.shared.markPromptedThisVersion()
            }
        )
    }

    private func openFeedback() {
        if let url = SupportContact.mailURL(subject: "Tenra Feedback") {
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
