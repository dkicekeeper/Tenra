//
//  LaunchHealthCheckTests.swift
//  TenraTests
//
//  Pins how the launch health check turns probe outcomes into results: what counts as a
//  failure (logged as an error, flagged in Settings → Diagnostics), what is skipped, and the
//  report's order and summary text.
//

import Foundation
import Testing
@testable import Tenra

struct LaunchHealthCheckTests {

    @Test("Database: open passes; a load failure or a failed read fails, with its code")
    func database() {
        #expect(LaunchHealthCheck.databaseResult(loadFailure: nil, readError: nil).status == .passed)

        let failure = StoreLoadFailure(kind: .migration, reference: "NSCocoaErrorDomain 134110", details: "")
        let unavailable = LaunchHealthCheck.databaseResult(loadFailure: failure, readError: nil)
        #expect(unavailable.status == .failed)
        #expect(unavailable.finding == .databaseUnavailable(reference: "NSCocoaErrorDomain 134110"))

        let unreadable = LaunchHealthCheck.databaseResult(loadFailure: nil, readError: "NSCocoaErrorDomain 256")
        #expect(unreadable.finding == .databaseUnreadable(reference: "NSCocoaErrorDomain 256"))
        #expect(unreadable.status == .failed)
    }

    @Test("Settings: nothing saved passes; a blob that doesn't decode fails")
    func settings() {
        #expect(LaunchHealthCheck.settingsResult(hasSavedSettings: false, decodeError: nil).finding == .settingsNotSaved)
        #expect(LaunchHealthCheck.settingsResult(hasSavedSettings: true, decodeError: nil).status == .passed)
        let broken = LaunchHealthCheck.settingsResult(hasSavedSettings: true, decodeError: "keyNotFound baseCurrency")
        #expect(broken.status == .failed)
    }

    @Test("Purchases: nothing to sell fails (the three-month silent paywall); offline is skipped")
    func purchases() {
        #expect(LaunchHealthCheck.purchasesResult(.available(packageCount: 3)).status == .passed)
        let nothing = LaunchHealthCheck.purchasesResult(.nothingToSell(revenueCatCode: 23))
        #expect(nothing.status == .failed)
        #expect(nothing.finding == .purchasesNothingToSell(reference: "RevenueCat 23"))
        #expect(LaunchHealthCheck.purchasesResult(.notConfigured).status == .failed)
        #expect(LaunchHealthCheck.purchasesResult(.failed(revenueCatCode: 2)).status == .failed)
        #expect(LaunchHealthCheck.purchasesResult(.offline).status == .skipped)
    }

    @Test("The report lists one result per item in a fixed order and collects the failures")
    func report() {
        let report = LaunchHealthCheck.makeReport([
            LaunchHealthCheck.purchasesResult(.nothingToSell(revenueCatCode: 23)),
            LaunchHealthCheck.settingsResult(hasSavedSettings: true, decodeError: nil),
            LaunchHealthCheck.databaseResult(loadFailure: nil, readError: nil),
        ], finishedAt: Date())

        #expect(report.results.map(\.item) == [.database, .settings, .purchases])
        #expect(report.failures.map(\.item) == [.purchases])
        #expect(!report.isHealthy)
    }

    @Test("A skipped check doesn't make the report unhealthy")
    func skippedIsHealthy() {
        let report = LaunchHealthCheck.makeReport([
            LaunchHealthCheck.databaseResult(loadFailure: nil, readError: nil),
            LaunchHealthCheck.settingsResult(hasSavedSettings: false, decodeError: nil),
            LaunchHealthCheck.purchasesResult(.offline),
        ], finishedAt: Date())
        #expect(report.isHealthy)
    }

    @Test("A later result for the same item replaces the earlier one")
    func laterResultWins() {
        let report = LaunchHealthCheck.makeReport([
            LaunchHealthCheck.purchasesResult(.offline),
            LaunchHealthCheck.purchasesResult(.available(packageCount: 1)),
        ], finishedAt: Date())
        #expect(report.results.count == 1)
        #expect(report.results.first?.status == .passed)
    }

    private struct NeedsCurrency: Decodable {
        let baseCurrency: String
        let wallpaperImageName: String?
    }

    private func decodingError(_ json: String) -> (any Error)? {
        do {
            _ = try JSONDecoder().decode(NeedsCurrency.self, from: Data(json.utf8))
            return nil
        } catch {
            return error
        }
    }

    @Test("Error references name the missing key or the failing path, never the data")
    func references() throws {
        let missingKey = try #require(decodingError("{}"))
        #expect(LaunchHealthCheck.reference(for: missingKey) == "keyNotFound baseCurrency")

        let wrongType = try #require(decodingError(#"{"baseCurrency":"KZT","wallpaperImageName":5}"#))
        #expect(LaunchHealthCheck.reference(for: wrongType) == "typeMismatch wallpaperImageName")

        #expect(LaunchHealthCheck.reference(for: NSError(domain: "Domain", code: 7)) == "Domain 7")
    }

    @Test("The shared summary has the versions, every check and every report")
    func summaryText() {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let report = LaunchHealthCheck.makeReport([
            LaunchHealthCheck.databaseResult(loadFailure: nil, readError: nil),
            LaunchHealthCheck.purchasesResult(.nothingToSell(revenueCatCode: 23)),
        ], finishedAt: start)
        let payload = DiagnosticPayloadSummary(
            fileName: "diagnostic-a.json",
            receivedAt: start,
            periodStart: start,
            periodEnd: start.addingTimeInterval(86_400),
            counts: .init(crashes: 1, hangs: 2)
        )

        let text = LaunchHealthCheck.summaryText(
            report: report,
            payloads: [payload],
            appVersion: "1.4 (2)",
            systemVersion: "26.0",
            deviceModel: "iPhone17,1",
            generatedAt: start
        )

        #expect(text.contains("App: 1.4 (2)"))
        #expect(text.contains("iOS: 26.0 (iPhone17,1)"))
        #expect(text.contains("- database: passed, open"))
        #expect(text.contains("- purchases: failed, nothing to sell (RevenueCat 23)"))
        #expect(text.contains("- diagnostic-a.json:"))
        #expect(text.contains("crashes 1, hangs 2"))
    }
}
