//
//  DonutChart.swift
//  AIFinanceManager
//
//  Phase 43 (chart merge): Unified donut (ring) chart component.
//  Replaces two structurally identical components:
//  - CategoryBreakdownChart   (multi-color sectors, compact/full modes, annotations, legend)
//  - SubcategoryBreakdownChart (monochromatic opacity-stepped sectors)
//
//  Behavioral differences are resolved at the call site via `DonutSlice` factory methods.
//

import SwiftUI
import Charts

// MARK: - DonutSlice

/// A single sector in a `DonutChart`.
struct DonutSlice: Identifiable {
    let id: String
    let amount: Double
    let color: Color
    /// Legend row label.
    let label: String
    /// 0–100 percentage, used for in-sector annotation (shown when > 10%) and legend text.
    let percentage: Double
}

extension DonutSlice {
    /// Converts `CategoryBreakdownItem` array to slices.
    ///
    /// When the input exceeds 6 items the tail is collapsed into a single "Other" slice
    /// (mirrors the previous `CategoryBreakdownChart.displayItems` logic).
    static func from(_ items: [CategoryBreakdownItem]) -> [DonutSlice] {
        guard items.count > 6 else {
            return items.map { DonutSlice(id: $0.id, amount: $0.amount, color: $0.color,
                                          label: $0.categoryName, percentage: $0.percentage) }
        }
        let top5 = Array(items.prefix(5))
        let rest  = items.dropFirst(5)
        let other = DonutSlice(
            id: "other",
            amount: rest.reduce(0) { $0 + $1.amount },
            color: AppColors.textTertiary,
            label: String(localized: "insights.other"),
            percentage: rest.reduce(0) { $0 + $1.percentage }
        )
        let top5Slices = top5.map { DonutSlice(id: $0.id, amount: $0.amount, color: $0.color,
                                               label: $0.categoryName, percentage: $0.percentage) }
        return top5Slices + [other]
    }

    /// Converts `SubcategoryBreakdownItem` array to opacity-stepped slices of `baseColor`.
    ///
    /// Opacity formula: `index × 0.15 + 0.3` (matches previous `SubcategoryBreakdownChart` logic).
    static func from(_ items: [SubcategoryBreakdownItem], baseColor: Color) -> [DonutSlice] {
        items.enumerated().map { index, item in
            DonutSlice(
                id: item.id,
                amount: item.amount,
                color: baseColor.opacity(Double(index) * 0.15 + 0.3),
                label: item.name,
                percentage: item.percentage
            )
        }
    }
}

// MARK: - DonutChart

/// Unified donut (ring) chart for any `DonutSlice` series.
///
/// Supports compact sparkline mode (60 pt, no annotations or legend) and full detail
/// mode (200 pt or 240 pt with legend).  Appearance and update animations are built in.
///
/// Usage:
/// ```swift
/// // Category breakdown (multi-color, with annotations + legend)
/// DonutChart(slices: DonutSlice.from(items))
///
/// // Subcategory breakdown (monochromatic, no annotations or legend)
/// DonutChart(slices: DonutSlice.from(subcategories, baseColor: color),
///            showAnnotations: false, showLegend: false)
///
/// // Compact sparkline
/// DonutChart(slices: DonutSlice.from(items), mode: .compact)
/// ```
struct DonutChart: View {
    let slices: [DonutSlice]
    var mode: ChartDisplayMode = .full
    /// Show percentage labels inside sectors larger than 10 % (full mode only).
    var showAnnotations: Bool = true
    /// Show 2-column grid legend below the chart (full mode only).
    var showLegend: Bool = true

    private var isCompact: Bool { mode == .compact }
    /// Chart ring height: 60 compact / 200 full-no-legend / 240 full-with-legend.
    private var ringHeight: CGFloat { isCompact ? 60 : (showLegend ? 240 : 200) }

    // MARK: Body

    var body: some View {
        chartContent
            .chartAppear()
    }

    @ViewBuilder private var chartContent: some View {
        if isCompact {
            compactChart
        } else {
            fullChart
        }
    }

    // MARK: - Compact chart

    private var compactChart: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.amount),
                innerRadius: .ratio(0.6),
                angularInset: 1
            )
            .cornerRadius(AppRadius.md)
            .shadow(color: slice.color.opacity(0.5), radius: 4)
            .foregroundStyle(
                        LinearGradient(
                            colors: [
                                slice.color.opacity(1),
                                slice.color.opacity(0.5)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
        }
        .animation(AppAnimation.chartUpdateAnimation, value: slices.count)
        .frame(height: 60)
        .chartLegend(.hidden)
    }

    // MARK: - Full chart

    private var fullChart: some View {
        VStack(spacing: AppSpacing.lg) {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.amount),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .cornerRadius(AppRadius.md)
                .shadow(color: slice.color.opacity(0.7), radius: 8)
                .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    slice.color.opacity(1),
                                    slice.color.opacity(0.5)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                .annotation(position: .overlay) {
                    if showAnnotations && slice.percentage > 10 {
                        Text(String(format: "%.0f%%", slice.percentage))
                            .font(AppTypography.captionEmphasis)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                    }
                }
            }
            .animation(AppAnimation.chartUpdateAnimation, value: slices.count)
            .frame(height: ringHeight)
            .chartLegend(.hidden)

            if showLegend {
                legend
            }
        }
    }

    // MARK: - Legend

    private var legend: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppSpacing.sm
        ) {
            ForEach(slices) { slice in
                HStack(spacing: AppSpacing.xs) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 8, height: 8)
                    Text(slice.label)
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.0f%%", slice.percentage))
                        .font(AppTypography.captionEmphasis)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Full — category breakdown") {
    DonutChart(slices: DonutSlice.from(CategoryBreakdownItem.mockItems()))
        .screenPadding()
        .padding(.vertical, AppSpacing.md)
}

#Preview("Full — subcategory (monochromatic)") {
    let items: [SubcategoryBreakdownItem] = [
        SubcategoryBreakdownItem(id: "restaurants", name: "Restaurants", amount: 42_000, percentage: 49),
        SubcategoryBreakdownItem(id: "groceries",   name: "Groceries",   amount: 28_000, percentage: 33),
        SubcategoryBreakdownItem(id: "delivery",    name: "Delivery",    amount: 15_000, percentage: 18)
    ]
    DonutChart(
        slices: DonutSlice.from(items, baseColor: AppColors.warning),
        showAnnotations: false,
        showLegend: false
    )
    .screenPadding()
    .padding(.vertical, AppSpacing.md)
}

#Preview("Compact") {
    VStack(spacing: AppSpacing.md) {
        DonutChart(slices: DonutSlice.from(CategoryBreakdownItem.mockItems()), mode: .compact)
    }
    .screenPadding()
    .frame(height: 100)
}
