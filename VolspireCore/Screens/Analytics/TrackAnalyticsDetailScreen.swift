//
//  TrackAnalyticsDetailScreen.swift
//  Volspire
//
//  The selected track's numbers, under the "Your tracks" list on the
//  analytics page (the web's phone layout stacks list above detail). In
//  order, 40pt apart: the track, "This week", four stat tiles, plays over the
//  last 30 days, where people listen (heatmap), how people found it.
//

import DesignSystem
import SwiftUI

struct TrackAnalyticsDetail: View {
    let track: TrackAnalyticsItem
    let viewModel: AnalyticsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            header
            thisWeekCard
            statTiles
            playsChart
            listeningChart
            AnalyticsBlock(title: "How people found it") {
                if track.sortedSources.isEmpty {
                    AnalyticsEmptyNote(text: "No source data yet.")
                } else {
                    AnalyticsSourceBars(sources: track.sortedSources)
                }
            }
        }
        .task(id: track.id) { await viewModel.loadHeatmap(trackId: track.id) }
    }
}

// MARK: - Track + this week

private extension TrackAnalyticsDetail {
    var header: some View {
        AnalyticsSubjectHeader(title: track.title, caption: headerCaption) {
            ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: Radius.tile)
        }
    }

    /// "Genre · Uploaded Oct 3, 2026" — empty parts dropped.
    var headerCaption: String {
        var parts: [String] = []
        if let genre = track.genre, !genre.isEmpty { parts.append(genre) }
        if let date = track.createdAt {
            parts.append("Uploaded \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
        }
        return parts.joined(separator: " · ")
    }

    /// Titled like the other blocks (the heading above the card, not a
    /// caption inside it).
    var thisWeekCard: some View {
        AnalyticsBlock(title: "This week") { thisWeekBody }
    }

    private var thisWeekBody: some View {
        let delta = track.weekDelta
        return HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                let count = Text(track.thisWeek.compactCount).font(.appLargeTitle).foregroundStyle(Color.vText)
                let unit = Text(track.thisWeek == 1 ? "play" : "plays").font(.appSubheadline).foregroundStyle(Color.vText3)
                Text("\(count) \(unit)").monospacedDigit()
                // The number bold, in full ink; the words stay quiet.
                let before = Text(track.lastWeek.compactCount).font(.appLabel).foregroundStyle(Color.vText)
                Text("\(before) the week before")
                    .font(.appCaption).foregroundStyle(Color.vText3).monospacedDigit()
            }
            Spacer(minLength: 0)
            if delta != 0 {
                let up = delta > 0
                HStack(spacing: 6) {
                    LucideIcon(up ? .trendingUp : .trendingDown, .md)
                    Text("\(up ? "+" : "")\(delta)% vs last week")
                        .font(.appSubheadlineSemibold).monospacedDigit()
                }
                .foregroundStyle(up ? Color.vSuccessText : Color.vError)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background((up ? Color.vSuccess : Color.vDestructive).opacity(0.10), in: Capsule())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    var statTiles: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                AnalyticsStatTile(label: "Streams",
                                  value: track.streams.compactCount, sub: "Every play, replays included")
                AnalyticsStatTile(label: "Listeners",
                                  value: track.uniqueListeners.compactCount, sub: "Different people")
            }
            GridRow {
                AnalyticsStatTile(label: "Avg listen",
                                  value: track.avgListenTime.durationLabel, sub: "Before stopping or skipping")
                AnalyticsStatTile(label: "Avg seeks",
                                  value: "\(Int(track.avgSeekCount.rounded()))", sub: "Scrubs per listen")
            }
        }
    }
}

// MARK: - Charts

private extension TrackAnalyticsDetail {
    /// "Oct 3" for the point `daysAgo` days before today.
    func dateLabel(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    var playsChart: some View {
        let days = track.dailyPlaysSeries
        let total = days.reduce(0, +)
        return AnalyticsBlock(title: "Plays, last 30 days", aside: "\(total.compactCount) total") {
            AnalyticsLineChart(
                values: days.map(Double.init),
                xLabels: (dateLabel(daysAgo: days.count - 1), dateLabel(daysAgo: days.count - 1 - 15), "Today"),
                readout: { i in
                    let plays = days[i]
                    return (i == days.count - 1 ? "Today" : dateLabel(daysAgo: days.count - 1 - i),
                            "\(plays.compactCount) \(plays == 1 ? "play" : "plays")")
                }
            )
        }
    }

    @ViewBuilder
    var listeningChart: some View {
        let heatmap = viewModel.heatmaps[track.id]
        let buckets = heatmap.map(Self.buckets) ?? []
        let duration = heatmap?.count ?? 0
        let peakSec = heatmap.flatMap { h in h.indices.max(by: { h[$0] < h[$1] }) } ?? 0
        AnalyticsBlock(
            title: "Where people listen",
            aside: buckets.isEmpty ? nil : "Most played at \(peakSec.durationLabel)"
        ) {
            if heatmap == nil {
                // In flight (or failed) — a bone, never the "no data" claim.
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Color.vSkeleton)
                    .frame(height: 140)
                    .shimmering()
            } else if buckets.isEmpty {
                AnalyticsEmptyNote(text: "No listening data yet.")
            } else {
                let secAt = { (i: Int) -> Int in
                    Int(((buckets.count <= 1 ? 0 : Double(i) / Double(buckets.count - 1)) * Double(duration)).rounded())
                }
                AnalyticsLineChart(
                    values: buckets,
                    xLabels: ("0:00", Int((Double(duration) / 2).rounded()).durationLabel, duration.durationLabel),
                    readout: { i in
                        let listens = Int(buckets[i].rounded())
                        return (secAt(i).durationLabel, "\(listens) \(listens == 1 ? "listen" : "listens")")
                    }
                )
            }
        }
    }

    /// Averages per-second counts into at most 120 buckets so long tracks
    /// stay readable (the web's ListeningChart roll-up).
    static func buckets(_ heatmap: [Int]) -> [Double] {
        let n = min(heatmap.count, 120)
        guard n > 0 else { return [] }
        let size = Double(heatmap.count) / Double(n)
        return (0 ..< n).map { i in
            let lo = Int((Double(i) * size).rounded(.down))
            let hi = min(Int((Double(i + 1) * size).rounded(.down)), heatmap.count)
            let slice = heatmap[lo ..< max(hi, lo)]
            return Double(slice.reduce(0, +)) / Double(max(slice.count, 1))
        }
    }
}
