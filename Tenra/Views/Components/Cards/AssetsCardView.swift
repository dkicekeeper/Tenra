//
//  AssetsCardView.swift
//  Tenra
//
//  The Assets card in Finances (docs/domains/assets.md), right after Deposits: what the held
//  assets are worth at the person's share, in the base currency (RedactableAmount: hidden with
//  the other amounts, a skeleton until the store loads), how many there are, and their icons
//  on the shelf like every Finances card, sized by value. Adding an asset is Tenra Pro; the
//  card shows them either way.
//

import SwiftUI

struct AssetsCardView: View {
    let assetStore: AssetStore
    let baseCurrency: String
    /// The FX refresh (TransactionStore.currencyRatesVersion): assets in other currencies are
    /// converted with the cached rates, so the total is drawn again when they change.
    let ratesVersion: Int

    var body: some View {
        let held = assetStore.held
        FinanceCard(
            title: String(localized: "finances.assets.title"),
            isEmpty: held.isEmpty,
            emptyTitle: String(localized: "finances.assets.empty"),
            subtitle: String(format: NSLocalizedString("finances.assets.count", comment: "Count with plural forms in Localizable.stringsdict"), held.count)
        ) {
            RedactableAmount(amount: assetStore.totals(in: baseCurrency).value, currency: baseCurrency, isLoading: !assetStore.isLoaded)
        } trailing: {
            PackedCircleIcons(
                items: held.map { asset in
                    PackedCircleItem(
                        id: asset.id,
                        iconSource: asset.displayIcon,
                        amount: max(assetStore.ownedValue(of: asset, in: baseCurrency), 0)
                    )
                },
                style: .shelf
            )
        }
    }
}

#Preview("Assets Card") {
    let store = AssetStore(repository: nil)
    AssetsCardView(assetStore: store, baseCurrency: "KZT", ratesVersion: 0)
        .screenPadding()
        .task {
            await store.add(Asset(name: "Flat", kind: .apartment, currency: "KZT", purchasePrice: 24_000_000,
                                  valuations: [AssetValuation(date: Date(), value: 70_000_000)]))
            await store.add(Asset(name: "Car", kind: .vehicle, currency: "KZT", purchasePrice: 10_000_000))
        }
}
