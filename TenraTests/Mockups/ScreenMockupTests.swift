//
//  ScreenMockupTests.swift
//  TenraTests
//
//  Renders screens to PNG for the owner to look at before a layout ships (CLAUDE.md, "To check
//  a layout you changed"). A UIWindow with a UIHostingController, drawn by `drawHierarchy`, so
//  glass, navigation bars and scroll views come out as on the phone (ImageRenderer leaves
//  UIKit-backed views out). Runs only where MOCKUP_DIR is set: Actions → Mockups
//  (`.github/workflows/mockups.yml`) sets it per language and uploads the folder. A screen's
//  mockup stays here while its layout is in review; drop it once approved.
//

import Testing
import SwiftUI
import UIKit
@testable import Tenra

@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["MOCKUP_DIR"] != nil), .serialized)
struct ScreenMockupTests {

    private var directory: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["MOCKUP_DIR"] ?? NSTemporaryDirectory())
    }

    // In review: the assets section (docs/plan-assets.md, phase 1): the Finances card, the
    // list with its hero, an asset's screen and its form. A new screen in review gets a `@Test`
    // here that calls `render(_:height:_:)`.

    // MARK: - Assets

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    /// A flat that grew, a car that lost value, a garage without a purchase price, a sold
    /// country house: every look of a card.
    private func demoAssets() async -> AssetStore {
        let store = AssetStore(repository: nil)
        await store.add(Asset(
            id: "flat", name: "Flat on Abay", kind: .apartment, currency: "KZT",
            purchaseDate: Self.day(2018, 6, 12), purchasePrice: 24_000_000,
            valuations: [
                AssetValuation(date: Self.day(2021, 5, 1), value: 41_000_000),
                AssetValuation(date: Self.day(2023, 9, 1), value: 58_000_000),
                AssetValuation(date: Self.day(2026, 10, 16), value: 70_000_000, note: "Listings on krisha.kz"),
            ]
        ))
        await store.add(Asset(
            id: "car", name: "Toyota Camry", kind: .vehicle, currency: "KZT",
            purchaseDate: Self.day(2024, 3, 1), purchasePrice: 15_000_000,
            valuations: [AssetValuation(date: Self.day(2026, 9, 2), value: 12_600_000)]
        ))
        await store.add(Asset(
            id: "garage", name: "Garage", kind: .commercial, currency: "KZT",
            valuations: [AssetValuation(date: Self.day(2026, 3, 3), value: 3_500_000)]
        ))
        await store.add(Asset(
            id: "dacha", name: "Country house", kind: .house, currency: "KZT",
            purchaseDate: Self.day(2015, 4, 20), purchasePrice: 6_000_000
        ))
        await store.sell(assetId: "dacha", price: 14_000_000, date: Self.day(2026, 7, 10))
        return store
    }

    @Test func assetsList() async throws {
        let store = await demoAssets()
        let coordinator = AppCoordinator()
        try await render("assets-list", height: 1400) {
            NavigationStack {
                AssetsListView(assetStore: store)
            }
            .environment(coordinator)
            .environment(PremiumManager.shared)
        }
    }

    @Test func assetDetail() async throws {
        let store = await demoAssets()
        let coordinator = AppCoordinator()
        try await render("asset-detail", height: 1500) {
            NavigationStack {
                AssetDetailView(assetStore: store, assetId: "flat")
            }
            .environment(coordinator)
            .environment(coordinator.transactionStore)
            .environment(TimeFilterManager())
        }
    }

    @Test func assetsCard() async throws {
        let store = await demoAssets()
        try await render("assets-card", height: 300) {
            AssetsCardView(assetStore: store, baseCurrency: "KZT", ratesVersion: 0)
                .screenPadding()
                .frame(maxHeight: .infinity)
                .background(AppColors.Background.base)
        }
    }

    @Test func assetEdit() async throws {
        let store = await demoAssets()
        let flat = try #require(store.asset(id: "flat"))
        try await render("asset-edit") {
            AssetEditView(asset: flat, loanAccounts: [], baseCurrency: "KZT", onSave: { _ in })
        }
    }

    // MARK: - Rendering

    /// Draws `content` in an iPhone-sized window, in the light and the dark theme, into
    /// `<name>-light.png` and `<name>-dark.png`.
    private func render<Content: View>(
        _ name: String,
        height: CGFloat = 874,
        @ViewBuilder _ content: () -> Content
    ) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = UIHostingController(rootView: content())
            window.isHidden = false
            // Lay out, load fonts and let entrance animations settle: polls, not a deadline
            // (CLAUDE.md, Testing).
            for _ in 0..<40 { try await Task.sleep(for: .milliseconds(50)) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let file = directory.appendingPathComponent("\(name)-\(style == .dark ? "dark" : "light").png")
            try #require(image.pngData()).write(to: file)
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
