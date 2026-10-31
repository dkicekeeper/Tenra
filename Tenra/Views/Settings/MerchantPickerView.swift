//
//  MerchantPickerView.swift
//  Tenra
//
//  The transaction form's merchant (TransactionMerchantRow, the owner's request 2026-10-31):
//  a payment entered by hand counts towards the merchant picked here, whatever its description
//  says (`MerchantGroupStore.link`). The history's merchants, the ones worth a screen first
//  (remembered, with a logo or a given name, a brand's point, linked by hand), then by how often;
//  the system search reads the bank's text, the name the person gave a merchant and its brand's
//  name, and a name nobody has yet is added as typed. The picked one stays on top; "No
//  merchant" removes a link. The history is swept once, off the main actor (red flag #9).
//

import SwiftUI

struct MerchantPickerView: View {
    /// The merchant the form shows now, as the bank wrote it (or as typed).
    let current: String?
    /// The form has a link to remove ("No merchant").
    let canClear: Bool
    /// The merchant picked, nil for none. The screen closes after it.
    let onPick: (String?) -> Void

    @Environment(TransactionStore.self) private var transactionStore
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [Entry] = []
    @State private var hasLoaded = false
    @State private var searchText = ""

    /// A merchant to pick: its key, how it is written, its name, what the search reads.
    struct Entry: Identifiable, Equatable {
        let id: String
        let merchant: String
        let title: String
        let count: Int
        let searchable: String
    }

    /// Rows shown at once: the search reaches the rest.
    private static let shownLimit = 100

    private var query: String {
        CategorySuggestionService.normalizedMerchant(searchText)
    }

    private var currentKey: String? {
        current.map(CategorySuggestionService.normalizedMerchant)
    }

    var body: some View {
        Group {
            if !hasLoaded {
                ScrollView {
                    FormSection {
                        ForEach(0..<6, id: \.self) { _ in SkeletonRow() }
                    }
                    .screenPadding()
                    .padding(.vertical, AppSpacing.md)
                }
            } else {
                list
            }
        }
        .navigationTitle(String(localized: "transaction.merchant"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .task { await load() }
    }

    private var list: some View {
        let matching = query.isEmpty ? entries : entries.filter { $0.searchable.contains(query) }
        let picked = matching.first { $0.id == currentKey }
        let others = Array(matching.filter { $0.id != currentKey }.prefix(Self.shownLimit))
        let typed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name nobody has yet: added as typed (long enough to be a merchant's key).
        let canAdd = !typed.isEmpty && MerchantCategoryMemory.key(forMerchant: typed) != nil
            && !entries.contains { $0.id == query }
        return ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if canAdd {
                    FormSection {
                        UniversalRow(
                            String(format: String(localized: "merchant.picker.add"), typed),
                            icon: "plus.circle.fill",
                            accessory: .action { pick(typed) }
                        )
                    }
                }
                if let current, canClear, query.isEmpty {
                    FormSection {
                        UniversalRow(
                            String(localized: "merchant.picker.clear"),
                            icon: "xmark.circle",
                            role: .destructive,
                            accessory: .action { pick(nil) }
                        )
                        .accessibilityHint(TransactionMerchant.title(of: current))
                    }
                }
                if let picked {
                    FormSection {
                        row(picked)
                    }
                }
                if !others.isEmpty {
                    FormSection(footer: String(localized: "merchant.picker.footer")) {
                        ForEach(others) { row($0) }
                    }
                } else if entries.isEmpty && !canAdd {
                    EmptyState(
                        icon: "storefront",
                        title: String(localized: "merchant.picker.emptyTitle"),
                        description: String(localized: "merchant.picker.emptyMessage")
                    )
                } else if matching.isEmpty && !canAdd {
                    EmptyState(
                        icon: "magnifyingglass",
                        title: String(localized: "emptyState.searchNoResults"),
                        description: String(localized: "emptyState.tryDifferentSearch")
                    )
                }
            }
            .screenPadding()
            .padding(.vertical, AppSpacing.md)
        }
    }

    private func row(_ entry: Entry) -> some View {
        MerchantChoiceRow(
            merchant: entry.merchant,
            title: entry.title,
            count: entry.count > 0 ? entry.count : nil,
            isSelected: entry.id == currentKey
        ) {
            pick(entry.merchant)
        }
        .accessibilityIdentifier("merchantPicker.row.\(entry.id)")
    }

    private func pick(_ merchant: String?) {
        HapticManager.selection()
        onPick(merchant)
        dismiss()
    }

    // MARK: - Loading

    private func load() async {
        guard !hasLoaded else { return }
        let all = transactionStore.transactions
        let found = await Task.detached(priority: .userInitiated) {
            MerchantDirectory.entries(in: all, excluding: [], like: "")
        }.value
        guard !Task.isCancelled else { return }
        // Linked by hand: a merchant typed in a form may have no description of its own.
        let groups = MerchantGroupStore.shared
        var linkedCounts: [String: (merchant: String, count: Int)] = [:]
        for merchant in groups.links.values {
            let key = CategorySuggestionService.normalizedMerchant(merchant)
            guard !key.isEmpty else { continue }
            linkedCounts[key, default: (merchant: merchant, count: 0)].count += 1
        }
        var rows: [(entry: Entry, known: Bool)] = []
        var seen = Set<String>()
        func add(key: String, merchant: String, count: Int) {
            let title = TransactionMerchant.title(of: merchant)
            let brand = groups.group(forKey: key).map { groups.displayName(of: $0) }
            let searchable = ([key, title] + [brand].compactMap { $0 })
                .map(CategorySuggestionService.normalizedMerchant)
                .joined(separator: " | ")
            let known = linkedCounts[key] != nil || TransactionMerchant.describedMerchant(merchant) != nil
            rows.append((Entry(id: key, merchant: merchant, title: title, count: count, searchable: searchable), known))
            seen.insert(key)
        }
        for entry in found {
            add(key: entry.id, merchant: entry.name, count: entry.count + (linkedCounts[entry.id]?.count ?? 0))
        }
        for (key, linked) in linkedCounts where !seen.contains(key) {
            add(key: key, merchant: linked.merchant, count: linked.count)
        }
        // The form's own merchant is listed even when nothing else names it.
        if let current, let key = currentKey, !key.isEmpty, !seen.contains(key) {
            add(key: key, merchant: current, count: 0)
        }
        entries = rows
            .sorted { lhs, rhs in
                if lhs.known != rhs.known { return lhs.known }
                if lhs.entry.count != rhs.entry.count { return lhs.entry.count > rhs.entry.count }
                return lhs.entry.id < rhs.entry.id
            }
            .map(\.entry)
        hasLoaded = true
    }
}

#Preview {
    let coordinator = AppCoordinator()
    NavigationStack {
        MerchantPickerView(current: "YANDEX.GO", canClear: true) { _ in }
    }
    .environment(coordinator.transactionStore)
}
