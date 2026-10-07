//
//  InsightDeepDiveView.swift
//  Tenra
//
//  Phase 17: Financial Insights Feature
//  Full category detail: subcategory breakdown, spending trends, anomalies.
//  Pages through the periods of the selected granularity like the paged breakdown it
//  opens from (TabView swipe + the chevrons on the orb, PeriodPager.swift).
//

import SwiftUI
import os

struct InsightDeepDiveView: View {
    let categoryName: String
    let color: Color
    let iconSource: IconSource?
    let currency: String
    let viewModel: InsightsViewModel?
    /// Period bucket the user drilled in from — the page the drill-down opens on.
    /// `nil` = current period (non-paged breakdowns).
    let periodKey: String?
    /// Drives the comparison card's good/bad coloring: a rise is red for spending,
    /// green for income (deposit interest drills down here too).
    let isExpenseContext: Bool

    /// One page per period of the granularity the drill-down was loaded at. Empty
    /// only until the first load lands.
    @State private var pages: [CategoryDeepDivePage] = []
    /// Selected page — the TabView swipe and the chevrons both drive it.
    @State private var index = 0
    /// Granularity the pages were computed for (`.allTime` has nothing to step through).
    @State private var pagesGranularity: InsightGranularity = .month
    /// Base currency the pages were computed in (a reload follows a base-currency change).
    @State private var pagesCurrency: String?
    /// Accent color per account row, extracted from its logo (empty for subcategory rows).
    @State private var brandColorByID: [String: Color] = [:]

    private static let logger = Logger(subsystem: "Tenra", category: "CategoryDeepDive")

    // MARK: - Initializers

    /// Production initializer
    init(
        categoryName: String,
        color: Color,
        iconSource: IconSource?,
        currency: String,
        viewModel: InsightsViewModel,
        periodKey: String? = nil,
        isExpenseContext: Bool = true
    ) {
        self.categoryName = categoryName
        self.color = color
        self.iconSource = iconSource
        self.currency = currency
        self.viewModel = viewModel
        self.periodKey = periodKey
        self.isExpenseContext = isExpenseContext
    }

    /// Preview initializer — pre-populates the pages, no ViewModel needed
    fileprivate init(
        categoryName: String,
        color: Color,
        iconSource: IconSource?,
        currency: String,
        pages: [CategoryDeepDivePage],
        index: Int,
        isExpenseContext: Bool = true
    ) {
        self.categoryName = categoryName
        self.color = color
        self.iconSource = iconSource
        self.currency = currency
        self.viewModel = nil
        self.periodKey = nil
        self.isExpenseContext = isExpenseContext
        _pages = State(initialValue: pages)
        _index = State(initialValue: PeriodPaging.clamped(index, count: pages.count))
    }

    var body: some View {
        content
            // Reloads on every dimension the pages depend on (CLAUDE.md ⚠️ #12); paging
            // itself never reloads — every period is computed at once.
            .task(id: viewModel?.categoryDeepDiveKey) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if pages.isEmpty {
            // Before the first load: the header alone, never the empty state (it would
            // flash "no expenses" while the pages compute).
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    headerSection(total: 0, periodLabel: nil)
                }
            }
        } else {
            // The pager owns the screen; each page scrolls on its own, hero and orb
            // together with the rows (same layout as PagedCategoryBreakdownView). The
            // TabView takes the horizontal swipe, so it doesn't fight edge swipe-back.
            TabView(selection: $index) {
                ForEach(pages.indices, id: \.self) { i in
                    pageContent(pages[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
    }

    // MARK: - Page

    private func pageContent(_ page: CategoryDeepDivePage) -> some View {
        // Build slices once so the chart and the list draw each row in the exact same
        // color — keyed by id, not by a separate per-view index formula.
        let slices = orbSlices(for: page.items)
        let colorByID = Dictionary(slices.map { ($0.id, $0.color) }, uniquingKeysWith: { first, _ in first })
        return ScrollView {
            VStack(spacing: AppSpacing.lg) {
                headerSection(total: page.period.total, periodLabel: page.period.label)

                // Icon lives in the centre of the orb; the arrows sit on it.
                PeriodPagerChartBand(
                    index: $index,
                    count: pages.count,
                    isEmpty: page.items.isEmpty,
                    showsArrows: pagesGranularity != .allTime
                ) {
                    OrbChart(slices: slices, showLabels: true, centerIcon: iconSource)
                        .screenPadding()
                }

                if page.items.isEmpty {
                    PeriodPagerEmptyState(title: emptyTitle)
                        .frame(maxWidth: .infinity)
                } else {
                    subcategorySection(page.items, colorByID: colorByID)
                    comparisonSection(page.period)
                }
            }
        }
    }

    private var displayCurrency: String { pagesCurrency ?? currency }

    private var emptyTitle: String {
        isExpenseContext
            ? String(localized: "insights.noExpensesForPeriod")
            : String(localized: "insights.noIncomeForPeriod")
    }

    // MARK: - Header

    private func headerSection(total: Double, periodLabel: String?) -> some View {
        // Icon is hidden here — it now lives in the centre of the orb chart below.
        // Amount uses HeroSection's built-in slot (consistent with InsightDetailView);
        // the period label is what changes as the user pages.
        HeroSection(
            icon: nil,
            // Raw grouping key in, localized label out (e.g. "Loan Payment").
            title: CategoryDisplay.displayName(for: categoryName, type: isExpenseContext ? .expense : .income),
            iconTint: .monochrome(color),
            showsIcon: false,
            primaryAmount: total > 0 ? total : nil,
            primaryCurrency: displayCurrency,
            primaryAmountColor: color,
            subtitle: periodLabel
        )
    }

    // MARK: - Subcategories

    /// Orb slices for a page. Account rows (loans / deposits) override the opacity ramp
    /// with each logo's own accent color once `brandColorByID` resolves, the same
    /// treatment `heroAccentGlow` applies.
    private func orbSlices(for items: [SubcategoryBreakdownItem]) -> [DonutSlice] {
        DonutSlice.from(items, baseColor: color).map { slice in
            guard let brand = brandColorByID[slice.id] else { return slice }
            return DonutSlice(id: slice.id, amount: slice.amount, color: brand,
                              label: slice.label, percentage: slice.percentage)
        }
    }

    private func subcategorySection(_ items: [SubcategoryBreakdownItem], colorByID: [String: Color]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            ForEach(items) { item in
                HStack (alignment:.top){
                    // Entity rows (a loan, a deposit) show the account's own logo;
                    // plain subcategory rows keep the slice-colored dot.
                    if let itemIcon = item.iconSource {
                        IconView(source: itemIcon, size: AppIconSize.Tile.sm)
                    } else {
                        Circle()
                            .fill(colorByID[item.id] ?? color)
                            .frame(width: 24, height: 24)
                    }

                    Text(item.name)
                        .font(AppTypography.body)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    VStack(alignment: .trailing, spacing: AppSpacing.xxs) {
                        FormattedAmountText(amount: item.amount, currency: displayCurrency, color: AppColors.textPrimary)
                        Text(String(format: "%.1f%%", item.percentage))
                            .font(AppTypography.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .screenPadding()
    }

    /// Resolves each account row's accent color from its logo (in-memory cached, so
    /// usually instant), across every page. Mirrors `WealthOrbSection` in
    /// InsightDetailView — the builder can't do this itself: it runs nonisolated with
    /// no access to logo images.
    private func resolveBrandColors() async {
        var resolved: [String: Color] = [:]
        var seen = Set<String>()
        for item in pages.flatMap({ $0.items }) {
            guard !seen.contains(item.id) else { continue }
            seen.insert(item.id)
            guard case .brandService(let brand) = item.iconSource,
                  let color = await DominantColorExtractor.accentColor(forBrand: brand) else { continue }
            resolved[item.id] = color
        }
        guard resolved != brandColorByID else { return }
        withAnimation(AppAnimation.gentleSpring) {
            brandColorByID = resolved
        }
    }

    // MARK: - Comparison

    /// This period against the one before it. No card for `.allTime` — one bucket,
    /// no previous period.
    @ViewBuilder
    private func comparisonSection(_ period: CategoryDeepDivePeriod) -> some View {
        if let previousLabel = period.previousLabel {
            PeriodComparisonCard(
                currentLabel: period.label,
                currentAmount: period.total,
                previousLabel: previousLabel,
                previousAmount: period.previousTotal,
                currency: displayCurrency,
                isExpenseContext: isExpenseContext
            )
            .screenPadding()
        }
    }

    // MARK: - Data Loading

    /// Every period of the selected granularity in one off-main pass (the view model
    /// detaches it), so paging is instant. `.task(id:)` cancels a superseded reload.
    @MainActor
    private func reload() async {
        guard let viewModel else { return } // Preview mode — pages pre-populated
        Self.logger.debug("🔍 [CategoryDeepDive] LOAD — category='\(categoryName, privacy: .public)' gran='\(viewModel.currentGranularity.rawValue, privacy: .public)' period='\(periodKey ?? "current", privacy: .public)'")

        let result = await viewModel.categoryDeepDivePages(
            categoryName: categoryName,
            isExpenseContext: isExpenseContext
        )
        guard !Task.isCancelled else { return }

        // A reload keeps the period on screen; the first load opens on the period the
        // user drilled in from (the current one when the breakdown wasn't paged).
        let selectedKey: String? = pages.indices.contains(index) ? pages[index].id : periodKey
        index = PeriodPaging.index(
            of: selectedKey,
            in: result.pages.map { $0.period.id },
            fallbackKey: result.granularity.currentPeriodKey
        )
        pages = result.pages
        pagesGranularity = result.granularity
        pagesCurrency = result.currency

        let page: CategoryDeepDivePage? = pages.indices.contains(index) ? pages[index] : nil
        Self.logger.debug("🔍 [CategoryDeepDive] LOADED — pages=\(pages.count), index=\(index), rows=\(page?.items.count ?? 0), total=\(String(format: "%.0f", page?.period.total ?? 0), privacy: .public)")

        await resolveBrandColors()
    }
}

// MARK: - Previews

#Preview("Insight Deep Dive — Food") {
    let pages = CategoryDeepDivePage.mockPages()
    return NavigationStack {
        InsightDeepDiveView(
            categoryName: "Food",
            color: AppColors.warning,
            iconSource: .sfSymbol("fork.knife"),
            currency: "KZT",
            pages: pages,
            index: pages.count - 1
        )
    }
}
