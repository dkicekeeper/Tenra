//
//  MetricKitCollector.swift
//  Tenra
//
//  MetricKit subscriber: keeps the diagnostic payloads iOS delivers (crashes, hangs, disk-write
//  and CPU exceptions, slow launches) in DiagnosticPayloadStore, so they can be read in
//  Settings → Diagnostics and shared. Without it a crash in the field left no trace the owner
//  could see. Metric payloads (daily aggregates) are not kept: only the diagnostics matter here.
//
//  MetricKit calls back on a background queue, so the type is nonisolated and only touches the
//  thread-safe store. Registered once at launch (AppDelegate → DiagnosticsCenter), which keeps
//  the instance alive for the whole process.
//

import Foundation
import MetricKit
import os

nonisolated final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    private static let logger = Logger(subsystem: "Tenra", category: "MetricKit")

    private let store: DiagnosticPayloadStore

    init(store: DiagnosticPayloadStore) {
        self.store = store
        super.init()
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let counts = DiagnosticPayloadSummary.Counts(
                crashes: payload.crashDiagnostics?.count ?? 0,
                hangs: payload.hangDiagnostics?.count ?? 0,
                diskWrites: payload.diskWriteExceptionDiagnostics?.count ?? 0,
                cpuExceptions: payload.cpuExceptionDiagnostics?.count ?? 0,
                slowLaunches: payload.appLaunchDiagnostics?.count ?? 0
            )
            do {
                try store.save(
                    json: payload.jsonRepresentation(),
                    periodStart: payload.timeStampBegin,
                    periodEnd: payload.timeStampEnd,
                    counts: counts
                )
                Self.logger.notice("Diagnostic payload saved: crashes=\(counts.crashes, privacy: .public) hangs=\(counts.hangs, privacy: .public) diskWrites=\(counts.diskWrites, privacy: .public) cpu=\(counts.cpuExceptions, privacy: .public) launches=\(counts.slowLaunches, privacy: .public)")
            } catch {
                Self.logger.error("Diagnostic payload not saved: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        // Daily metric aggregates are not kept; see the header.
    }
}
