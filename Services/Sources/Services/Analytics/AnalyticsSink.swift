//
//  AnalyticsSink.swift
//  Volspire
//
//  The swappable boundary. Everything above this protocol speaks vendor-neutral
//  `AnalyticsEvent`s; everything below decides *where* they go. To migrate to a
//  different events backend, implement a new `AnalyticsSink` and inject it into
//  `AnalyticsService` — no call-site changes.
//

import Foundation

public protocol AnalyticsSink: Sendable {
    /// Records a single event. Implementations must never throw to the caller —
    /// analytics is best-effort and must not affect product flows.
    func send(_ event: AnalyticsEvent) async

    /// A counted stream (a play that crossed the "counts as a listen" threshold).
    /// Kept distinct from `send` because the canonical backend increments a
    /// durable counter here, not just an event row.
    func incrementStream(trackId: String, sessionId: String, metadata: [String: AnalyticsValue]) async
}

/// Drops everything. Use for previews and the dependency stub.
public struct NoopAnalyticsSink: AnalyticsSink {
    public init() {}
    public func send(_ event: AnalyticsEvent) async {}
    public func incrementStream(trackId: String, sessionId: String, metadata: [String: AnalyticsValue]) async {}
}
