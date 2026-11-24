//
//  YearReviewView.swift
//  Tenra
//
//  The year in review (docs/plan-release-1.9.md §3): a calendar year in Tenra, page by page, on
//  the whole screen, like stories. Swiped or moved on with Next; a page with nothing to show is
//  left out (YearReviewPage). Each page has its own aurora (YearReviewPalette), and the colours
//  flow from one page into the next as the finger moves (YearReviewAurora reads the paging
//  scroll's progress). A page's content rises in the first time it comes up; the finale throws
//  confetti once. The figures come from YearReviewBuilder through YearReviewLoader, so they
//  follow Analytics' money rules; this file only lays them out, from DesignKit's parts.
//
//  YearReviewScreen loads the review for a year and shows it: what Analytics' card and Ten's
//  message open. The last page shares a picture of the year (YearReviewShareCard), without
//  amounts unless the person turns them on.
//

import SwiftUI
import UIKit

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
                    series: coordinator.transactionStore.recurringSeries,
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
    /// The person's series: the subscriptions' names and logos.
    let series: [RecurringSeries]
    /// What Ten wears today (TenWardrobeStore).
    let accessory: CreatureAccessory?

    @Environment(\.dismiss) private var dismiss
    /// The page in front: the paging scroll's position.
    @State private var current: YearReviewPage?
    /// The pages that came up once: their content rose in and stays.
    @State private var shown: Set<YearReviewPage>
    /// How far the pages are swiped, for the aurora only (read by YearReviewAurora alone, so a
    /// swipe never redraws the pages).
    @State private var pager: YearReviewPager
    @State private var sharing = false
    @State private var confetti = 0
    /// The share picture's amounts (plan §3: off by default, the person's figures stay theirs).
    @AppStorage(YearReviewShareCard.amountsKey) private var shareAmounts = false
    /// Settings → "Merchant logos", as on the merchants' own screens.
    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    /// `initialPage`: the page it opens on (the mockups show each one).
    init(
        review: YearReview,
        categories: [CustomCategory] = [],
        series: [RecurringSeries] = [],
        accessory: CreatureAccessory? = nil,
        initialPage: Int = 0
    ) {
        self.review = review
        self.categories = categories
        self.series = series
        self.accessory = accessory
        let pages = YearReviewPage.pages(for: review)
        let start = pages.indices.contains(initialPage) ? initialPage : 0
        _current = State(initialValue: pages.isEmpty ? nil : pages[start])
        _shown = State(initialValue: pages.isEmpty ? [] : [pages[start]])
        _pager = State(initialValue: YearReviewPager(progress: Double(start)))
    }

    var body: some View {
        let pages = YearReviewPage.pages(for: review)
        let index = current.flatMap { pages.firstIndex(of: $0) } ?? 0
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(pages) { kind in
                        YearReviewPageContainer(isShown: shown.contains(kind)) {
                            pageContent(kind)
                        }
                        .containerRelativeFrame(.horizontal)
                        .id(kind)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $current)
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Double.self) { geometry in
                geometry.contentOffset.x / max(geometry.containerSize.width, 1)
            } action: { _, progress in
                pager.progress = progress
            }
            .onChange(of: current) { _, page in
                guard let page, !shown.contains(page) else { return }
                if page == .finale { confetti += 1 }
                withAnimation(AppAnimation.contentSpring) { _ = shown.insert(page) }
            }
            .background {
                YearReviewAurora(palettes: pages.map(palette(for:)), pager: pager)
            }
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: AppSpacing.md) {
                    YearReviewPageDots(count: pages.count, current: index)
                        .fixedSize()
                    bottomButton(isLast: index >= pages.count - 1, next: pages.indices.contains(index + 1) ? pages[index + 1] : nil)
                }
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

    @ViewBuilder
    private func bottomButton(isLast: Bool, next: YearReviewPage?) -> some View {
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
                guard let next else { return }
                withAnimation(AppAnimation.contentSpring) { current = next }
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

    /// A page's title: large, on its own, nothing over it.
    private func title(_ text: String, centered: Bool = false) -> some View {
        Text(text)
            .font(AppTypography.h1)
            .foregroundStyle(AppColors.textPrimary)
            .multilineTextAlignment(centered ? .center : .leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private var cover: some View {
        VStack(spacing: AppSpacing.lg) {
            ParticleCreature(mood: .happy, accessory: accessory)
                .frame(width: YearReviewMetrics.creatureSize, height: YearReviewMetrics.creatureSize)
                .accessibilityHidden(true)
            Text(verbatim: String(review.year))
                .font(AppTypography.display)
                .foregroundStyle(AppColors.textPrimary)
                .monospacedDigit()
            title(String(localized: "yearReview.cover.title"), centered: true)
            Text(String(localized: "yearReview.cover.text"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var money: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                title(String(localized: "yearReview.money.title"))
                LiveAmountText(
                    amount: review.expenses,
                    currency: review.currency,
                    fontSize: AppTypography.h1,
                    fontWeight: .bold
                )
            }
            if let rate = review.savingsRate, rate > 0 {
                HStack(spacing: AppSpacing.lg) {
                    ZStack {
                        ProgressRing(
                            progress: rate,
                            size: YearReviewMetrics.ringSize,
                            lineWidth: YearReviewMetrics.ringLine,
                            overrideColor: AppColors.success,
                            showsTrack: true
                        )
                        Text(NumberDisplay.percent(rate * 100))
                            .font(AppTypography.h3)
                            .foregroundStyle(AppColors.textPrimary)
                            .monospacedDigit()
                    }
                    Text(String(localized: "yearReview.money.kept"))
                        .font(AppTypography.bodyEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
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
            }
        }
    }

    private var months: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            title(String(localized: "yearReview.months.title"))
            MiniBars(
                values: review.monthlyExpenses,
                highlighted: review.busiestMonth.map { $0 - 1 },
                color: AppColors.accent,
                labels: Array(YearReviewText.monthInitials.prefix(review.monthlyExpenses.count)),
                height: YearReviewMetrics.barsHeight
            )
            .frame(maxWidth: .infinity)
            .cardContentPadding()
            .cardStyle()
            .accessibilityHidden(true)
            FormSection {
                if let busiest = review.busiestMonth {
                    AmountRow(
                        YearReviewText.monthName(busiest),
                        subtitle: String(localized: "yearReview.months.busiest"),
                        leading: .tinted(.sfSymbol("flame.fill"), AppColors.warning),
                        value: .amount(review.monthlyExpenses[busiest - 1]),
                        currency: review.currency
                    )
                }
                if let calmest = review.calmestMonth {
                    AmountRow(
                        YearReviewText.monthName(calmest),
                        subtitle: String(localized: "yearReview.months.calmest"),
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
            title(String(localized: "yearReview.categories.title"))
            OrbChart(
                slices: review.topCategories.map { category in
                    DonutSlice(
                        id: category.key,
                        amount: category.amount,
                        color: categoryStyle(category.key).color,
                        label: CategoryDisplay.displayName(for: category.key, type: .expense),
                        percentage: category.share * 100
                    )
                },
                size: YearReviewMetrics.orbSize
            )
            .frame(maxWidth: .infinity)
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
            title(String(localized: "yearReview.merchants.title"))
            PackedCircleIcons(
                items: review.topMerchants.map { merchant in
                    let style = categoryStyle(merchant.usualCategory)
                    return PackedCircleItem(
                        id: merchant.key,
                        iconSource: merchantLogo(merchant) ?? style.icon,
                        amount: merchant.amount,
                        tint: style.color
                    )
                },
                maxVisible: YearReviewBuilder.topMerchantCount,
                containerWidth: YearReviewMetrics.circlesWidth
            )
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            FormSection {
                ForEach(review.topMerchants) { merchant in
                    let style = categoryStyle(merchant.usualCategory)
                    AmountRow(
                        merchant.name,
                        subtitle: YearReviewText.visits(merchant.visits),
                        leading: merchantLogo(merchant).map { AmountRow.Leading.icon($0) } ?? .tinted(style.icon, style.color),
                        value: .amount(merchant.amount),
                        currency: review.currency
                    )
                }
            }
        }
    }

    private var subscriptions: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                title(String(localized: "yearReview.subscriptions.title"))
                LiveAmountText(
                    amount: review.subscriptionsTotal,
                    currency: review.currency,
                    fontSize: AppTypography.h1,
                    fontWeight: .bold
                )
                Text(YearReviewText.subscriptions(review.subscriptionsCount))
                    .font(AppTypography.body)
                    .foregroundStyle(AppColors.textSecondary)
            }
            PackedCircleIcons(
                items: review.subscriptions.map { subscription in
                    let found = series.first { $0.id == subscription.seriesId }
                    let style = categoryStyle(found?.category ?? "")
                    return PackedCircleItem(
                        id: subscription.seriesId,
                        iconSource: found?.iconSource ?? style.icon,
                        amount: subscription.amount,
                        tint: style.color
                    )
                },
                maxVisible: YearReviewMetrics.subscriptionLogos,
                containerWidth: YearReviewMetrics.circlesWidth,
                style: .shelf
            )
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            if !review.monthlyExpenses.isEmpty {
                FormSection {
                    AmountRow(
                        String(localized: "yearReview.subscriptions.perMonth"),
                        leading: .tinted(.sfSymbol("calendar"), AppColors.accent),
                        value: .amount(review.subscriptionsTotal / Double(review.monthlyExpenses.count)),
                        currency: review.currency
                    )
                }
            }
        }
    }

    private var habit: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xl) {
            title(String(localized: "yearReview.habit.title"))
            StatsStrip(items: YearReviewText.habitStats(review.habit))
            CalendarHeatmap(
                values: YearReviewText.heatmapValues(review.recordsByDay),
                weeks: YearReviewText.heatmapWeeks(review.year),
                color: AppColors.warning,
                valueFormat: .compact,
                today: YearReviewText.heatmapEnd(review.year),
                calendar: AppCalendar.current
            )
            .cardContentPadding()
            .cardStyle()
            .accessibilityHidden(true)
            Text(String(localized: "yearReview.habit.text"))
                .font(AppTypography.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    @ViewBuilder
    private var biggest: some View {
        if let biggest = review.biggestExpense {
            let style = categoryStyle(biggest.categoryKey)
            VStack(spacing: AppSpacing.xl) {
                title(String(localized: "yearReview.biggest.title"), centered: true)
                HeroSection(
                    icon: style.icon,
                    title: biggest.title,
                    iconTint: .monochrome(style.color),
                    primaryAmount: biggest.amount,
                    primaryCurrency: review.currency,
                    primaryAmountColor: AppColors.textPrimary,
                    subtitle: FastDateParser.date(from: biggest.date).map { DateFormatters.day($0, includeYear: false) }
                )
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var finale: some View {
        VStack(spacing: AppSpacing.xl) {
            ParticleCreature(mood: .happy, accessory: accessory)
                .frame(width: YearReviewMetrics.creatureSize, height: YearReviewMetrics.creatureSize)
                .celebration(trigger: confetti, colors: YearReviewPalette.finale.map(\.color))
                .accessibilityHidden(true)
            VStack(spacing: AppSpacing.md) {
                title(String(format: String(localized: "yearReview.finale.title"), String(review.year + 1)), centered: true)
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

    // MARK: - Colours and icons

    /// Each page's aurora: a hue family of its own, the categories' colours on theirs and the
    /// biggest expense's category on its page.
    private func palette(for page: YearReviewPage) -> [AuroraBackground.Spot] {
        switch page {
        case .cover: return YearReviewPalette.spots(YearReviewPalette.cover)
        case .money: return YearReviewPalette.spots(YearReviewPalette.money)
        case .months: return YearReviewPalette.spots(YearReviewPalette.months)
        case .categories:
            let top = review.topCategories.prefix(YearReviewPalette.maxSpots)
            let largest = top.map(\.share).max() ?? 1
            guard !top.isEmpty, largest > 0 else { return YearReviewPalette.spots(YearReviewPalette.cover) }
            return top.map { AuroraBackground.Spot(color: categoryStyle($0.key).color, weight: $0.share / largest) }
        case .merchants: return YearReviewPalette.spots(YearReviewPalette.merchants)
        case .subscriptions: return YearReviewPalette.spots(YearReviewPalette.subscriptions)
        case .habit: return YearReviewPalette.spots(YearReviewPalette.habit)
        case .biggest:
            let color = review.biggestExpense.map { categoryStyle($0.categoryKey).color } ?? AppColors.accent
            return [AuroraBackground.Spot(color: color, weight: 1)] + YearReviewPalette.spots(YearReviewPalette.biggest, from: 0.6)
        case .finale: return YearReviewPalette.spots(YearReviewPalette.finale)
        }
    }

    private func merchantLogo(_ merchant: YearReview.MerchantTotal) -> IconSource? {
        guard showsMerchantLogos else { return nil }
        return MerchantLogoStore.shared.iconSource(forDescription: merchant.description)
    }

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

// MARK: - Page

/// One page: its own vertical scroll (large text), the content in the middle of the screen when
/// it is shorter, rising in the first time the page comes up.
private struct YearReviewPageContainer<Content: View>: View {
    let isShown: Bool
    @ViewBuilder let content: () -> Content

    /// The scroll's height inside its insets: the content is centred in it.
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            ZStack {
                if isShown {
                    content()
                        .screenPadding()
                        .padding(.vertical, AppSpacing.xl)
                        .transition(.riseIn)
                }
            }
            .frame(maxWidth: .infinity, minHeight: visibleHeight)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            visibleHeight = max(height, 0)
        }
    }
}

/// The system's page dots, under the pages.
private struct YearReviewPageDots: UIViewRepresentable {
    let count: Int
    let current: Int

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.isUserInteractionEnabled = false
        control.hidesForSinglePage = true
        control.backgroundStyle = .minimal
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        control.numberOfPages = count
        control.currentPage = current
        control.currentPageIndicatorTintColor = UIColor(AppColors.textPrimary)
        control.pageIndicatorTintColor = UIColor(AppColors.textTertiary)
    }
}

// MARK: - Aurora

/// How far the pages are swiped: 0 on the first, 1.5 halfway from the second to the third.
@Observable
final class YearReviewPager {
    var progress: Double

    init(progress: Double = 0) {
        self.progress = progress
    }
}

/// The aurora behind the pages: the page under the finger in full, the next one over it as far as
/// the swipe has gone, so the colours flow with the finger. Only these two are drawn; each is
/// still, so the glass over it never redraws for a drift.
private struct YearReviewAurora: View {
    let palettes: [[AuroraBackground.Spot]]
    let pager: YearReviewPager

    var body: some View {
        let last = max(palettes.count - 1, 0)
        let progress = min(max(pager.progress, 0), Double(last))
        let lower = Int(progress.rounded(.down))
        let upper = min(lower + 1, last)
        let fraction = progress - Double(lower)
        ZStack {
            if palettes.indices.contains(lower) {
                ForEach(lower == upper ? [lower] : [lower, upper], id: \.self) { index in
                    AuroraBackground(palettes[index], intensity: YearReviewMetrics.auroraIntensity)
                        .opacity(index == lower ? 1 : fraction)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Each page's hues (DesignKit's named palette), heaviest first.
enum YearReviewPalette {
    static let cover: [AppColors.Palette] = [.violet, .pink, .cyan]
    static let money: [AppColors.Palette] = [.emerald, .teal, .green]
    static let months: [AppColors.Palette] = [.orange, .pink, .violet]
    static let merchants: [AppColors.Palette] = [.blue, .cyan, .indigo]
    static let subscriptions: [AppColors.Palette] = [.purple, .indigo, .pink]
    static let habit: [AppColors.Palette] = [.orange, .red, .ochre]
    static let biggest: [AppColors.Palette] = [.violet, .slate]
    static let finale: [AppColors.Palette] = [.pink, .violet, .cyan, .orange]
    /// The categories' page: up to as many of the top categories.
    static let maxSpots = 4

    /// The hues as spots, each a fifth lighter than the one before, from `from`.
    static func spots(_ hues: [AppColors.Palette], from weight: Double = 1) -> [AuroraBackground.Spot] {
        hues.enumerated().map { offset, hue in
            .init(color: hue.color, weight: max(weight - Double(offset) * 0.2, 0.2))
        }
    }
}

enum YearReviewMetrics {
    /// Ten on the first and the last page.
    static let creatureSize: CGFloat = 200
    /// The months' bars.
    static let barsHeight: CGFloat = 180
    /// The savings ring.
    static let ringSize: CGFloat = 112
    static let ringLine: CGFloat = 12
    /// The categories' orb.
    static let orbSize: CGFloat = 240
    /// The merchants' marbles and the subscriptions' shelf.
    static let circlesWidth: CGFloat = 240
    static let subscriptionLogos = 5
    static let auroraIntensity: Double = 0.55
}

/// The review's words that are not a plain key: plurals, months, the habit's counters.
enum YearReviewText {
    /// "12 visits".
    static func visits(_ count: Int) -> String {
        String(format: NSLocalizedString("yearReview.merchants.visits", comment: "Visits to a merchant in the year"), count)
    }

    /// "4 subscriptions".
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

    /// The records per day as the calendar takes them.
    static func heatmapValues(_ recordsByDay: [String: Int]) -> [Date: Double] {
        var values: [Date: Double] = [:]
        for (day, count) in recordsByDay {
            if let date = FastDateParser.date(from: day) { values[date] = Double(count) }
        }
        return values
    }

    /// The calendar's last day: today in the year that is running, 31 December after it.
    static func heatmapEnd(_ year: Int, now: Date = Date()) -> Date {
        let lastDay = FastDateParser.date(from: String(format: "%04d-12-31", year)) ?? now
        return min(now, lastDay)
    }

    /// Weeks from 1 January to the calendar's last day.
    static func heatmapWeeks(_ year: Int, now: Date = Date()) -> Int {
        guard let first = FastDateParser.date(from: String(format: "%04d-01-01", year)) else { return 26 }
        let days = FastDateParser.calendar.dateComponents([.day], from: first, to: heatmapEnd(year, now: now)).day ?? 0
        return min(max(days / 7 + 2, 1), 54)
    }

    /// A month's name as it stands alone, as a title: "March", "Март".
    static func monthName(_ month: Int) -> String {
        let symbols = calendar.standaloneMonthSymbols
        return symbols.indices.contains(month - 1) ? symbols[month - 1].localizedCapitalized : ""
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
