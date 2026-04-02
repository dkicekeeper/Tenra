//
//  LRUCache.swift
//  AIFinanceManager
//
//  Created on 2026-02-02
//  Part of: Subscriptions & Recurring Transactions Full Rebuild - Phase 3
//  Purpose: Generic LRU (Least Recently Used) cache to prevent memory leaks
//

import Foundation

/// A generic LRU (Least Recently Used) cache implementation
/// Automatically evicts least recently used items when capacity is exceeded
/// Thread-safe for concurrent access
@MainActor
class LRUCache<Key: Hashable, Value> {

    // MARK: - Private Types

    /// Node in the doubly-linked list
    fileprivate class Node {
        let key: Key
        var value: Value
        var prev: Node?
        var next: Node?

        init(key: Key, value: Value) {
            self.key = key
            self.value = value
        }
    }

    // MARK: - Properties

    private var cache: [Key: Node] = [:]
    private var head: Node?  // Most recently used
    private var tail: Node?  // Least recently used
    private let capacity: Int

    /// Current number of items in cache
    var count: Int {
        cache.count
    }

    /// Cache hit rate statistics (for monitoring)
    private(set) var hits: Int = 0
    private(set) var misses: Int = 0

    var hitRate: Double {
        let total = hits + misses
        return total > 0 ? Double(hits) / Double(total) : 0.0
    }

    // MARK: - Initialization

    /// Initialize LRU cache with specified capacity
    /// - Parameter capacity: Maximum number of items to store
    init(capacity: Int) {
        precondition(capacity > 0, "LRU Cache capacity must be greater than 0")
        self.capacity = capacity
    }

    // MARK: - Public Methods

    /// Get value for key, moving it to front (most recently used)
    /// - Parameter key: The key to look up
    /// - Returns: The value if found, nil otherwise
    func get(_ key: Key) -> Value? {
        guard let node = cache[key] else {
            misses += 1
            return nil
        }

        hits += 1
        moveToHead(node)
        return node.value
    }

    /// Set value for key, adding to front (most recently used)
    /// - Parameters:
    ///   - key: The key to set
    ///   - value: The value to store
    func set(_ key: Key, value: Value) {
        if let existingNode = cache[key] {
            // Update existing
            existingNode.value = value
            moveToHead(existingNode)
        } else {
            // Add new
            let newNode = Node(key: key, value: value)
            cache[key] = newNode
            addToHead(newNode)

            // Evict LRU if over capacity
            if cache.count > capacity {
                evictLRU()
            }
        }
    }

    /// Remove value for key
    /// - Parameter key: The key to remove
    func remove(_ key: Key) {
        guard let node = cache[key] else { return }
        removeNode(node)
        cache.removeValue(forKey: key)
    }

    /// Clear all items from cache
    func removeAll() {
        cache.removeAll()
        head = nil
        tail = nil
        hits = 0
        misses = 0
    }

    /// Check if key exists in cache without affecting LRU order
    /// - Parameter key: The key to check
    /// - Returns: True if key exists
    func contains(_ key: Key) -> Bool {
        cache[key] != nil
    }

    /// Get all keys in cache (ordered from most to least recently used)
    var keys: [Key] {
        var result: [Key] = []
        var current = head
        while let node = current {
            result.append(node.key)
            current = node.next
        }
        return result
    }

    // MARK: - Private Methods

    /// Move node to head (most recently used)
    private func moveToHead(_ node: Node) {
        guard node !== head else { return }
        removeNode(node)
        addToHead(node)
    }

    /// Add node to head (most recently used position)
    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil

        if let head = head {
            head.prev = node
        }

        head = node

        if tail == nil {
            tail = node
        }
    }

    /// Remove node from linked list
    private func removeNode(_ node: Node) {
        let prev = node.prev
        let next = node.next

        if let prev = prev {
            prev.next = next
        } else {
            head = next
        }

        if let next = next {
            next.prev = prev
        } else {
            tail = prev
        }

        node.prev = nil
        node.next = nil
    }

    /// Evict least recently used item (tail)
    private func evictLRU() {
        guard let tail = tail else { return }
        cache.removeValue(forKey: tail.key)
        removeNode(tail)
    }

    // MARK: - Debug

    #if DEBUG
    /// Debug description of cache state
    var debugDescription: String {
        let items = keys.map { "\($0)" }.joined(separator: " -> ")
        return """
        LRUCache(capacity: \(capacity), count: \(count), hitRate: \(String(format: "%.1f%%", hitRate * 100)))
        Order (MRU -> LRU): \(items)
        """
    }
    #endif
}

// MARK: - Subscript Support

extension LRUCache {
    /// Subscript access for convenient get/set
    subscript(key: Key) -> Value? {
        get {
            get(key)
        }
        set {
            if let value = newValue {
                set(key, value: value)
            } else {
                remove(key)
            }
        }
    }
}

// MARK: - Sequence Support

extension LRUCache: Sequence {
    /// Iterator for LRU cache
    /// Iterates from most recently used to least recently used
    struct Iterator: IteratorProtocol {
        private var currentKeys: [Key]
        private var currentIndex: Int
        private let cache: [Key: Node]

        fileprivate init(keys: [Key], cache: [Key: Node]) {
            self.currentKeys = keys
            self.currentIndex = 0
            self.cache = cache
        }

        mutating func next() -> (key: Key, value: Value)? {
            guard currentIndex < currentKeys.count else { return nil }
            let key = currentKeys[currentIndex]
            currentIndex += 1
            guard let node = cache[key] else { return nil }
            return (key: key, value: node.value)
        }
    }

    func makeIterator() -> Iterator {
        Iterator(keys: keys, cache: cache)
    }
}
