//
//  DesignKitBridge.swift
//  Tenra
//
//  Tenra's design system lives in the DesignKit package (github.com/dkicekeeper/DesignKit),
//  shared with Dalada. This file is the seam between the two:
//
//  - Re-exports DesignKit's modules, so every Tenra file (and TenraTests via
//    `@testable import Tenra`) sees AppColors, UniversalRow, … without per-file imports.
//  - Wires DesignKit's host hooks to Tenra services (brand logos, FX).
//  - Keeps the Tenra-model adapters DesignKit cannot know about (custom category colours,
//    logo registry domains, breakdown slices, the stat-card sparkline).
//
//  Changing a shared component = a DesignKit PR (see DesignKit's CLAUDE.md), then a
//  version bump here in the project's package dependency.
//

@_exported import DesignTokens
@_exported import DesignSupport
@_exported import DesignComponents
import SwiftUI

enum DesignKitBridge {
    /// Call once from `TenraApp.init()`, before any view renders.
    static func configure() {
        // Inter comes from DesignKit's bundle (Tenra's own copy and UIAppFonts were removed).
        // The accent stays DesignKit's default, system indigo (= Tenra's AccentColor).
        DesignKitFonts.registerIfNeeded()
        DesignKitLogoLoader.loader = { brandName in
            await LogoService.shared.logoImage(brandName: brandName)
        }
        DesignKitCurrencyConverter.convert = { amount, from, to in
            await CurrencyConverter.convert(amount: amount, from: from, to: to)
        }
    }
}

// MARK: - Category colours with Tenra's custom categories

extension CategoryColors {
    /// Custom category colour when the user set one, else DesignKit's palette colour.
    /// Legacy O(N_cat) path — still used in cold/preview contexts. Prefer the
    /// store-backed overload below on the hot path.
    nonisolated static func hexColor(for category: String, opacity: Double = 1.0, customCategories: [CustomCategory]) -> Color {
        if let custom = customCategories.first(where: { $0.name.lowercased() == category.lowercased() }) {
            return custom.color.opacity(opacity)
        }
        return hexColor(for: category, opacity: opacity)
    }

    /// O(1) — looks up the custom category through TransactionStore.categoryIdByName
    /// and falls back to the deterministic palette by name hash.
    @MainActor
    static func hexColor(for category: String, opacity: Double = 1.0, store: TransactionStore) -> Color {
        if let id = store.categoryIdByName[category.lowercased()],
           let custom = store.categoryById[id] {
            return custom.color.opacity(opacity)
        }
        return hexColor(for: category, opacity: opacity)
    }
}

// MARK: - Brand logo registry

extension IconSource {
    /// Registry domain of a brand logo ("kaspi.kz"), resolving a stored alias or
    /// display name. nil for SF Symbols.
    var brandDomain: String? {
        guard case .brandService(let name) = self else { return nil }
        return ServiceLogoRegistry.resolveDomain(from: name).lowercased()
    }
}

// MARK: - Breakdown slices

extension DonutSlice {
    /// Category breakdown → ring slices, slivers folded into "Other"
    /// (DesignKit's `foldingSlivers`). Assumes `items` is ordered by amount descending.
    static func from(_ items: [CategoryBreakdownItem]) -> [DonutSlice] {
        foldingSlivers(items.map {
            DonutSlice(id: $0.id, amount: $0.amount, color: $0.color,
                       label: $0.categoryName, percentage: $0.percentage)
        })
    }

    /// Subcategory breakdown → opacity-stepped slices of `baseColor`.
    static func from(_ items: [SubcategoryBreakdownItem], baseColor: Color) -> [DonutSlice] {
        opacityStepped(items.map {
            DonutSlice(id: $0.id, amount: $0.amount, color: baseColor,
                       label: $0.name, percentage: $0.percentage)
        }, baseColor: baseColor)
    }
}

// MARK: - Stat card sparkline

/// Trend footer of `InsightsStatCard`: the recent tail of a `PeriodDataPoint` series.
struct InsightsStatTrend: View {
    /// Pass the full series — the card plots only its tail (see `periodLimit`).
    let points: [PeriodDataPoint]
    /// Which series the sparkline plots. `nil` hides it.
    let series: PeriodChartSeries?

    /// Periods drawn in the sparkline. At ~150pt wide a full 24-month window collapses
    /// into noise; the recent tail is what "is this normal for me?" actually asks about.
    /// The full history stays one tap away in the detail screen.
    private static let periodLimit = 6

    var body: some View {
        let visible = Array(points.suffix(Self.periodLimit))
        if let series, visible.count >= 2 {
            MiniSparkline(
                dataPoints: visible,
                series: series,
                lineWidth: 1.2,
                height: 24,
                endDotRadius: 2.5
            )
            .padding(.top, AppSpacing.xxs)
            .accessibilityHidden(true)
        }
    }
}

extension InsightsStatCard where Trend == InsightsStatTrend {
    /// Stat card with the trend behind the number — the sparkline answers "is this normal
    /// for me?" without a tap. Needs ≥2 points to show anything.
    init(
        title: String,
        amount: Double,
        currency: String,
        color: Color = AppColors.textPrimary,
        previous: Double? = nil,
        upIsGood: Bool = true,
        trendPoints: [PeriodDataPoint],
        trendSeries: PeriodChartSeries?
    ) {
        self.init(title: title, amount: amount, currency: currency, color: color,
                  previous: previous, upIsGood: upIsGood) {
            InsightsStatTrend(points: trendPoints, series: trendSeries)
        }
    }
}
