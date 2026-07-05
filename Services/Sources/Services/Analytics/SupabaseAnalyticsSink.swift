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
            #if DEBUG
            print("[analytics] ✓ \(event.type.rawValue) track=\(event.trackId ?? "-")")
            #endif
        } catch {
            #if DEBUG
            print("[analytics] ✗ \(event.type.rawValue) failed: \(error)")
            #endif
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
            #if DEBUG
            print("[analytics] ✓ stream_counted track=\(trackId)")
            #endif
        } catch {
            #if DEBUG
            print("[analytics] ✗ increment_track_stream failed: \(error)")
            #endif
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
}

private struct StreamParams: Encodable, Sendable {
    let p_track_id: String
    let p_session_id: String
    let p_metadata: AnalyticsValue
}
