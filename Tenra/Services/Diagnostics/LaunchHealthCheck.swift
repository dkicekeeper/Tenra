//
//  LaunchHealthCheck.swift
//  Tenra
//
//  A small self-check run once per launch, after the first frame: the database opened and
//  reads, the saved settings decode, and the App Store has something to sell. Each of these
//  once failed silently (the paywall had nothing to sell for three months), so a failure is
//  logged with os.Logger and listed in Settings → Diagnostics, where the owner sees it
//  without a backend.
//
//  Pure aggregation: DiagnosticsCenter runs the probes and hands their raw outcomes here.
//

import Foundation

nonisolated enum LaunchHealthCheck {

    enum Item: String, CaseIterable, Sendable {
        case database
        case settings
        case purchases
    }

    enum Status: String, Sendable {
        case passed
        case failed
        /// Could not be checked (offline): says nothing about the app.
        case skipped
    }

    /// What a probe saw. `reference` is a technical code for support, never shown as prose.
    enum Finding: Equatable, Sendable {
        case databaseOpen
        case databaseUnavailable(reference: String)
        case databaseUnreadable(reference: String)
        case settingsDecoded
        /// Nothing saved yet (a fresh install): the defaults are correct.
        case settingsNotSaved
        case settingsUnreadable(reference: String)
        case purchasesAvailable(packageCount: Int)
        case purchasesNotConfigured
        case purchasesNothingToSell(reference: String?)
        case purchasesOffline
        case purchasesFailed(reference: String?)
    }

    struct Result: Equatable, Sendable, Identifiable {
        let item: Item
        let finding: Finding

        var id: Item { item }

        var status: Status {
            switch finding {
            case .databaseOpen, .settingsDecoded, .settingsNotSaved, .purchasesAvailable:
                return .passed
            case .purchasesOffline:
                return .skipped
            case .databaseUnavailable, .databaseUnreadable, .settingsUnreadable,
                 .purchasesNotConfigured, .purchasesNothingToSell, .purchasesFailed:
                return .failed
            }
        }

        /// English, for the log and the shared diagnostics summary.
        var logDescription: String {
            let detail: String
            switch finding {
            case .databaseOpen: detail = "open"
            case .databaseUnavailable(let reference): detail = "could not be opened (\(reference))"
            case .databaseUnreadable(let reference): detail = "opened but a read failed (\(reference))"
            case .settingsDecoded: detail = "decoded"
            case .settingsNotSaved: detail = "none saved yet, defaults in use"
            case .settingsUnreadable(let reference): detail = "saved settings don't decode, defaults in use (\(reference))"
            case .purchasesAvailable(let count): detail = "current offering has \(count) package(s)"
            case .purchasesNotConfigured: detail = "RevenueCat is not configured"
            case .purchasesNothingToSell(let reference): detail = "nothing to sell" + Self.suffix(reference)
            case .purchasesOffline: detail = "offline, not checked"
            case .purchasesFailed(let reference): detail = "offerings failed to load" + Self.suffix(reference)
            }
            return "\(item.rawValue): \(status.rawValue), \(detail)"
        }

        private static func suffix(_ reference: String?) -> String {
            reference.map { " (\($0))" } ?? ""
        }
    }

    struct Report: Equatable, Sendable {
        /// One result per item, in `Item.allCases` order.
        let results: [Result]
        let finishedAt: Date

        var failures: [Result] { results.filter { $0.status == .failed } }
        var isHealthy: Bool { failures.isEmpty }
    }

    // MARK: - Probe outcomes → results

    /// `loadFailure`: why the store could not be opened (nil = open).
    /// `readError`: a reference for a failed test read on an open store.
    static func databaseResult(loadFailure: StoreLoadFailure?, readError: String?) -> Result {
        if let loadFailure {
            return Result(item: .database, finding: .databaseUnavailable(reference: loadFailure.reference))
        }
        if let readError {
            return Result(item: .database, finding: .databaseUnreadable(reference: readError))
        }
        return Result(item: .database, finding: .databaseOpen)
    }

    /// `hasSavedSettings`: a settings blob exists. `decodeError`: why it doesn't decode (nil = it does).
    static func settingsResult(hasSavedSettings: Bool, decodeError: String?) -> Result {
        guard hasSavedSettings else { return Result(item: .settings, finding: .settingsNotSaved) }
        if let decodeError {
            return Result(item: .settings, finding: .settingsUnreadable(reference: decodeError))
        }
        return Result(item: .settings, finding: .settingsDecoded)
    }

    static func purchasesResult(_ availability: OfferingsAvailability) -> Result {
        let finding: Finding
        switch availability {
        case .available(let count):
            finding = .purchasesAvailable(packageCount: count)
        case .notConfigured:
            finding = .purchasesNotConfigured
        case .nothingToSell(let code):
            finding = .purchasesNothingToSell(reference: code.map { "RevenueCat \($0)" })
        case .offline:
            finding = .purchasesOffline
        case .failed(let code):
            finding = .purchasesFailed(reference: code.map { "RevenueCat \($0)" })
        }
        return Result(item: .purchases, finding: finding)
    }

    /// Orders the results by item; a later result for the same item replaces an earlier one.
    static func makeReport(_ results: [Result], finishedAt: Date) -> Report {
        var latest: [Item: Result] = [:]
        for result in results { latest[result.item] = result }
        return Report(results: Item.allCases.compactMap { latest[$0] }, finishedAt: finishedAt)
    }

    /// A short technical reference for an error: the missing key or failing path of a
    /// DecodingError, else "domain code". Never contains the data itself.
    static func reference(for error: Error) -> String {
        switch error as? DecodingError {
        case .keyNotFound(let key, _)?:
            return "keyNotFound \(key.stringValue)"
        case .typeMismatch(_, let context)?:
            return "typeMismatch \(path(context))"
        case .valueNotFound(_, let context)?:
            return "valueNotFound \(path(context))"
        case .dataCorrupted?:
            return "dataCorrupted"
        default:
            let ns = error as NSError
            return "\(ns.domain) \(ns.code)"
        }
    }

    private static func path(_ context: DecodingError.Context) -> String {
        context.codingPath.map(\.stringValue).joined(separator: ".")
    }

    // MARK: - Shared summary

    /// The plain-text file shared from Settings → Diagnostics with the payloads: versions,
    /// the launch check and the list of saved reports. English: it is read by the developer.
    /// Contains no user data.
    static func summaryText(
        report: Report?,
        payloads: [DiagnosticPayloadSummary],
        appVersion: String,
        systemVersion: String,
        deviceModel: String,
        generatedAt: Date
    ) -> String {
        let iso = ISO8601DateFormatter()
        var lines = [
            "Tenra diagnostics",
            "App: \(appVersion)",
            "iOS: \(systemVersion) (\(deviceModel))",
            "Generated: \(iso.string(from: generatedAt))",
            "",
        ]
        if let report {
            lines.append("Launch check (\(iso.string(from: report.finishedAt))):")
            lines += report.results.map { "- \($0.logDescription)" }
        } else {
            lines.append("Launch check: not run yet")
        }
        lines.append("")
        lines.append("MetricKit diagnostic reports (\(payloads.count)):")
        for payload in payloads {
            let counts = payload.counts
            lines.append(
                "- \(payload.fileName): \(iso.string(from: payload.periodStart)) to \(iso.string(from: payload.periodEnd)), "
                + "crashes \(counts.crashes), hangs \(counts.hangs), disk writes \(counts.diskWrites), "
                + "cpu \(counts.cpuExceptions), slow launches \(counts.slowLaunches)"
            )
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
