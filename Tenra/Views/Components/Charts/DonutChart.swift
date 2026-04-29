//
//  DonutChart.swift
//  Tenra
//
//  Phase 43 (chart merge): Unified donut (ring) chart component.
//  Replaces two structurally identical components:
//  - CategoryBreakdownChart   (multi-color sectors, compact/full modes, annotations)
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
    /// Display label (used for VoiceOver / external lists).
    let label: String
    /// 0–100 percentage, used for in-sector annotation (shown when > 10%).
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
    /// Opacity is distributed linearly between 0.95 (first item) and 0.40 (last item),
    /// regardless of count. This avoids the previous bug where the legacy formula
    /// `index × 0.15 + 0.3` saturated at 1.0 starting from index 5, making all 6th+
    /// subcategories visually identical.
    static func from(_ items: [SubcategoryBreakdownItem], baseColor: Color) -> [DonutSlice] {
        let count = items.count
        let maxOpacity = 0.95
        let minOpacity = 0.40
        return items.enumerated().map { index, item in
            let opacity: Double
            if count <= 1 {
                opacity = maxOpacity
            } else {
                let t = Double(index) / Double(count - 1)
                opacity = maxOpacity - (maxOpacity - minOpacity) * t
            }
            return DonutSlice(
                id: item.id,
                amount: item.amount,
                color: baseColor.opacity(opacity),
                label: item.name,
                percentage: item.percentage
            )
        }
    }
}

// MARK: - DonutChart

/// Unified donut (ring) chart for any `DonutSlice` series.
///
/// Supports compact sparkline mode (60 pt) and full detail mode (200 pt).
/// Appearance and update animations are built in.
///
/// Usage:
/// ```swift
/// // Category breakdown (multi-color, with overlay annotations)
/// DonutChart(slices: DonutSlice.from(items))
///
/// // Subcategory breakdown (monochromatic, no annotations)
/// DonutChart(slices: DonutSlice.from(subcategories, baseColor: color),
///            showAnnotations: false)
///
/// // Compact sparkline
/// DonutChart(slices: DonutSlice.from(items), mode: .compact)
///
/// // Full mode with center label (total amount, selected slice, etc.)
/// DonutChart(slices: DonutSlice.from(items)) {
///     VStack(spacing: 2) {
///         Text("Total").font(.caption).foregroundStyle(.secondary)
///         Text("125 000 ₸").font(.title3.weight(.semibold))
///     }
/// }
/// ```
struct DonutChart<CenterContent: View>: View {
    let slices: [DonutSlice]
    var mode: ChartDisplayMode = .full
    /// Show percentage labels inside sectors larger than 10 % (full mode only).
    var showAnnotations: Bool = true
    /// Optional content rendered in the donut hole (full mode only).
    @ViewBuilder var centerContent: () -> CenterContent

    private var isCompact: Bool { mode == .compact }
    /// Chart ring height: 60 compact / 200 full.
    private var ringHeight: CGFloat { isCompact ? 60 : 200 }

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

    /// Adaptive corner radius for sectors.
    /// Sectors smaller than 5 % get a tighter radius (4 pt) so they don't visually
    /// collapse into a circle; larger sectors keep the original 12 pt rounding.
    private func cornerRadius(for percentage: Double) -> CGFloat {
        percentage < 5 ? AppRadius.xs : AppRadius.md
    }

    // MARK: - Compact chart

    private var compactChart: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Amount", slice.amount),
                innerRadius: .ratio(0.6),
                angularInset: 1
            )
            .cornerRadius(cornerRadius(for: slice.percentage))
            .foregroundStyle(slice.color)
        }
        .animation(AppAnimation.chartUpdateAnimation, value: slices.count)
        .frame(height: 60)
        .chartLegend(.hidden)
    }

    // MARK: - Full chart

    private var fullChart: some View {
        ZStack {
            Chart(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.amount),
                    innerRadius: .ratio(0.5),
                    angularInset: 2
                )
                .cornerRadius(cornerRadius(for: slice.percentage))
                .foregroundStyle(slice.color)
                .annotation(position: .overlay) {
                    if showAnnotations && slice.percentage > 10 {
                        Text(String(format: "%.0f%%", slice.percentage))
                            .font(AppTypography.bodyEmphasis)
                            .foregroundStyle(.white)
                    }
                }
            }
            .animation(AppAnimation.chartUpdateAnimation, value: slices.count)
            .chartLegend(.hidden)

            centerContent()
                .allowsHitTesting(false)
        }
        .frame(height: ringHeight)
    }
}

// MARK: - Convenience init (no center content)

extension DonutChart where CenterContent == EmptyView {
    /// Convenience initializer for the common case of a donut without a center label.
    /// Preserves source-compatibility with existing call sites.
    init(
        slices: [DonutSlice],
        mode: ChartDisplayMode = .full,
        showAnnotations: Bool = true
    ) {
        self.slices = slices
        self.mode = mode
        self.showAnnotations = showAnnotations
        self.centerContent = { EmptyView() }
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
        showAnnotations: false
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
