//
//  DiagnosticsCenter.swift
//  Tenra
//
//  Owns the app's on-device diagnostics: the MetricKit collector (payloads saved in
//  Application Support/Diagnostics) and the launch health check. Settings → Diagnostics reads
//  both and shares them. There is no backend; nothing leaves the device unless the user
//  shares it.
//
//  Launch cost: registering the MetricKit subscriber is one call in didFinishLaunching. The
//  health check is scheduled after the first frame, and its probes run off the main actor
//  except the settings decode (AppSettings is MainActor-isolated; one small JSON blob).
//

import Foundation
import Observation
import CoreData
import MetricKit
import UIKit
import os

@MainActor
@Observable
final class DiagnosticsCenter {

    static let shared = DiagnosticsCenter()

    /// The latest launch health check; nil until the first run finishes.
    private(set) var lastReport: LaunchHealthCheck.Report?
    private(set) var isChecking = false

    @ObservationIgnored let payloadStore: DiagnosticPayloadStore
    @ObservationIgnored private let collector: MetricKitCollector
    @ObservationIgnored private var isCollecting = false
    @ObservationIgnored private var scheduledCheck: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "Tenra", category: "Diagnostics")

    private init() {
        let store = DiagnosticPayloadStore()
        payloadStore = store
        collector = MetricKitCollector(store: store)
    }

    // MARK: - MetricKit

    /// Call once at launch (AppDelegate). iOS then delivers pending diagnostic payloads.
    func startCollectingPayloads() {
        guard !isCollecting else { return }
        isCollecting = true
        MXMetricManager.shared.add(collector)
    }

    /// Saved payloads, newest first (read off the main actor).
    func payloadSummaries() async -> [DiagnosticPayloadSummary] {
        let store = payloadStore
        return await Task.detached(priority: .utility) { store.summaries() }.value
    }

    // MARK: - Launch health check

    /// Runs the health check once `delay` has passed (by default after the first frame and the
    /// home reveal). A new call replaces a pending one.
    func scheduleLaunchHealthCheck(after delay: Duration = .seconds(2)) {
        scheduledCheck?.cancel()
        scheduledCheck = Task(priority: .utility) { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.runHealthCheck()
        }
    }

    /// Checks the database, the saved settings and the offerings, logs each result
    /// (failures as errors) and publishes the report for Settings → Diagnostics.
    func runHealthCheck() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        let settingsKey = SettingsStorageService.userDefaultsKey
        async let database = Self.probeDatabase()
        async let savedSettings = Self.readSavedSettings(key: settingsKey)
        let purchases = LaunchHealthCheck.purchasesResult(await PremiumManager.shared.checkOfferings())
        let settings = Self.settingsResult(for: await savedSettings)

        let report = LaunchHealthCheck.makeReport([await database, settings, purchases], finishedAt: Date())
        for result in report.results {
            if result.status == .failed {
                logger.error("Launch check: \(result.logDescription, privacy: .public)")
            } else {
                logger.info("Launch check: \(result.logDescription, privacy: .public)")
            }
        }
        lastReport = report
    }

    /// The store opened (or why not), and a COUNT on a background context reads.
    private nonisolated static func probeDatabase() async -> LaunchHealthCheck.Result {
        let stack = CoreDataStack.shared
        if let failure = stack.openStoreIfNeeded() {
            return LaunchHealthCheck.databaseResult(loadFailure: failure, readError: nil)
        }
        let context = stack.newBackgroundContext()
        let readError: String? = await context.perform {
            do {
                _ = try context.count(for: AccountEntity.fetchRequest())
                return nil
            } catch {
                return LaunchHealthCheck.reference(for: error)
            }
        }
        return LaunchHealthCheck.databaseResult(loadFailure: nil, readError: readError)
    }

    private nonisolated static func readSavedSettings(key: String) async -> Data? {
        UserDefaults.standard.data(forKey: key)
    }

    /// Decodes with the real AppSettings decoder, which SettingsStorageService would otherwise
    /// replace with the defaults without a word.
    private static func settingsResult(for data: Data?) -> LaunchHealthCheck.Result {
        guard let data else {
            return LaunchHealthCheck.settingsResult(hasSavedSettings: false, decodeError: nil)
        }
        do {
            _ = try JSONDecoder().decode(AppSettings.self, from: data)
            return LaunchHealthCheck.settingsResult(hasSavedSettings: true, decodeError: nil)
        } catch {
            return LaunchHealthCheck.settingsResult(
                hasSavedSettings: true,
                decodeError: LaunchHealthCheck.reference(for: error)
            )
        }
    }

    // MARK: - Sharing

    /// Writes the summary text file and returns it with the saved payload files, for ShareLink.
    func prepareShareItems(payloads: [DiagnosticPayloadSummary]) async -> [URL] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let text = LaunchHealthCheck.summaryText(
            report: lastReport,
            payloads: payloads,
            appVersion: "\(version) (\(build))",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: Self.deviceModel,
            generatedAt: Date()
        )
        let store = payloadStore
        return await Task.detached(priority: .utility) {
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("TenraDiagnostics", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let summaryURL = folder.appendingPathComponent("Tenra-diagnostics.txt")
            var urls: [URL] = []
            if (try? Data(text.utf8).write(to: summaryURL, options: .atomic)) != nil {
                urls.append(summaryURL)
            }
            urls += payloads
                .map { store.fileURL(for: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            return urls
        }.value
    }

    /// Hardware model identifier, e.g. "iPhone17,1" (UIDevice only says "iPhone").
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
