//
//  APICache.swift
//  Services
//

import Foundation

/// Cache freshness tiers (seconds) for RPC responses. Centralises the cache
/// durations that were previously scattered as magic numbers across the service.
public enum CacheTTL {
    /// 30s — near-real-time surfaces (e.g. notifications).
    public static let realtime: TimeInterval = 30
    /// 60s — frequently-changing lists (feeds, library, comments, folders).
    public static let short: TimeInterval = 60
    /// 120s — semi-static browse data (explore, analytics, packs).
    public static let medium: TimeInterval = 120
    /// 300s — slow-changing detail (profiles, home feed, track metadata).
    public static let long: TimeInterval = 300
}

/// A thread-safe in-memory cache for API responses with configurable TTL.
public actor APICache {
    public static let shared = APICache()

    private struct CacheEntry {
        let data: Data
        let timestamp: Date
        let ttl: TimeInterval
        
        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }

    private var cache: [String: CacheEntry] = [:]
    /// Decoded values kept alongside `cache` so repeat hits skip re-decoding the same
    /// payload. Keyed identically; invalidated whenever the entry is (re)written.
    private var decodedValues: [String: any Sendable] = [:]
    /// In-flight network fetches per key, so concurrent misses for the same key share
    /// ONE round-trip instead of each hitting the network.
    private var inFlight: [String: Task<Data, Error>] = [:]

    /// Default TTL: 5 minutes.
    public static let defaultTTL: TimeInterval = CacheTTL.long

    public init() {}

    // MARK: - Public API

    /// Get a cached value if it exists and hasn't expired.
    public func get<T: Decodable & Sendable>(_ key: String) -> T? {
        guard let entry = cache[key], !entry.isExpired else {
            if cache[key] != nil {
                cache.removeValue(forKey: key)
                decodedValues.removeValue(forKey: key)
            }
            return nil
        }
        // Skip the JSON decode when we've already decoded this exact payload.
        if let cached = decodedValues[key] as? T { return cached }
        guard let value = try? JSONDecoder().decode(T.self, from: entry.data) else { return nil }
        decodedValues[key] = value
        return value
    }

    /// Caches an already-decoded value (from a fresh fetch) so the next `get` returns
    /// it without decoding the bytes again.
    public func storeDecoded<T: Sendable>(_ key: String, _ value: T) {
        decodedValues[key] = value
    }

    /// Returns fresh cached bytes for `key`, or runs `fetch` — coalescing concurrent
    /// callers for the same key onto a single in-flight fetch — then caches and
    /// returns the bytes.
    public func coalescedData(
        _ key: String,
        ttl: TimeInterval,
        fetch: @Sendable @escaping () async throws -> Data
    ) async throws -> Data {
        if let entry = cache[key], !entry.isExpired { return entry.data }
        if let existing = inFlight[key] { return try await existing.value }

        let task = Task { try await fetch() }
        inFlight[key] = task
        defer { inFlight[key] = nil }
        let data = try await task.value
        cache[key] = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
        decodedValues.removeValue(forKey: key)
        return data
    }

    /// Remove a specific entry.
    public func remove(_ key: String) {
        cache.removeValue(forKey: key)
        decodedValues.removeValue(forKey: key)
    }

    /// Remove all entries matching a prefix.
    public func removeAll(matching prefix: String) {
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        decodedValues = decodedValues.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Clear all cached data.
    public func clear() {
        cache.removeAll()
        decodedValues.removeAll()
        inFlight.values.forEach { $0.cancel() }
        inFlight.removeAll()
    }

    // MARK: - Convenience

    /// Build a cache key from an RPC function name and optional params.
    public static func key(_ function: String, params: [String: Any]? = nil) -> String {
        guard let params, !params.isEmpty else { return "rpc:\(function)" }
        let sortedKeys = params.keys.sorted()
        let paramString = sortedKeys.map { "\($0)=\(params[$0] ?? "")" }.joined(separator: "&")
        return "rpc:\(function)?\(paramString)"
    }
}
