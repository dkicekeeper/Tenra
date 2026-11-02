//
//  AssetEstimateTests.swift
//  TenraTests
//
//  "Estimate from listings" (docs/domains/assets.md, plan A4): the request is the asset's kind,
//  country and the characteristics the server takes; the answer is read back with its listings
//  (only web links open) and the estimates left; the sheet's model saves the characteristics
//  into the asset when the search starts, waits for what the kind needs, turns the server's
//  refusals into a failure, and saves the median as today's valuation with its range. Amounts
//  are KZT on both sides, so no shared FX state is involved.
//

import Foundation
import Testing
@testable import Tenra

@MainActor
struct AssetEstimateTests {

    /// The server's `POST /v1/valuation`, answering what it is given.
    private nonisolated final class Transport: AgentValuationTransport, @unchecked Sendable {
        private(set) var sent: [[String: JSONValue]] = []
        private let answer: Result<JSONValue, AgentServerError>

        init(_ answer: Result<JSONValue, AgentServerError>) {
            self.answer = answer
        }

        func valuation(asset: [String: JSONValue]) async throws -> JSONValue {
            sent.append(asset)
            return try answer.get()
        }
    }

    private static let answer: JSONValue = [
        "status": "ok", "currency": "KZT", "value": 72_500_000, "low": 67_800_000, "high": 76_100_000,
        "accuracy": "medium", "basis": "per_unit", "count": 14,
        "listings": [
            ["title": "2-комнатная квартира", "url": "https://krisha.kz/a/show/1", "site": "krisha.kz", "price": 70_000_000, "currency": "KZT", "size_m2": 62, "rooms": 2, "year": 2012],
            ["title": "Квартира", "url": "javascript:alert(1)", "site": "olx.kz", "price": 74_000_000, "currency": "KZT", "size_m2": 66, "rooms": 2],
        ],
        "searched_at": "2026-11-02T10:00:00.000Z", "quota": ["used": 1, "limit": 2],
    ]

    private static var flat: Asset {
        Asset(
            id: "flat", name: "Квартира на Абая", kind: .apartment, currency: "KZT",
            purchaseDate: FastDateParser.date(from: "2018-10-29"), purchasePrice: 24_000_000,
            valuations: [AssetValuation(id: "v1", date: FastDateParser.date(from: "2026-04-16")!, value: 70_000_000)]
        )
    }

    @Test func theAnswerIsReadWithItsListingsAndWhatIsLeft() throws {
        let estimate = AssetEstimate(answer: Self.answer)
        #expect(estimate.isSufficient)
        #expect(estimate.marketCurrency == "KZT")
        #expect(estimate.value == 72_500_000)
        #expect(estimate.low == 67_800_000)
        #expect(estimate.count == 14)
        #expect(estimate.accuracy == .medium)
        #expect(estimate.estimatesLeft == 1)
        #expect(estimate.searchedAt != nil)
        #expect(estimate.listings.count == 2)
        #expect(estimate.listings.first?.url?.host() == "krisha.kz")
        #expect(estimate.listings.first?.rooms == 2)
        // Only a web link opens.
        #expect(estimate.listings.last?.url == nil)
        #expect(estimate.sites == ["krisha.kz", "olx.kz"])

        let few = AssetEstimate(answer: ["status": "insufficient", "reason": "few_listings", "count": 2, "listings": []])
        #expect(!few.isSufficient)
        #expect(few.value == nil)
    }

    @Test func theRequestIsTheKindTheCountryAndWhatTheServerTakes() {
        let attributes = AssetAttributes([
            "country": .text("tr"), "city": .text(" İstanbul "), "area_m2": .number(64), "rooms": .number(2.5), "make": .text("Toyota"),
        ])
        let body = AssetEstimateRequest.body(kind: .apartment, attributes: attributes, country: AssetEstimateRequest.country(nil, attributes: attributes))
        #expect(body["kind"] == "apartment")
        #expect(body["country"] == "TR")
        #expect(body["city"] == "İstanbul")
        #expect(body["area_m2"]?.numberValue == 64)
        #expect(!body.keys.contains("rooms") && !body.keys.contains("make"))
        #expect(AssetEstimateRequest.country("kz", attributes: attributes) == "KZ")
    }

    /// The characteristics go into the asset when the search starts; the median is saved as
    /// today's valuation with its range, count and sites.
    @Test func anEstimateSavesTheCharacteristicsAndThenTheValuation() async throws {
        let assets = AssetStore(repository: nil)
        await assets.add(Self.flat)
        let transport = Transport(.success(Self.answer))
        let model = AssetEstimateViewModel(asset: Self.flat, assets: assets, transport: transport, defaultCountry: "KZ")

        // A flat needs its city and area before any search.
        #expect(model.missing.count == 2)
        await model.estimate()
        #expect(transport.sent.isEmpty)
        #expect(model.phase == .details)

        model.draft.texts[.city] = "Алматы"
        model.draft.texts[.areaM2] = "64"
        model.draft.texts[.rooms] = "2"
        #expect(model.missing.isEmpty)
        await model.estimate()
        let sent = try #require(transport.sent.first)
        #expect(sent["country"] == "KZ")
        #expect(sent["city"] == "Алматы")
        #expect(sent["rooms"]?.numberValue == 2)
        #expect(!sent.keys.contains("name"))
        #expect(assets.asset(id: "flat")?.attributes.text(.city) == "Алматы")

        guard case .result(let estimate) = model.phase else {
            Issue.record("no result: \(model.phase)")
            return
        }
        let today = try #require(FastDateParser.date(from: "2026-11-02"))
        let savedIt = await model.save(estimate, today: today)
        #expect(savedIt)
        let saved = try #require(assets.asset(id: "flat")?.valuations.last)
        #expect(saved.value == 72_500_000)
        #expect(saved.source == .assistant)
        #expect(saved.listings == AssetValuation.Listings(low: 67_800_000, high: 76_100_000, count: 14, sites: ["krisha.kz", "olx.kz"]))
        #expect(saved.note?.contains("14") == true)
        #expect(saved.note?.contains("krisha.kz") == true)
    }

    @Test func theServersRefusalsBecomeWhatTheSheetSays() async {
        let cases: [(AgentServerError, AssetEstimateViewModel.Failure)] = [
            (.quotaExceeded(limit: 2), .quota(limit: 2)),
            (.disabled, .unavailable),
            (.regionUnavailable, .unavailable),
            (.busy, .busy),
            (.http(status: 422), .busy),
        ]
        for (error, failure) in cases {
            let assets = AssetStore(repository: nil)
            var flat = Self.flat
            flat.attributes = AssetAttributes(["city": .text("Алматы"), "area_m2": .number(64)])
            await assets.add(flat)
            let model = AssetEstimateViewModel(asset: flat, assets: assets, transport: Transport(.failure(error)), defaultCountry: "KZ")
            await model.estimate()
            #expect(model.phase == .failed(failure), "\(error)")
        }
    }

    /// A valuation saved with its range reads back; one saved before the range existed reads
    /// without it.
    @Test func aValuationKeepsItsRange() throws {
        let valuation = AssetValuation(id: "v", date: Date(timeIntervalSinceReferenceDate: 0), value: 72_500_000, source: .assistant,
                                       listings: AssetValuation.Listings(low: 67_800_000, high: 76_100_000, count: 14, sites: ["krisha.kz"]))
        let data = try JSONEncoder().encode([valuation])
        #expect(AssetRepository.valuations(from: data) == [valuation])
        let older = Data(#"[{"id":"o","date":0,"value":70000000,"source":"manual"}]"#.utf8)
        #expect(AssetRepository.valuations(from: older).first?.listings == nil)
    }
}
