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
//  service and the feedback e-mail stay here.
//

import SwiftUI

struct RatingSurveyView: View {

    /// Feedback inbox — keep in sync with the support page contact email.
    private let feedbackEmail = "dakacom@gmail.com"

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
