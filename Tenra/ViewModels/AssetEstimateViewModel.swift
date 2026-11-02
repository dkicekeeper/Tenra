//
//  AssetEstimateViewModel.swift
//  Tenra
//
//  The asset screen's "Estimate from listings" (docs/domains/assets.md, plan A4): the
//  characteristics the estimate needs (saved into the asset when the search starts), one
//  POST /v1/valuation on Ten's server, its answer in the asset's currency, and the value saved as
//  a valuation with its range and the number of listings. The server counts the month's
//  estimates (two without Pro); a refusal becomes a failure the sheet explains.
//

import Foundation
import Observation

@Observable
@MainActor
final class AssetEstimateViewModel {
    enum Phase: Equatable {
        /// The characteristics, before a search.
        case details
        case searching
        case result(AssetEstimate)
        case failed(Failure)
    }

    enum Failure: Equatable {
        /// The month's estimates are used up (the limit, when the server said).
        case quota(limit: Int?)
        /// Off on the server, not in this region, or this device is not allowed.
        case unavailable
        /// Busy or unreachable: worth trying again.
        case busy
    }

    let assetId: String
    @ObservationIgnored private let assets: AssetStore
    @ObservationIgnored private let transport: AgentValuationTransport
    var draft: AssetAttributesDraft
    private(set) var phase: Phase = .details

    init(asset: Asset, assets: AssetStore, transport: AgentValuationTransport, defaultCountry: String?) {
        assetId = asset.id
        self.assets = assets
        self.transport = transport
        draft = AssetAttributesDraft(asset.attributes, defaultCountry: defaultCountry)
    }

    var asset: Asset? { assets.asset(id: assetId) }

    /// The characteristics as the sheet has them now.
    var attributes: AssetAttributes {
        guard let asset else { return AssetAttributes() }
        return draft.attributes(for: asset.kind, over: asset.attributes)
    }

    /// What the kind still needs, one field of each group: the search waits for it.
    var missing: [[AssetAttributes.Field]] {
        guard let asset else { return [] }
        return attributes.missing(for: asset.kind)
    }

    /// Saves the characteristics into the asset and asks the server.
    func estimate() async {
        guard let asset, !asset.isSold, missing.isEmpty, phase != .searching else { return }
        let attributes = self.attributes
        if attributes != asset.attributes {
            var updated = asset
            updated.attributes = attributes
            await assets.update(updated)
        }
        phase = .searching
        let country = AssetEstimateRequest.country(nil, attributes: attributes)
        let body = AssetEstimateRequest.body(kind: asset.kind, attributes: attributes, country: country)
        do {
            let answer = try await transport.valuation(asset: body)
            phase = .result(AssetEstimate(answer: answer))
        } catch let error as AgentServerError {
            phase = .failed(Self.failure(error))
        } catch {
            phase = .failed(.busy)
        }
    }

    /// Back to the characteristics (to add a district after too few listings).
    func edit() {
        phase = .details
    }

    static func failure(_ error: AgentServerError) -> Failure {
        switch error {
        case .quotaExceeded(let limit): return .quota(limit: limit)
        case .busy, .http, .invalidRequest: return .busy
        case .disabled, .regionUnavailable, .notConfigured, .unauthorized, .attestation, .entitlementUnavailable: return .unavailable
        }
    }

    /// An amount of the estimate in the asset's currency at the cached rates; nil without a rate.
    func inAssetCurrency(_ amount: Double?, of estimate: AssetEstimate) -> Double? {
        guard let amount, let market = estimate.marketCurrency, let asset else { return nil }
        if market == asset.currency { return amount }
        return CurrencyConverter.convertSync(amount: amount, from: market, to: asset.currency).map { $0.rounded() }
    }

    /// Saves the median as today's valuation, with its range, count and sites; false when it
    /// has no value in the asset's currency.
    @discardableResult
    func save(_ estimate: AssetEstimate, today: Date = Date()) async -> Bool {
        guard estimate.isSufficient, let value = inAssetCurrency(estimate.value, of: estimate) else { return false }
        let sites = estimate.sites
        let note = String(
            format: String(localized: "asset.estimate.note"),
            estimate.count,
            sites.isEmpty ? String(localized: "asset.estimate.title") : sites.joined(separator: ", ")
        )
        let listings = AssetValuation.Listings(
            low: inAssetCurrency(estimate.low, of: estimate) ?? value,
            high: inAssetCurrency(estimate.high, of: estimate) ?? value,
            count: estimate.count,
            sites: sites
        )
        await assets.addValuation(
            AssetValuation(date: Calendar.current.startOfDay(for: today), value: value, source: .assistant, note: note, listings: listings),
            to: assetId
        )
        return true
    }
}
