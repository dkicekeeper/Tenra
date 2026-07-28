//
//  PerformanceProfiler.swift
//  Tenra
//
//  Created on 2024
//

import Foundation
import QuartzCore
import os

private nonisolated let perfLogger = Logger(subsystem: "Tenra", category: "Performance")

/// Простой профилировщик производительности для debug режима.
///
/// Implementation note: previous version used `Task { @MainActor in startTimes[...] = Date() }`
/// to capture timestamps. That made measurements unreliable for any hot caller — the captured
/// time was "when MainActor next had a free slot", not the actual call site, so a 142 ms
/// `initialize()` followed by 4 s of UI rendering would report as a 4 s warning. Now we use
/// `CACurrentMediaTime()` (lock-free, monotonic) at the call site, gated by an unfair lock so
/// nonisolated callers from any thread are safe.
#if DEBUG
final class PerformanceProfiler {
    nonisolated(unsafe) private static var measurements: [String: TimeInterval] = [:]
    nonisolated(unsafe) private static var startTimes: [String: CFTimeInterval] = [:]
    nonisolated(unsafe) private static var lock = os_unfair_lock_s()

    nonisolated static func start(_ name: String) {
        let now = CACurrentMediaTime()
        os_unfair_lock_lock(&lock)
        startTimes[name] = now
        os_unfair_lock_unlock(&lock)
    }

    nonisolated static func end(_ name: String) {
        let now = CACurrentMediaTime()
        os_unfair_lock_lock(&lock)
        let startTime = startTimes.removeValue(forKey: name)
        if let startTime {
            measurements[name] = now - startTime
        }
        os_unfair_lock_unlock(&lock)

        guard let startTime else { return }
        let duration = now - startTime

        if duration > 0.1 {
            perfLogger.warning("⚠️ [Perf] \(name): \(String(format: "%.0f", duration * 1000))ms — exceeds 100ms threshold")
        } else if duration > 0.016 {
            perfLogger.debug("🕐 [Perf] \(name): \(String(format: "%.0f", duration * 1000))ms")
        }
    }

    static func getAllMeasurements() -> [String: TimeInterval] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return measurements
    }

    static func clear() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        measurements.removeAll()
        startTimes.removeAll()
    }

    static func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        start(name)
        defer { end(name) }
        return try block()
    }
}
#else
// В release режиме профилировщик не делает ничего
class PerformanceProfiler {
    static func start(_ name: String) {}
    static func end(_ name: String) {}
    static func getAllMeasurements() -> [String: TimeInterval] { [:] }
    static func clear() {}
    static func measure<T>(_ name: String, _ block: () throws -> T) rethrows -> T {
        return try block()
    }
}
#endif
