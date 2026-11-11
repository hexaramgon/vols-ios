//
//  PackAnalyticsScreen.swift
//  Volspire
//
//  Pack Analytics — the owner's performance page for one pack, opened from the
//  "Pack Analytics" card on their pack (like Profile's Artist Dashboard →
//  Analytics). Built from the track Analytics pieces: stat tiles, the 30-day
//  line chart, titled blocks. Data: owner-only `get_pack_stats` (views exclude
//  the owner's own; download people are recorded since 2026-11-05).
//

import DesignSystem
import Services
import SwiftUI

struct PackAnalyticsScreen: View {
    let packId: String
    let packName: String
    let coverURL: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(PlayerController.self) private var playerController

    @State private var stats: ApiPackStats?
    @State private var failed = false

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 16)
                .padding(.bottom, playerController.contentBottomInset + 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await load() }
        .appNavBar(title: "Pack Analytics") { dismiss() }
        .task { await load() }
    }

    // The pack itself opens the page (like Track Analytics) — not the nav bar.
    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            AnalyticsSubjectHeader(title: packName, caption: "Sample pack") {
                // The pack page's own art: its cover, else its name mesh.
                Group {
                    if let url = coverURL.flatMap(URL.init(string:)) {
                        ArtworkView(.webImage(url), cornerRadius: 0)
                    } else {
                        PlaylistCoverFallback(name: packName, icon: nil)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            }
            statsContent
        }
    }

    @ViewBuilder
    private var statsContent: some View {
        if failed && stats == nil {
            LoadErrorView(title: "Couldn't load analytics") { Task { await load() } }
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.5)
        } else {
            let s = stats ?? Self.placeholder
            VStack(alignment: .leading, spacing: 32) {
                tiles(s)
                viewsChart(s)
                allTime(s)
            }
            // Shaped placeholder until the numbers land (never fake zeros).
            .redacted(reason: stats == nil ? .placeholder : [])
            .loadingCrossfade(stats != nil)
        }
    }

    private func load() async {
        do {
            stats = try await dependencies.supabaseService.getPackStats(packId: packId)
            failed = false
        } catch {
            failed = true
        }
    }

    // MARK: Pieces

    private func tiles(_ s: ApiPackStats) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                AnalyticsStatTile(label: "Views",
                                  value: s.viewsLast30Days.compactCount,
                                  sub: "Last 30 days · \(s.viewersLast30Days.compactCount) \(s.viewersLast30Days == 1 ? "person" : "people")")
                AnalyticsStatTile(label: "Downloads",
                                  value: s.downloadsTotal.compactCount,
                                  sub: "\(s.downloaders.compactCount) \(s.downloaders == 1 ? "person" : "people") since Nov 5")
            }
            GridRow {
                AnalyticsStatTile(label: "Saves",
                                  value: s.savesTotal.compactCount,
                                  sub: "+\(s.savesLast30Days.compactCount) in the last 30 days")
                AnalyticsStatTile(label: "Rating",
                                  value: s.reviewCount > 0 ? String(format: "%.1f", s.avgRating) : "–",
                                  sub: s.reviewCount == 0 ? "No reviews yet"
                                      : "\(s.reviewCount.compactCount) \(s.reviewCount == 1 ? "review" : "reviews")")
            }
        }
    }

    private func viewsChart(_ s: ApiPackStats) -> some View {
        let views = s.daily.map(\.views)
        return AnalyticsBlock(title: "Views, last 30 days", aside: "\(views.reduce(0, +).compactCount) total") {
            AnalyticsLineChart(
                values: views.map(Double.init),
                xLabels: (AnalyticsDates.label(s.daily.first?.date), AnalyticsDates.label(s.daily.dropFirst(15).first?.date), "Today"),
                readout: { i in
                    let day = s.daily[i]
                    return (i == s.daily.count - 1 ? "Today" : AnalyticsDates.label(day.date),
                            "\(day.views) \(day.views == 1 ? "view" : "views") · \(day.downloads) \(day.downloads == 1 ? "download" : "downloads")")
                }
            )
        }
    }

    private func allTime(_ s: ApiPackStats) -> some View {
        AnalyticsBlock(title: "All time") {
            AnalyticsTotals(items: [
                .init(label: "Views", value: s.viewsTotal.compactCount),
                .init(label: "Likes", value: s.likesTotal.compactCount),
            ])
        }
    }

    private static let placeholder = ApiPackStats(
        viewsTotal: 0, viewsLast30Days: 0, viewersLast30Days: 0, downloadsTotal: 0, downloaders: 0,
        downloadsLast30Days: 0, savesTotal: 0, savesLast30Days: 0, likesTotal: 0, avgRating: 0,
        reviewCount: 0, daily: (0 ..< 30).map { _ in .init(date: "", views: 0, downloads: 0, saves: 0) }
    )
}
