//
//  APICache.swift
//  Services
//

import Foundation

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

    /// Default TTL: 5 minutes
    public static let defaultTTL: TimeInterval = 300

    public init() {}

    // MARK: - Public API

    /// Get a cached value if it exists and hasn't expired.
    public func get<T: Decodable & Sendable>(_ key: String) -> T? {
        guard let entry = cache[key], !entry.isExpired else {
            if cache[key] != nil {
                cache.removeValue(forKey: key)
            }
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: entry.data)
    }

    /// Store a value in the cache.
    public func set<T: Encodable>(_ key: String, value: T, ttl: TimeInterval = APICache.defaultTTL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        cache[key] = CacheEntry(data: data, timestamp: Date(), ttl: ttl)
    }

    /// Remove a specific entry.
    public func remove(_ key: String) {
        cache.removeValue(forKey: key)
    }

    /// Remove all entries matching a prefix.
    public func removeAll(matching prefix: String) {
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
    }

    /// Clear all cached data.
    public func clear() {
        cache.removeAll()
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
