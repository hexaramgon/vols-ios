//
//  AnalyticsViewModel.swift
//  Volspire
//
//  Loads the creator's per-track analytics (get_my_track_analytics) and derives
//  the summary aggregates shown on the dashboard.
//

import Foundation
import Observation
import Services

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

    /// This track's plays per day over the last 30 days (oldest → today).
    var dailyPlaysSeries: [Int] { AnalyticsViewModel.dailySeries(from: dailyPlays) }

    /// This track's source breakdown (label, count), highest first.
    var sortedSources: [(label: String, count: Int)] {
        sources.sorted { $0.value > $1.value }.map { (AnalyticsViewModel.sourceLabel($0.key), $0.value) }
    }
}

@Observable @MainActor
final class AnalyticsViewModel {
    private(set) var tracks: [TrackAnalyticsItem] = []
    /// Audience engagement (followers / likes / saves / comments + 30d deltas).
    /// Optional: the dashboard still renders without it if the RPC fails.
    private(set) var engagement: ApiEngagementStats?
    private(set) var loaded = false
    /// The last load got no response (used as an offline indicator).
    private(set) var loadFailed = false

    private let supabaseService: SupabaseService
    private let storageService: StorageService

    init(supabaseService: SupabaseService = SupabaseService(),
         storageService: StorageService = StorageService()) {
        self.supabaseService = supabaseService
        self.storageService = storageService
    }

    func load() async {
        // Engagement loads alongside the track analytics; it's additive, so a
        // failure there never blocks the dashboard.
        async let engagementResult = supabaseService.getMyEngagementStats()
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
                    genre: row.genre
                )
            }
            loadFailed = false
        } catch {
            print("[AnalyticsVM] Failed to load analytics: \(error)")
            loadFailed = true
        }
        engagement = try? await engagementResult
        loaded = true
    }

    // MARK: - Aggregates

    var totalStreams: Int { tracks.reduce(0) { $0 + $1.streams } }
    var totalListeners: Int { tracks.reduce(0) { $0 + $1.uniqueListeners } }

    /// Stream-weighted average listen time, in whole seconds.
    var avgListenSeconds: Int {
        let streams = totalStreams
        guard streams > 0 else { return 0 }
        let weighted = tracks.reduce(0.0) { $0 + $1.avgListenTime * Double($1.streams) }
        return Int((weighted / Double(streams)).rounded())
    }

    /// Total plays counted in the last 30 days.
    var playsLast30: Int { dailyPlays.reduce(0, +) }

    /// Week-over-week change (last 7 days vs the 7 before), as a percentage.
    var weekTrend: Int { Self.weekTrend(from: dailyPlays) }

    /// The plays series for the selected window (7 or 30 days, oldest → today).
    func plays(last days: Int) -> [Int] { Array(dailyPlays.suffix(days)) }

    /// Trend for a window: its most recent half vs the half before it, as a
    /// percentage (so the pill stays meaningful for both 7D and 30D).
    func trend(days: Int) -> Int {
        let series = Array(dailyPlays.suffix(days))
        let half = max(days / 2, 1)
        let recent = series.suffix(half).reduce(0, +)
        let prior = series.dropLast(half).suffix(half).reduce(0, +)
        if prior == 0 { return recent > 0 ? 100 : 0 }
        return Int(((Double(recent) - Double(prior)) / Double(prior) * 100).rounded())
    }

    /// Total source-attributed plays (denominator for source percentages).
    var totalSourcePlays: Int {
        tracks.reduce(0) { $0 + $1.sources.values.reduce(0, +) }
    }

    /// Total plays per day over the last 30 days (oldest → today), all tracks.
    var dailyPlays: [Int] {
        Self.dailySeries(from: tracks.flatMap { $0.dailyPlays })
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

    /// Week-over-week % change from a 30-day series.
    nonisolated static func weekTrend(from series: [Int]) -> Int {
        let thisWeek = series.suffix(7).reduce(0, +)
        let lastWeek = series.dropLast(7).suffix(7).reduce(0, +)
        if lastWeek == 0 { return thisWeek > 0 ? 100 : 0 }
        return Int(((Double(thisWeek) - Double(lastWeek)) / Double(lastWeek) * 100).rounded())
    }

    /// Top play sources across all tracks (label, count), highest first.
    var topSources: [(label: String, count: Int)] {
        var agg: [String: Int] = [:]
        for track in tracks {
            for (source, count) in track.sources {
                agg[source, default: 0] += count
            }
        }
        return agg.sorted { $0.value > $1.value }
            .prefix(5)
            .map { (Self.sourceLabel($0.key), $0.value) }
    }

    nonisolated static func sourceLabel(_ key: String) -> String {
        switch key {
        case "explore": "Explore"
        case "profile": "Profile"
        case "library": "Library"
        case "direct_link": "Direct link"
        case "search": "Search"
        case "home_feed": "Home"
        case "profile-credits": "Credits"
        default: key.capitalized
        }
    }
}
