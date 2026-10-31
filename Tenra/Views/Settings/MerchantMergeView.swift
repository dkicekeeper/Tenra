//
//  MerchantMergeView.swift
//  Tenra
//
//  "Combine points" from a merchant's screen (MerchantDetailView): the other merchants of the
//  history to merge with it into one brand (MerchantGroupStore), points the bank names apart
//  ("ZARA MEGA", "ZARA DOSTYK PLAZA"). The ones picked stay on top, then those that start with
//  the same words, then the rest; the system search finds a merchant by the bank's text, by the
//  name the person gave it and by its brand's name. Rows as in Settings → Wallet → Merchants
//  (`UniversalRow` with the name and a line under it, DesignKit's `SelectionIndicator`). The
//  history is swept once, off the main actor (red flag #9).
//

import SwiftUI

struct MerchantMergeView: View {
    /// The screen's merchant, as the bank wrote it.
    let merchant: String

    @Environment(TransactionStore.self) private var transactionStore
    @Environment(\.dismiss) private var dismiss
    /// Settings → "Merchant logos" (on by default), as on the merchant's transaction rows.
    @AppStorage(MerchantLogoStore.enabledKey) private var showsMerchantLogos = true

    @State private var candidates: [Candidate] = []
    @State private var hasLoaded = false
    /// The merchants picked, in the order they were picked.
    @State private var picked: [String] = []
    @State private var searchText = ""
    /// Each merchant's name as its rows show it: the person's, else the clean bank's text.
    @State private var titles: [String: String] = [:]
    /// What the search reads for each merchant: the bank's text, its name and its brand's,
    /// normalized.
    @State private var searchable: [String: String] = [:]

    typealias Candidate = MerchantDirectory.Entry

    /// Rows shown at once below the suggestions: the search reaches the rest.
    private static let shownLimit = 100

    private var query: String {
        CategorySuggestionService.normalizedMerchant(searchText)
    }

    private var matching: [Candidate] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { (searchable[$0.id] ?? $0.id).contains(query) }
    }

    private func title(of candidate: Candidate) -> String {
        titles[candidate.id] ?? MerchantName.displayName(candidate.name)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasLoaded {
                    ScrollView {
                        FormSection {
                            ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                        }
                        .screenPadding()
                        .padding(.vertical, AppSpacing.md)
                    }
                } else if candidates.isEmpty {
                    EmptyState(
                        icon: "storefront",
                        title: String(localized: "merchant.merge.emptyTitle"),
                        description: String(localized: "merchant.merge.emptyMessage")
                    )
                } else {
                    list
                }
            }
            .navigationTitle(String(localized: "merchant.merge.title"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "button.close"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        merge()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .dsButton()
                    .disabled(picked.isEmpty)
                    .accessibilityLabel(String(localized: "merchant.merge.confirm"))
                }
            }
            .task { await load() }
        }
    }

    private var list: some View {
        let pickedSet = Set(picked)
        let byId = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        // The ones picked stay on top, whatever the search: what is picked is always in sight.
        let chosen = picked.compactMap { byId[$0] }
        let shown = matching.filter { !pickedSet.contains($0.id) }
        let suggested = shown.filter(\.isSuggested)
        let others = Array(shown.filter { !$0.isSuggested }.prefix(Self.shownLimit))
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if !chosen.isEmpty {
                    FormSection(header: String(localized: "merchant.merge.picked")) {
                        ForEach(chosen) { row($0) }
                    }
                }
                if !suggested.isEmpty {
                    FormSection(
                        header: String(localized: "merchant.merge.suggested"),
                        footer: String(localized: "merchant.merge.footer")
                    ) {
                        ForEach(suggested) { row($0) }
                    }
                }
                if !others.isEmpty {
                    FormSection(
                        header: String(localized: "merchant.merge.others"),
                        footer: suggested.isEmpty ? String(localized: "merchant.merge.footer") : nil
                    ) {
                        ForEach(others) { row($0) }
                    }
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
    }

    /// The merchant's logo, its name and how many payments, and whether it is picked: the row of
    /// the Wallet merchants list (MerchantCategoriesView).
    private func row(_ candidate: Candidate) -> some View {
        let isPicked = picked.contains(candidate.id)
        return Button {
            toggle(candidate.id)
        } label: {
            UniversalRow(leadingIcon: icon(for: candidate)) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text(title(of: candidate))
                        .font(AppTypography.h4)
                        .fontWeight(.medium)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)
                    Text(String(format: String(localized: "merchant.merge.operations"), candidate.count))
                        .font(AppTypography.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
            } trailing: {
                SelectionIndicator(isSelected: isPicked)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isPicked ? .isSelected : [])
        .accessibilityIdentifier("merchantMerge.row.\(candidate.id)")
        // The button keeps the row's divider inset to itself: the 44 pt tile and its space.
        .rowDividerInset(AppIconSize.Tile.sm + AppSpacing.md)
    }

    private func toggle(_ id: String) {
        HapticManager.selection()
        withAnimation(AppAnimation.smooth) {
            if let index = picked.firstIndex(of: id) {
                picked.remove(at: index)
            } else {
                picked.append(id)
            }
        }
    }

    /// The merchant's logo when it has one (and logos are on), else a shop on a pale plate.
    private func icon(for candidate: Candidate) -> IconConfig {
        if showsMerchantLogos, let logo = MerchantLogoStore.shared.iconSource(forDescription: candidate.name) {
            return .custom(
                source: logo,
                style: .circle(size: AppIconSize.Tile.sm, tint: .original, backgroundColor: AppColors.Status.neutralPale)
            )
        }
        return .custom(
            source: .sfSymbol("storefront"),
            style: .circle(
                size: AppIconSize.Tile.sm,
                tint: .monochrome(AppColors.textSecondary),
                backgroundColor: AppColors.Status.neutralPale
            )
        )
    }

    // MARK: - Loading

    private func load() async {
        guard !hasLoaded else { return }
        let all = transactionStore.transactions
        let ownKey = CategorySuggestionService.normalizedMerchant(merchant)
        let excluded = Set(MerchantGroupStore.shared.group(forKey: ownKey)?.members ?? [ownKey])
        let found = await Task.detached(priority: .userInitiated) {
            MerchantDirectory.entries(in: all, excluding: excluded, like: ownKey)
        }.value
        guard !Task.isCancelled else { return }
        // The names live on the main actor (the logo store, the brands): read once here.
        let logos = MerchantLogoStore.shared
        let groups = MerchantGroupStore.shared
        var titles: [String: String] = [:]
        var searchable: [String: String] = [:]
        for candidate in found {
            let custom = logos.customName(forDescription: candidate.name)
            let title = custom ?? MerchantName.displayName(candidate.name)
            let brand = groups.group(forKey: candidate.id).map { groups.displayName(of: $0) }
            titles[candidate.id] = title
            searchable[candidate.id] = ([candidate.id, title] + [brand].compactMap { $0 })
                .map(CategorySuggestionService.normalizedMerchant)
                .joined(separator: " | ")
        }
        self.titles = titles
        self.searchable = searchable
        candidates = found
        hasLoaded = true
    }

    // MARK: - Merge

    private func merge() {
        let pickedSet = Set(picked)
        let names = candidates.filter { pickedSet.contains($0.id) }.map(\.name)
        MerchantGroupStore.shared.merge(names, into: merchant)
        HapticManager.success()
        dismiss()
    }
}

#Preview {
    let coordinator = AppCoordinator()
    MerchantMergeView(merchant: "ZARA MEGA")
        .environment(coordinator.transactionStore)
}
