//
//  YearReviewView.swift
//  Tenra
//
//  The year in review (docs/plan-release-1.9.md §3): a calendar year in Tenra, page by page, on
//  the whole screen. Swiped or moved on with Next; a page with nothing to show is left out
//  (YearReviewPage). The figures come from YearReviewBuilder through YearReviewLoader, so they
//  follow Analytics' money rules; this file only lays them out, from DesignKit's parts.
//
//  YearReviewScreen loads the review for a year and shows it: what Analytics' card and Ten's
//  message open. The last page shares a picture of the year (YearReviewShareCard), without
//  amounts unless the person turns them on.
//

import SwiftUI

/// Loads the review of `year` and shows it; a quiet state while it computes, an empty state if
/// there turns out to be too little to review.
struct YearReviewScreen: View {
    @Environment(AppCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    let year: Int

    @State private var review: YearReview?
    @State private var isLoaded = false

    var body: some View {
        Group {
            if let review {
                YearReviewView(
                    review: review,
                    categories: coordinator.transactionStore.categories,
                    accessory: coordinator.tenWardrobe.accessory()
                )
            } else {
                NavigationStack {
                    Group {
                        if isLoaded {
                            EmptyState(
                                icon: "sparkles",
                                title: String(localized: "yearReview.empty.title"),
                                description: String(localized: "yearReview.empty.text")
                            )
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(String(localized: "button.close"), systemImage: "xmark") { dismiss() }
                        }
                    }
                }
            }
        }
        .task {
            let store = coordinator.transactionStore
            let loaded = await YearReviewLoader.review(
                year: year,
                store: store,
                baseCurrency: coordinator.transactionsViewModel.appSettings.baseCurrency,
                brands: MerchantGroupStore.shared.brands
            )
            withAnimation(AppAnimation.smooth) {
                review = loaded
                isLoaded = true
            }
        }
    }
}

struct YearReviewView: View {
    let review: YearReview
    /// The person's categories: the icons and colours of the top categories and merchants.
    let categories: [CustomCategory]
    /// What Ten wears today (TenWardrobeStore).
    let accessory: CreatureAccessory?

    @Environment(\.dismiss) private var dismiss
    @State private var page: Int
    @State private var sharing = false
    /// The share picture's amounts (plan §3: off by default, the person's figures stay theirs).
    @AppStorage(YearReviewShareCard.amountsKey) private var shareAmounts = false

    /// `initialPage`: the page it opens on (the mockups show each one).
    init(review: YearReview, categories: [CustomCategory] = [], accessory: CreatureAccessory? = nil, initialPage: Int = 0) {
        self.review = review
        self.categories = categories
        self.accessory = accessory
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        let pages = YearReviewPage.pages(for: review)
        let isLast = page >= pages.count - 1
        NavigationStack {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.element) { index, kind in
                    ScrollView {
                        pageContent(kind)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .screenPadding()
                            .padding(.vertical, AppSpacing.xl)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .background { aurora }
            .safeAreaBar(edge: .bottom) {
                bottomButton(isLast: isLast)
                    .screenPadding()
                    .padding(.bottom, AppSpacing.md)
            }
            .navigationTitle(Text(verbatim: String(review.year)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "button.close"), systemImage: "xmark") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $sharing) {
            ShareCardSheet(
                previewTitle: "Tenra",
                formats: [.story],
                load: { Optional(review) },
                message: { review in YearReviewShareCard.message(for: review) },
                card: { review, format in
                    YearReviewShareCard(
                        review: review,
                        showsAmounts: shareAmounts,
                        categories: categories,
                        accessory: accessory,
                        format: format
                    )
                }
            )
        }
    }

    // MARK: - Chrome

    /// The accent's aurora behind every page, still, so the pages never redraw for it.
    private var aurora: some View {
        AuroraBackground(intensity: YearReviewMetrics.auroraIntensity, motion: .still)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func bottomButton(isLast: Bool) -> some View {
        if isLast {
            DSButton(
                String(localized: "yearReview.share"),
                systemImage: "square.and.arrow.up",
                fullWidth: true
            ) {
                HapticManager.light()
                sharing = true
            }
        } else {
            DSButton(String(localized: "onboarding.cta.next"), fullWidth: true) {
                withAnimation(AppAnimation.contentSpring) { page += 1 }
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func pageContent(_ kind: YearReviewPage) -> some View {
        switch kind {
        case .cover: cover
        case .money: money
        case .months: months
        case .categories: topCategories
        case .merchants: topMerchants
        case .subscriptions: subscriptions
        case .habit: habit
        case .biggest: biggest
        case .finale: finale
        }
    }

    /// The eyebrow and the title every page starts with.
    private func heading(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(eyebrow)
                .font(AppTypography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(AppColors.accent)
            Text(title)
                .font(AppTypography.h2)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var yearText: String { String(review.year) }

    private var cover: some View {
        VStack(spacing: AppSpacing.xl) {
            ParticleCreature(mood: .celebrating, accessory: accessory)
                .frame(width: YearReviewMetrics.creatureSize, height: YearReviewMetrics.creatureSize)
                .accessibilityHidden(true)
            VStack(spacing: AppSpacing.md) {
                Text(String(format: String(localized: "yearReview.cover.title"), yearText))
                    .font(AppTypography.h1)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(String(localized: "yearReview.cover.text"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.xxl)
    }

    private var money: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            heading(String(localized: "yearReview.money.eyebrow"), String(localized: "yearReview.money.title"))
            FormattedAmountText(
                amount: review.expenses,
                currency: review.currency,
                fontSize: AppTypography.h1,
                fontWeight: .bold,
                color: AppColors.textPrimary
            )
            if review.income > 0 {
                FormSection {
                    AmountRow(
                        String(localized: "yearReview.money.income"),
                        leading: .tinted(.sfSymbol("arrow.down.circle.fill"), AppColors.income),
                        value: .amount(review.income),
                        currency: review.currency
                    )
                    AmountRow(
                        review.saved >= 0
                            ? String(localized: "yearReview.money.left")
                            : String(localized: "yearReview.money.over"),
                        leading: .tinted(.sfSymbol(review.saved >= 0 ? "banknote.fill" : "exclamationmark.circle.fill"),
                                         review.saved >= 0 ? AppColors.success : AppColors.warning),
                        value: .amount(abs(review.saved)),
                        currency: review.currency
                    )
                }
                if let rate = review.savingsRate, rate > 0 {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        ProportionBar(ratio: rate, leftColor: AppColors.success, rightColor: AppColors.expense)
                        Text(String(format: String(localized: "yearReview.money.kept"), NumberDisplay.percent(rate * 100)))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
    }

    private var months: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            heading(String(localized: "yearReview.months.eyebrow"), String(localized: "yearReview.months.title"))
            MiniBars(
                values: review.monthlyExpenses,
                highlighted: review.busiestMonth.map { $0 - 1 },
                color: AppColors.accent,
                labels: Array(YearReviewText.monthInitials.prefix(review.monthlyExpenses.count)),
                height: YearReviewMetrics.barsHeight
            )
            .accessibilityHidden(true)
            FormSection {
                if let busiest = review.busiestMonth {
                    AmountRow(
                        String(format: String(localized: "yearReview.months.busiest"), YearReviewText.monthName(busiest)),
                        leading: .tinted(.sfSymbol("flame.fill"), AppColors.warning),
                        value: .amount(review.monthlyExpenses[busiest - 1]),
                        currency: review.currency
                    )
                }
                if let calmest = review.calmestMonth {
                    AmountRow(
                        String(format: String(localized: "yearReview.months.calmest"), YearReviewText.monthName(calmest)),
                        leading: .tinted(.sfSymbol("leaf.fill"), AppColors.success),
                        value: .amount(review.monthlyExpenses[calmest - 1]),
                        currency: review.currency
                    )
                }
            }
        }
    }

    private var topCategories: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            heading(String(localized: "yearReview.categories.eyebrow"), String(localized: "yearReview.categories.title"))
            FormSection {
                ForEach(review.topCategories) { category in
                    let style = categoryStyle(category.key)
                    AmountRow(
                        CategoryDisplay.displayName(for: category.key, type: .expense),
                        leading: .tinted(style.icon, style.color),
                        value: .share(category.amount, percentage: category.share * 100),
                        currency: review.currency
                    )
                }
            }
        }
    }

    private var topMerchants: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            heading(String(localized: "yearReview.merchants.eyebrow"), String(localized: "yearReview.merchants.title"))
            FormSection {
                ForEach(review.topMerchants) { merchant in
                    let style = categoryStyle(merchant.usualCategory)
                    AmountRow(
                        merchant.name,
                        subtitle: YearReviewText.visits(merchant.visits),
                        leading: .tinted(style.icon, style.color),
                        value: .amount(merchant.amount),
                        currency: review.currency
                    )
                }
            }
        }
    }

    private var subscriptions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            heading(String(localized: "yearReview.subscriptions.eyebrow"), String(localized: "yearReview.subscriptions.title"))
            FormattedAmountText(
                amount: review.subscriptionsTotal,
                currency: review.currency,
                fontSize: AppTypography.h1,
                fontWeight: .bold,
                color: AppColors.textPrimary
            )
            Text(YearReviewText.subscriptions(review.subscriptionsCount))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var habit: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            heading(String(localized: "yearReview.habit.eyebrow"), String(localized: "yearReview.habit.title"))
            StatsStrip(items: YearReviewText.habitStats(review.habit))
            Text(String(localized: "yearReview.habit.text"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    @ViewBuilder
    private var biggest: some View {
        if let biggest = review.biggestExpense {
            let style = categoryStyle(biggest.categoryKey)
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                heading(String(localized: "yearReview.biggest.eyebrow"), String(localized: "yearReview.biggest.title"))
                HeroSection(
                    icon: style.icon,
                    title: biggest.title,
                    iconTint: .monochrome(style.color),
                    primaryAmount: biggest.amount,
                    primaryCurrency: review.currency,
                    subtitle: FastDateParser.date(from: biggest.date).map { DateFormatters.day($0, includeYear: false) }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var finale: some View {
        VStack(spacing: AppSpacing.xl) {
            ParticleCreature(mood: .happy, accessory: accessory)
                .frame(width: YearReviewMetrics.creatureSize, height: YearReviewMetrics.creatureSize)
                .accessibilityHidden(true)
            VStack(spacing: AppSpacing.md) {
                Text(String(format: String(localized: "yearReview.finale.title"), String(review.year + 1)))
                    .font(AppTypography.h2)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(String(localized: "yearReview.finale.text"))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            FormSection(footer: String(localized: "yearReview.share.amountsFooter")) {
                UniversalRow(
                    String(localized: "yearReview.share.amounts"),
                    icon: "eye",
                    accessory: .toggle($shareAmounts)
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Categories

    private func categoryStyle(_ key: String) -> (icon: IconSource?, color: Color) {
        Self.categoryStyle(key, in: categories)
    }

    /// A category key's icon and colour: the person's category, the synthetic loan and interest
    /// keys' own, the accent for a category deleted since.
    static func categoryStyle(_ key: String, in categories: [CustomCategory]) -> (icon: IconSource?, color: Color) {
        if let synthetic = InsightsService.syntheticCategoryStyle(for: key) {
            return (synthetic.icon, synthetic.color)
        }
        let category = categories.first { $0.name == key && $0.type == .expense }
            ?? categories.first { $0.name == key }
        return (category?.iconSource, category.map { Color(hex: $0.colorHex) } ?? AppColors.accent)
    }
}

enum YearReviewMetrics {
    /// Ten on the first and the last page.
    static let creatureSize: CGFloat = 180
    /// The months' bars.
    static let barsHeight: CGFloat = 160
    static let auroraIntensity: Double = 0.45
}

/// The review's words that are not a plain key: plurals, months, the habit's counters.
enum YearReviewText {
    /// "12 visits".
    static func visits(_ count: Int) -> String {
        String(format: NSLocalizedString("yearReview.merchants.visits", comment: "Visits to a merchant in the year"), count)
    }

    /// "Across 4 subscriptions".
    static func subscriptions(_ count: Int) -> String {
        String(format: NSLocalizedString("yearReview.subscriptions.count", comment: "Subscriptions charged in the year"), count)
    }

    /// The habit's three counters: records, days with one, the longest run.
    static func habitStats(_ habit: YearReview.Habit) -> [StatsStrip.Item] {
        [
            .init(value: NumberDisplay.decimal(Double(habit.records), fractionDigits: 0),
                  title: String(localized: "yearReview.habit.records")),
            .init(value: NumberDisplay.decimal(Double(habit.days), fractionDigits: 0),
                  title: String(localized: "yearReview.habit.days")),
            .init(value: NumberDisplay.decimal(Double(habit.longestStreak), fractionDigits: 0),
                  title: String(localized: "yearReview.habit.streak"))
        ]
    }

    /// A month's name as it stands alone: "March", "март".
    static func monthName(_ month: Int) -> String {
        let symbols = calendar.standaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1] : ""
    }

    /// Each month's first letter, for the bars.
    static var monthInitials: [String] {
        calendar.veryShortStandaloneMonthSymbols
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        return calendar
    }
}
