//
//  SupabaseAnalyticsSink.swift
//  Volspire
//
//  The default sink: writes to the same Supabase RPCs the web app uses
//  (`log_analytics_event` + `increment_track_stream`), so iOS and web land in
//  the one `analytics_events` table with an identical shape. This is the only
//  file that knows the transport — swap it to change events backend.
//

import Foundation
import SharedUtilities
import Supabase

public final class SupabaseAnalyticsSink: AnalyticsSink {
    private let client: SupabaseClient

    public init(client: SupabaseClient = supabaseClient) {
        self.client = client
    }

    public func send(_ event: AnalyticsEvent) async {
        do {
            _ = try await client
                .rpc("log_analytics_event", params: LogParams(
                    p_event_type: event.type.rawValue,
                    p_track_id: event.trackId,
                    p_session_id: event.sessionId,
                    p_metadata: .object(event.metadata)
                ))
                .execute()
            debugLog("[analytics] ✓ \(event.type.rawValue) track=\(event.trackId ?? "-")")
        } catch {
            debugLog("[analytics] ✗ \(event.type.rawValue) failed: \(error)")
        }
    }

    public func incrementStream(trackId: String, sessionId: String, metadata: [String: AnalyticsValue]) async {
        do {
            _ = try await client
                .rpc("increment_track_stream", params: StreamParams(
                    p_track_id: trackId,
                    p_session_id: sessionId,
                    p_metadata: .object(metadata)
                ))
                .execute()
            debugLog("[analytics] ✓ stream_counted track=\(trackId)")
        } catch {
            debugLog("[analytics] ✗ increment_track_stream failed: \(error)")
        }
    }
}

// RPC parameter envelopes. Property names match the SQL function's arg names so
// PostgREST binds them positionally-by-name; metadata rides as nested jsonb.
private struct LogParams: Encodable, Sendable {
    let p_event_type: String
    let p_track_id: String?
    let p_session_id: String
    let p_metadata: AnalyticsValue

    // Encode p_track_id even when nil (as JSON null). Swift's synthesized Encodable
    // uses encodeIfPresent for optionals, which OMITS a nil — so page_view events (no
    // track) called log_analytics_event with only 3 args and PostgREST couldn't match
    // the 4-arg function (PGRST202). Explicit null keeps all four args present.
    enum CodingKeys: String, CodingKey {
        case p_event_type, p_track_id, p_session_id, p_metadata
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_event_type, forKey: .p_event_type)
        try c.encode(p_track_id, forKey: .p_track_id)
        try c.encode(p_session_id, forKey: .p_session_id)
        try c.encode(p_metadata, forKey: .p_metadata)
    }
}

private struct StreamParams: Encodable, Sendable {
    let p_track_id: String
    let p_session_id: String
    let p_metadata: AnalyticsValue
}
