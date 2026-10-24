//
//  AnalyticsViewModel.swift
//  Volspire
//
//  Loads the creator's per-track analytics (get_my_track_analytics) for the
//  web-matched "Your tracks" list + selected-track detail, and the selected
//  track's listening heatmap (get_track_heatmap) on demand.
//

import Foundation
import Observation
import Services
import SharedUtilities

struct TrackAnalyticsItem: Identifiable {
    let id: String
    let title: String
    let coverURL: URL?
    let streams: Int
    let uniqueListeners: Int
    let avgListenTime: Double
    let avgSeekCount: Double
    let dailyPlays: [ApiTrackAnalytics.DailyPlay]
    let sources: [String: Int]
    let genre: String?
    let createdAt: Date?

    /// This track's plays per day over the last 30 days (oldest → today).
    let dailyPlaysSeries: [Int]

    /// Plays in the last 7 days.
    var thisWeek: Int { dailyPlaysSeries.suffix(7).reduce(0, +) }
    /// Plays in days 8–14.
    var lastWeek: Int { dailyPlaysSeries.dropLast(7).suffix(7).reduce(0, +) }
    /// Week-over-week change, as the web's `weekDelta`.
    var weekDelta: Int { AnalyticsViewModel.weekDelta(thisWeek: thisWeek, lastWeek: lastWeek) }

    /// This track's source breakdown as (label, count), highest first —
    /// keys that share a label ("home_board" + "home_feed" → "Home") merged
    /// into one bar.
    var sortedSources: [(key: String, count: Int)] {
        var byLabel: [String: Int] = [:]
        for (key, count) in sources {
            byLabel[AnalyticsViewModel.sourceLabel(key), default: 0] += count
        }
        return byLabel.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }
}

@Observable @MainActor
final class AnalyticsViewModel {
    private(set) var tracks: [TrackAnalyticsItem] = []
    private(set) var loaded = false
    /// The last load got no response (used as an offline indicator).
    private(set) var loadFailed = false
    /// The track shown in the detail — nil falls back to the first (top) track.
    var selectedId: String?
    /// Per-second listen counts per track id, once its heatmap has loaded.
    private(set) var heatmaps: [String: [Int]] = [:]

    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(supabaseService: SupabaseService = SupabaseService(),
         storageService: StorageService = StorageService()) {
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    var selected: TrackAnalyticsItem? {
        tracks.first { $0.id == selectedId } ?? tracks.first
    }

    func load() async {
        do {
            tracks = try await supabaseService.getMyTrackAnalytics().map { row in
                TrackAnalyticsItem(
                    id: row.trackId,
                    title: row.title,
                    coverURL: storageService.resolveTrackUrl(row.coverUrl).flatMap { URL(string: $0) },
                    streams: row.streams,
                    uniqueListeners: row.uniqueListeners,
                    avgListenTime: row.avgListenTime,
                    avgSeekCount: row.avgSeekCount,
                    dailyPlays: row.dailyPlays,
                    sources: row.sources,
                    genre: row.genre,
                    createdAt: MessageTime.parse(row.createdAt),
                    dailyPlaysSeries: Self.dailySeries(from: row.dailyPlays)
                )
            }
            loadFailed = false
        } catch {
            debugLog("[AnalyticsVM] Failed to load analytics: \(error)")
            loadFailed = true
        }
        loaded = true
    }

    /// Fetches a track's heatmap once (cached by the service afterwards). A
    /// failure leaves it unloaded, so the chart keeps its skeleton rather than
    /// claiming "No listening data yet."
    func loadHeatmap(trackId: String) async {
        guard heatmaps[trackId] == nil else { return }
        do {
            let sessions = try await supabaseService.getTrackHeatmap(trackId: trackId)
            heatmaps[trackId] = SupabaseService.heatmapCounts(sessions)
        } catch {
            debugLog("[AnalyticsVM] Failed to load heatmap: \(error)")
        }
    }

    // MARK: - Aggregates (Profile's dashboard card)

    /// Total plays per day over the last 30 days (oldest → today), all tracks.
    private var dailyPlays: [Int] {
        Self.dailySeries(from: tracks.flatMap { $0.dailyPlays })
    }

    /// Total plays counted in the last 30 days.
    var playsLast30: Int { dailyPlays.reduce(0, +) }

    /// Week-over-week change across all tracks (last 7 days vs the 7 before).
    var weekTrend: Int {
        let series = dailyPlays
        return Self.weekDelta(thisWeek: series.suffix(7).reduce(0, +),
                              lastWeek: series.dropLast(7).suffix(7).reduce(0, +))
    }

    /// Builds a 30-day (oldest → today) plays series from raw daily-play rows.
    nonisolated static func dailySeries(from days: [ApiTrackAnalytics.DailyPlay]) -> [Int] {
        var byDate: [String: Int] = [:]
        for day in days { byDate[day.date, default: 0] += day.plays }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let today = Date()
        return (0...29).reversed().compactMap { offset -> Int? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return byDate[formatter.string(from: day)] ?? 0
        }
    }

    /// round((tw − lw) / lw · 100); a zero prior week reads 100 (or 0 when
    /// both are empty) — the web's `weekDelta`.
    nonisolated static func weekDelta(thisWeek: Int, lastWeek: Int) -> Int {
        if lastWeek == 0 { return thisWeek > 0 ? 100 : 0 }
        return Int(((Double(thisWeek) - Double(lastWeek)) / Double(lastWeek) * 100).rounded())
    }

    /// A play source key as a readable label. Known keys get a name; any
    /// other ("home_insight", "profile-credits") is humanized — separators
    /// to spaces, first letter capitalized — so no raw key ever shows.
    nonisolated static func sourceLabel(_ key: String) -> String {
        switch key {
        case "explore", "explore_details": "Explore"
        case "explore_billboard": "Explore spotlight"
        case "home_board", "home_feed", "home_default", "home_insight": "Home"
        case "profile": "Profile"
        case "profile-credits", "profile_credits": "Profile credits"
        case "library": "Library"
        case "direct_link": "Direct link"
        case "search": "Search"
        case "following": "Following"
        case "collab": "Collab"
        case "workspace": "Workspace"
        case "seed", "": "Other"
        default:
            {
                let words = key.replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .lowercased()
                return words.prefix(1).uppercased() + words.dropFirst()
            }()
        }
    }
}
