//
//  InsightsCache.swift
//  AIFinanceManager
//
//  Phase 17: Financial Insights Feature
//  In-memory LRU cache with TTL for computed insights.
//
//  Phase 31: Removed @MainActor isolation. Protected by NSLock so the cache
//  can be read/written from InsightsService running on any thread.
//
//  Design:
//  - Maximum `capacity` entries (default 20) to bound memory usage
//  - TTL (default 5 min) expiry — stale entries are lazily removed on read
//  - LRU eviction: the access-ordered array `lruKeys` tracks usage order;
//    the oldest entry is evicted when capacity is exceeded
//  - All operations are O(1) via dictionary + O(n) LRU scan (n ≤ 20, negligible)
//

import Foundation

/// Thread-safe LRU insights cache. @unchecked Sendable — internal state protected by NSLock.
nonisolated final class InsightsCache: @unchecked Sendable {
    // MARK: - Types

    private struct CacheEntry {
        let insights: [Insight]
        let timestamp: Date
    }

    // MARK: - Properties

    private var cache: [String: CacheEntry] = [:]
    /// Insertion-order list; most-recently used key moves to the back.
    private var lruKeys: [String] = []
    private let ttl: TimeInterval
    private let capacity: Int
    private let lock = NSLock()

    // MARK: - Init

    init(ttl: TimeInterval = 300, capacity: Int = 20) {
        self.ttl = ttl
        self.capacity = max(1, capacity)
    }

    // MARK: - Public API

    func get(key: String) -> [Insight]? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = cache[key] else { return nil }

        // TTL check — lazy eviction on read
        if Date().timeIntervalSince(entry.timestamp) > ttl {
            evictLocked(key: key)
            return nil
        }

        // Promote to most-recently-used
        promoteLocked(key: key)
        return entry.insights
    }

    func set(key: String, insights: [Insight]) {
        lock.lock()
        defer { lock.unlock() }

        if cache[key] != nil {
            cache[key] = CacheEntry(insights: insights, timestamp: Date())
            promoteLocked(key: key)
        } else {
            if cache.count >= capacity, let oldest = lruKeys.first {
                evictLocked(key: oldest)
            }
            cache[key] = CacheEntry(insights: insights, timestamp: Date())
            lruKeys.append(key)
        }
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
        lruKeys.removeAll()
    }

    func invalidate(category: InsightCategory) {
        lock.lock()
        defer { lock.unlock() }
        let keysToRemove = cache.keys.filter { $0.contains(category.rawValue) }
        for key in keysToRemove { evictLocked(key: key) }
    }

    // MARK: - Private Helpers (call only while lock is held)

    private func promoteLocked(key: String) {
        if let idx = lruKeys.firstIndex(of: key) {
            lruKeys.remove(at: idx)
            lruKeys.append(key)
        }
    }

    private func evictLocked(key: String) {
        cache.removeValue(forKey: key)
        lruKeys.removeAll { $0 == key }
    }
}
