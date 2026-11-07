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

/// A thread-safe cache for API responses with configurable TTL.
///
/// Fresh entries (inside their TTL) answer reads as before. Expired entries are
/// KEPT (LRU-bounded) as an offline fallback: `stale(_:)` returns them when a
/// refetch fails for lack of network, so e.g. your profile — and with it your
/// avatar's image link — still shows in airplane mode. The entries are also
/// mirrored to a file in Caches so that works on a cold launch offline too.
/// `clear()` (sign-out) deletes the file.
public actor APICache {
    public static let shared = APICache()

    private struct CacheEntry {
        let data: Data
        let timestamp: Date
        let ttl: TimeInterval
        /// Bumped on every read — the LRU eviction victim is the smallest.
        var lastAccess: UInt64 = 0

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > ttl
        }
    }

    /// LRU bound: keys embed ids (profiles, folders, listings…), so an
    /// unbounded map retained every payload a browsing session ever touched —
    /// plus its decoded twin — until sign-out. ~256 ≈ a long session's worth.
    private static let maxEntries = 256
    /// Monotonic access clock for the LRU ordering.
    private var accessClock: UInt64 = 0

    private var cache: [String: CacheEntry] = [:]
    /// Decoded values kept alongside `cache` so repeat hits skip re-decoding the same
    /// payload. Keyed identically; invalidated whenever the entry is (re)written.
    private var decodedValues: [String: any Sendable] = [:]
    /// In-flight network fetches per key, so concurrent misses for the same key share
    /// ONE round-trip instead of each hitting the network. The token identifies
    /// the fetch: invalidation drops the entry, and a fetch whose token is gone
    /// when it lands doesn't write to the cache.
    private var inFlight: [String: (token: UUID, task: Task<Data, Error>)] = [:]

    // MARK: Disk mirror

    private struct StoredEntry: Codable {
        let key: String
        let data: Data
        let timestamp: Date
        let ttl: TimeInterval
    }

    private static let fileURL: URL? = FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("api-cache.json")
    private var loadedFromDisk = false
    private var saveTask: Task<Void, Never>?

    /// Default TTL: 5 minutes.
    public static let defaultTTL: TimeInterval = CacheTTL.long

    public init() {}

    // MARK: - Public API

    /// Get a cached value if it exists and hasn't expired. (Expired entries
    /// stay for `stale(_:)`.)
    public func get<T: Decodable & Sendable>(_ key: String) -> T? {
        loadFromDiskIfNeeded()
        guard let entry = cache[key], !entry.isExpired else { return nil }
        touch(key)
        // Skip the JSON decode when we've already decoded this exact payload.
        if let cached = decodedValues[key] as? T { return cached }
        guard let value = try? JSONDecoder.api.decode(T.self, from: entry.data) else { return nil }
        decodedValues[key] = value
        return value
    }

    /// The last cached value for `key`, expired or not — the fallback when a
    /// refetch fails because there's no network.
    public func stale<T: Decodable & Sendable>(_ key: String) -> T? {
        loadFromDiskIfNeeded()
        guard let entry = cache[key] else { return nil }
        touch(key)
        if let cached = decodedValues[key] as? T { return cached }
        return try? JSONDecoder.api.decode(T.self, from: entry.data)
    }

    /// Caches an already-decoded value (from a fresh fetch) so the next `get` returns
    /// it without decoding the bytes again. Only if `data` is still what's cached —
    /// a fetch that was invalidated (or overtaken by a newer one) must not pin
    /// its stale decode over the current bytes.
    public func storeDecoded<T: Sendable>(_ key: String, _ value: T, decodedFrom data: Data) {
        guard cache[key]?.data == data else { return }
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
        loadFromDiskIfNeeded()
        if let entry = cache[key], !entry.isExpired {
            touch(key)
            return entry.data
        }
        if let existing = inFlight[key] { return try await existing.task.value }

        let token = UUID()
        let task = Task { try await fetch() }
        inFlight[key] = (token, task)
        let data: Data
        do {
            data = try await task.value
        } catch {
            if inFlight[key]?.token == token { inFlight[key] = nil }
            throw error
        }
        // Invalidated while in flight (a mutation's `remove`, or sign-out's
        // `clear`): hand the bytes to this caller, but don't cache them — they
        // predate the change, or belong to the previous account.
        guard inFlight[key]?.token == token else { return data }
        inFlight[key] = nil
        accessClock += 1
        cache[key] = CacheEntry(data: data, timestamp: Date(), ttl: ttl, lastAccess: accessClock)
        decodedValues.removeValue(forKey: key)
        evictIfNeeded()
        scheduleSave()
        return data
    }

    /// Marks `key` most-recently-used.
    private func touch(_ key: String) {
        accessClock += 1
        cache[key]?.lastAccess = accessClock
    }

    /// Drops least-recently-used entries (expired first) past `maxEntries`.
    /// O(n log n) over ≤ a few hundred entries, and only on insert overflow.
    private func evictIfNeeded() {
        guard cache.count > Self.maxEntries else { return }
        let overflow = cache.count - Self.maxEntries
        let victims = cache
            .sorted { lhs, rhs in
                if lhs.value.isExpired != rhs.value.isExpired { return lhs.value.isExpired }
                return lhs.value.lastAccess < rhs.value.lastAccess
            }
            .prefix(overflow)
        for (key, _) in victims {
            cache.removeValue(forKey: key)
            decodedValues.removeValue(forKey: key)
        }
    }

    /// Remove a specific entry.
    public func remove(_ key: String) {
        cache.removeValue(forKey: key)
        decodedValues.removeValue(forKey: key)
        inFlight.removeValue(forKey: key)
        scheduleSave()
    }

    /// Remove all entries matching a prefix.
    public func removeAll(matching prefix: String) {
        cache = cache.filter { !$0.key.hasPrefix(prefix) }
        decodedValues = decodedValues.filter { !$0.key.hasPrefix(prefix) }
        inFlight = inFlight.filter { !$0.key.hasPrefix(prefix) }
        scheduleSave()
    }

    /// Clear all cached data.
    public func clear() {
        cache.removeAll()
        decodedValues.removeAll()
        inFlight.values.forEach { $0.task.cancel() }
        inFlight.removeAll()
        // Nothing of the previous account may survive on disk.
        saveTask?.cancel()
        saveTask = nil
        loadedFromDisk = true
        if let url = Self.fileURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Disk mirror

    /// Once per launch, before the first read: restore the last session's
    /// entries (only ever served fresh-within-TTL or as the offline fallback).
    private func loadFromDiskIfNeeded() {
        guard !loadedFromDisk else { return }
        loadedFromDisk = true
        guard let url = Self.fileURL,
              let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode([StoredEntry].self, from: data) else { return }
        for entry in stored where cache[entry.key] == nil {
            accessClock += 1
            cache[entry.key] = CacheEntry(data: entry.data, timestamp: entry.timestamp, ttl: entry.ttl, lastAccess: accessClock)
        }
        evictIfNeeded()
    }

    /// Writes the entries a moment after the last change (coalesces bursts).
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.writeToDisk()
        }
    }

    private func writeToDisk() {
        guard let url = Self.fileURL else { return }
        let stored = cache.map { StoredEntry(key: $0.key, data: $0.value.data, timestamp: $0.value.timestamp, ttl: $0.value.ttl) }
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
