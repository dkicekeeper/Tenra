//
//  YearReviewLink.swift
//  Tenra
//
//  The year in review's card at the top of Analytics (docs/plan-release-1.9.md §3): from
//  15 December to 31 January (YearReviewWindow), for someone the year has enough to review.
//  DesignKit's NoticeCard with Ten, as his message on Home; its button opens the review on the
//  whole screen. Self-contained: reads the coordinator and asks YearReviewLoader again whenever
//  an input changes (the loader keeps the review until then). Takes no room outside the window.
//

import SwiftUI

struct YearReviewLink: View {
    @Environment(AppCoordinator.self) private var coordinator

    @State private var review: YearReview?
    @State private var showingReview = false

    private var store: TransactionStore { coordinator.transactionStore }

    // Everything the review reads (CLAUDE.md, red flag 12); the loader's key holds the same.
    private struct Trigger: Equatable {
        let year: Int?
        let txVersion: Int
        let series: [RecurringSeries]
        let categoriesVersion: Int
        let ratesVersion: Int
        let baseCurrency: String
        let brands: MerchantBrands
        let day: Date
        let isFullyInitialized: Bool
    }

    private var trigger: Trigger {
        // The versions are @ObservationIgnored: touch the observable array so `body` re-runs.
        _ = store.transactions.count
        let today = Date()
        return Trigger(
            year: YearReviewWindow.year(on: today),
            txVersion: store.mutationVersion,
            series: store.recurringSeries,
            categoriesVersion: store.categoriesMutationVersion,
            ratesVersion: store.currencyRatesVersion,
            baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
            brands: MerchantGroupStore.shared.brands,
            day: Calendar.current.startOfDay(for: today),
            isFullyInitialized: coordinator.isFullyInitialized
        )
    }

    var body: some View {
        // A ZStack, not a Group: `.task` needs a view to hang on while there is no card.
        ZStack {
            if let review {
                NoticeCard(
                    title: String(format: String(localized: "yearReview.card.title"), String(review.year)),
                    message: String(localized: "yearReview.card.text"),
                    actionTitle: String(localized: "yearReview.notice.action"),
                    actionSystemImage: "gift",
                    action: {
                        HapticManager.light()
                        showingReview = true
                    }
                ) {
                    ParticleCreature(mood: .celebrating, style: .compact, accessory: coordinator.tenWardrobe.accessory())
                        .frame(width: NoticeCardMetrics.leadingSize, height: NoticeCardMetrics.leadingSize)
                        .accessibilityHidden(true)
                }
                .accessibilityIdentifier("insights.yearReview")
                .transition(.opacity)
            }
        }
        .fullScreenCover(isPresented: $showingReview) {
            if let review {
                YearReviewView(
                    review: review,
                    categories: store.categories,
                    accessory: coordinator.tenWardrobe.accessory()
                )
            }
        }
        .task(id: trigger) {
            guard let year = trigger.year else {
                review = nil
                return
            }
            guard coordinator.isFullyInitialized, !store.isImporting else { return }
            let loaded = await YearReviewLoader.review(
                year: year,
                store: store,
                baseCurrency: trigger.baseCurrency,
                brands: trigger.brands
            )
            guard !Task.isCancelled else { return }
            withAnimation(AppAnimation.smooth) { review = loaded }
        }
    }
}
