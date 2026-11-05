//
//  AssetEstimateSheet.swift
//  Tenra
//
//  "Estimate from listings" (docs/domains/assets.md, plan A4): the asset's characteristics
//  first (AssetAttributesSection, what the kind needs named until it is filled), then the search
//  on Ten's server (up to a minute), then the middle of the asking prices of comparable listings
//  with its range, the value in the app, the listings themselves (a tap opens one in Safari),
//  how accurate it is and how many estimates are left this month; "Save valuation" adds it as
//  today's valuation. Used up for the month: Tenra Pro gives more (a free user), or the value by
//  hand.
//

import SwiftUI

struct AssetEstimateSheet: View {
    @State private var model: AssetEstimateViewModel
    /// The value by hand instead (the money sheet).
    let onManual: () -> Void
    /// A valuation was saved, with its value.
    let onSaved: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(PremiumManager.self) private var premium
    @State private var showingPaywall = false
    @State private var saving = false

    init(model: AssetEstimateViewModel, onManual: @escaping () -> Void, onSaved: @escaping (Double) -> Void) {
        _model = State(initialValue: model)
        self.onManual = onManual
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppSpacing.lg) {
                    if let asset = model.asset {
                        content(for: asset)
                    }
                }
                .screenPadding()
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.xl)
                .animation(AppAnimation.smooth, value: model.phase)
            }
            .navigationTitle(String(localized: "asset.estimate.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "button.close")) { dismiss() }
                }
            }
        }
        .paywallSheet(isPresented: $showingPaywall, source: .assetEstimate) {
            model.edit()
        }
        .interactiveDismissDisabled(model.phase == .searching)
    }

    @ViewBuilder
    private func content(for asset: Asset) -> some View {
        switch model.phase {
        case .details:
            details(for: asset)
        case .searching:
            searching(for: asset)
        case .result(let estimate):
            result(estimate, for: asset)
        case .failed(let failure):
            failed(failure, for: asset)
        }
    }

    // MARK: - Details

    @ViewBuilder
    private func details(for asset: Asset) -> some View {
        HeroSection(
            icon: asset.displayIcon,
            title: asset.name,
            primaryAmount: AssetValuationMath.summary(of: asset).value,
            primaryCurrency: asset.currency,
            subtitle: String(localized: "asset.estimate.current")
        ) {
            EmptyView()
        }
        Text(String(localized: "asset.estimate.intro"))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
        AssetAttributesSection(kind: asset.kind, draft: $model.draft)
        let missing = model.missing
        if !missing.isEmpty {
            InlineStatusText(
                message: String(
                    format: String(localized: "asset.estimate.needs"),
                    missing.map { group in group.map(AssetAttributesSection.title(of:)).joined(separator: " / ") }.joined(separator: ", ")
                ),
                type: .warning
            )
        }
        DSButton(
            String(localized: "asset.estimate.start"),
            systemImage: "magnifyingglass",
            fullWidth: true,
            isDisabled: !missing.isEmpty
        ) {
            Task { await model.estimate() }
        }
        manualButton
    }

    private var manualButton: some View {
        DSButton(String(localized: "asset.estimate.manual"), appearance: .flat) {
            dismiss()
            onManual()
        }
    }

    // MARK: - Searching

    @ViewBuilder
    private func searching(for asset: Asset) -> some View {
        HeroSection(icon: asset.displayIcon, title: asset.name, subtitle: String(localized: "assistant.step.valuing")) {
            EmptyView()
        }
        ProgressView()
            .controlSize(.large)
        Text(String(localized: "asset.estimate.searchingHint"))
            .font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Result

    @ViewBuilder
    private func result(_ estimate: AssetEstimate, for asset: Asset) -> some View {
        let value = model.inAssetCurrency(estimate.value, of: estimate)
        if estimate.isSufficient, let value {
            HeroSection(
                icon: asset.displayIcon,
                title: asset.name,
                primaryAmount: value,
                primaryCurrency: asset.currency,
                subtitle: Self.summaryLine(estimate)
            ) {
                EmptyView()
            }
            FormSection(footer: String(localized: "asset.estimate.asking")) {
                if let low = model.inAssetCurrency(estimate.low, of: estimate) {
                    UniversalRow(String(localized: "asset.estimate.low"), icon: "arrow.down.right", accessory: .amount(low, currency: asset.currency))
                }
                if let high = model.inAssetCurrency(estimate.high, of: estimate) {
                    UniversalRow(String(localized: "asset.estimate.high"), icon: "arrow.up.right", accessory: .amount(high, currency: asset.currency))
                }
                UniversalRow(
                    String(localized: "asset.estimate.current"),
                    icon: "house",
                    accessory: .amount(AssetValuationMath.summary(of: asset).value, currency: asset.currency)
                )
            }
            listingsSection(estimate)
            if let left = estimate.estimatesLeft {
                Text(String(format: String(localized: "asset.estimate.left"), left))
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            DSButton(
                String(localized: "asset.estimate.save"),
                systemImage: "checkmark",
                fullWidth: true,
                isLoading: saving
            ) {
                save(estimate, value: value)
            }
        } else if estimate.isSufficient, let market = estimate.marketCurrency {
            // A market in another currency the phone has no rate for yet.
            HeroSection(icon: asset.displayIcon, title: asset.name, primaryAmount: estimate.value, primaryCurrency: market, subtitle: Self.summaryLine(estimate)) {
                EmptyView()
            }
            InlineStatusText(message: String(format: String(localized: "asset.estimate.noRate"), market), type: .warning)
            listingsSection(estimate)
        } else {
            HeroSection(icon: asset.displayIcon, title: asset.name, subtitle: String(localized: "asset.estimate.insufficient")) {
                EmptyView()
            }
            listingsSection(estimate)
            DSButton(String(localized: "asset.estimate.refine"), systemImage: "slider.horizontal.3", fullWidth: true) {
                model.edit()
            }
            manualButton
        }
    }

    /// The comparables, each opening its listing in Safari.
    @ViewBuilder
    private func listingsSection(_ estimate: AssetEstimate) -> some View {
        if !estimate.listings.isEmpty {
            FormSection(header: String(localized: "asset.estimate.listings")) {
                ForEach(estimate.listings) { listing in
                    if let url = listing.url {
                        Link(destination: url) {
                            listingRow(listing)
                        }
                        // A link's label keeps the row's divider inset to itself: its icon and space.
                        .rowDividerInset(AppIconSize.lg + AppSpacing.md)
                    } else {
                        listingRow(listing)
                    }
                }
            }
        }
    }

    private func listingRow(_ listing: AssetEstimate.Listing) -> some View {
        UniversalRow(
            listing.site,
            icon: "link",
            hint: Self.details(of: listing),
            accessory: .amount(listing.price, currency: listing.currency)
        )
    }

    /// "64 m² · 2 rooms · 2012", "2019 · 110 000 km".
    static func details(of listing: AssetEstimate.Listing) -> String? {
        var parts: [String] = []
        if let size = listing.sizeM2 {
            parts.append(String(format: String(localized: "asset.estimate.squareMetres"), size.formatted(.number.precision(.fractionLength(0...1)))))
        }
        if let ares = listing.landAres {
            parts.append(String(format: String(localized: "asset.estimate.ares"), ares.formatted(.number.precision(.fractionLength(0...1)))))
        }
        if let rooms = listing.rooms {
            parts.append(String(format: String(localized: "asset.estimate.rooms"), rooms))
        }
        if let year = listing.year {
            parts.append(String(year))
        }
        if let mileage = listing.mileageKm {
            parts.append(String(format: String(localized: "asset.estimate.kilometres"), NumberDisplay.decimal(mileage, fractionDigits: 0)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Listings: 14 · Medium accuracy".
    static func summaryLine(_ estimate: AssetEstimate) -> String {
        let count = String(format: String(localized: "asset.estimate.count"), estimate.count)
        guard let accuracy = estimate.accuracy else { return count }
        let title: String
        switch accuracy {
        case .high: title = String(localized: "asset.estimate.accuracy.high")
        case .medium: title = String(localized: "asset.estimate.accuracy.medium")
        case .low: title = String(localized: "asset.estimate.accuracy.low")
        }
        return count + " · " + title
    }

    private func save(_ estimate: AssetEstimate, value: Double) {
        guard !saving else { return }
        saving = true
        Task {
            if await model.save(estimate) {
                HapticManager.success()
                onSaved(value)
                dismiss()
            }
            saving = false
        }
    }

    // MARK: - Failed

    static func message(for failure: AssetEstimateViewModel.Failure) -> String {
        switch failure {
        case .quota: return String(localized: "asset.estimate.quota")
        case .unavailable: return String(localized: "asset.estimate.unavailable")
        case .busy: return String(localized: "asset.estimate.failed")
        }
    }

    @ViewBuilder
    private func failed(_ failure: AssetEstimateViewModel.Failure, for asset: Asset) -> some View {
        HeroSection(icon: asset.displayIcon, title: asset.name, subtitle: Self.message(for: failure)) {
            EmptyView()
        }
        switch failure {
        case .quota where !premium.isPro:
            DSButton(String(localized: "asset.estimate.more"), systemImage: "crown", fullWidth: true) {
                showingPaywall = true
            }
        case .busy:
            DSButton(String(localized: "button.retry"), systemImage: "arrow.clockwise", fullWidth: true) {
                Task { await model.estimate() }
            }
        default:
            EmptyView()
        }
        manualButton
    }
}
