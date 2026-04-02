//
//  PerformanceProfiler.swift
//  AIFinanceManager
//
//  Created on 2024
//

import Foundation
import os

private let perfLogger = Logger(subsystem: "AIFinanceManager", category: "Performance")

/// Простой профилировщик производительности для debug режима
#if DEBUG
@MainActor
class PerformanceProfiler {
    private static var measurements: [String: TimeInterval] = [:]
    private static var startTimes: [String: Date] = [:]

    /// Начать измерение времени выполнения
    nonisolated static func start(_ name: String) {
        Task { @MainActor in
            startTimes[name] = Date()
        }
    }

    /// Завершить измерение и вывести результат
    nonisolated static func end(_ name: String) {
        Task { @MainActor in
            guard let startTime = startTimes[name] else {
                return
            }

            let duration = Date().timeIntervalSince(startTime)
            measurements[name] = duration

            if duration > 0.1 {
                // Threshold exceeded — warn so it appears in Console.app filtered by category "Performance"
                perfLogger.warning("⚠️ [Perf] \(name): \(String(format: "%.0f", duration * 1000))ms — exceeds 100ms threshold")
            } else if duration > 0.016 {
                perfLogger.debug("🕐 [Perf] \(name): \(String(format: "%.0f", duration * 1000))ms")
            }

            startTimes.removeValue(forKey: name)
        }
    }

    /// Получить все измерения
    static func getAllMeasurements() -> [String: TimeInterval] {
        return measurements
    }

    /// Очистить все измерения
    static func clear() {
        measurements.removeAll()
        startTimes.removeAll()
    }

    /// Измерить время выполнения блока кода
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
