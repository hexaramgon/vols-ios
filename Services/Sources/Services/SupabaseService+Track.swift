//
//  SupabaseService+Track.swift
//  Services
//
//  Track-detail / analytics reads added for the web revamp port.
//

import Foundation

public extension SupabaseService {
    /// Raw listening segments for one of the caller's tracks
    /// (`get_track_heatmap`): one array per ended session, each a list of
    /// `[start, end]` second ranges. Owner-only — the RPC returns `[]` for a
    /// track the caller didn't upload. Roll it up with `heatmapCounts(_:)`.
    func getTrackHeatmap(trackId: String) async throws -> [[[Double]]] {
        try await cachedRpc("get_track_heatmap", params: ["p_track_id": trackId], ttl: CacheTTL.medium)
    }

    /// Per-second listen counts from heatmap sessions — mirrors the web's
    /// `fetchTrackHeatmap`: every second a segment covers counts one listen.
    /// Malformed segments (fewer than two bounds) are skipped.
    nonisolated static func heatmapCounts(_ sessions: [[[Double]]]) -> [Int] {
        let segments = sessions.joined().filter { $0.count >= 2 && $0[0].isFinite && $0[1].isFinite }
        guard let maxEnd = segments.map({ $0[1] }).max(), maxEnd > 0 else { return [] }
        var counts = [Int](repeating: 0, count: Int(maxEnd.rounded(.up)) + 1)
        for segment in segments {
            var second = max(Int(segment[0].rounded(.down)), 0)
            let end = Int(segment[1].rounded(.up))
            while second < end, second < counts.count {
                counts[second] += 1
                second += 1
            }
        }
        return counts
    }
}
