//
//  MerchantMergeView.swift
//  Tenra
//
//  "Combine points" from a merchant's screen (MerchantDetailView): the other merchants of the
//  history to merge with it into one brand (MerchantGroupStore), points the bank names apart
//  ("ZARA MEGA", "ZARA DOSTYK PLAZA"). Those that start with the same words come first; the
//  system search finds the rest. The history is swept once, off the main actor (red flag #9).
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
    @State private var picked: Set<String> = []
    @State private var searchText = ""

    typealias Candidate = MerchantDirectory.Entry

    /// Rows shown at once below the suggestions: the search reaches the rest.
    private static let shownLimit = 100

    private var query: String {
        CategorySuggestionService.normalizedMerchant(searchText)
    }

    private var matching: [Candidate] {
        guard !query.isEmpty else { return candidates }
        return candidates.filter { $0.id.contains(query) }
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
        let shown = matching
        let suggested = shown.filter(\.isSuggested)
        let others = Array(shown.filter { !$0.isSuggested }.prefix(Self.shownLimit))
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
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

    private func row(_ candidate: Candidate) -> some View {
        UniversalRow(
            MerchantLogoStore.shared.customName(forDescription: candidate.name) ?? MerchantName.displayName(candidate.name),
            leadingIcon: icon(for: candidate),
            hint: String(format: String(localized: "merchant.merge.operations"), candidate.count),
            accessory: .checkmark(isSelected: picked.contains(candidate.id)) {
                if picked.contains(candidate.id) {
                    picked.remove(candidate.id)
                } else {
                    picked.insert(candidate.id)
                }
            }
        )
        .accessibilityIdentifier("merchantMerge.row.\(candidate.id)")
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
        candidates = found
        hasLoaded = true
    }

    // MARK: - Merge

    private func merge() {
        let names = candidates.filter { picked.contains($0.id) }.map(\.name)
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
