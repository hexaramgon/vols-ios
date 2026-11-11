//
//  ListingAnalyticsScreen.swift
//  Volspire
//
//  Listing Analytics — the author's performance page for one collab listing,
//  opened from the "Listing Analytics" card on their listing (like Pack
//  Analytics / Profile's Artist Dashboard). Same Analytics pieces: stat tiles,
//  the 30-day line chart, titled blocks. Data: author-only `get_listing_stats`.
//

import DesignSystem
import Services
import SwiftUI

struct ListingAnalyticsScreen: View {
    let listingId: String
    let listingTitle: String
    /// Raw category id — resolved to its label + icon for the header.
    let category: String

    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(PlayerController.self) private var playerController

    @State private var stats: ApiListingStats?
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
        .appNavBar(title: "Listing Analytics") { dismiss() }
        .task { await load() }
    }

    // The listing itself opens the page (like Track Analytics) — its category
    // tile (the thread's listing strip), title and category.
    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            AnalyticsSubjectHeader(title: listingTitle, caption: ListingCategory.label(category)) {
                LucideIcon(ListingCategory.icon(category), .xxl)
                    .foregroundStyle(Color.vOnColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.vAccent, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
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
            stats = try await dependencies.supabaseService.getListingStats(listingId: listingId)
            failed = false
        } catch {
            failed = true
        }
    }

    // MARK: Pieces

    private func tiles(_ s: ApiListingStats) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                AnalyticsStatTile(label: "Views",
                                  value: s.viewsLast30Days.compactCount,
                                  sub: "Last 30 days · \(people(s.viewersLast30Days))")
                AnalyticsStatTile(label: "Responses",
                                  value: s.responsesTotal.compactCount,
                                  sub: "+\(s.responsesLast30Days.compactCount) in the last 30 days")
            }
            GridRow {
                AnalyticsStatTile(label: "Saves",
                                  value: s.savesTotal.compactCount,
                                  sub: "+\(s.savesLast30Days.compactCount) in the last 30 days")
                AnalyticsStatTile(label: "Comments",
                                  value: s.commentsTotal.compactCount,
                                  sub: "+\(s.commentsLast30Days.compactCount) in the last 30 days")
            }
        }
    }

    private func viewsChart(_ s: ApiListingStats) -> some View {
        let views = s.daily.map(\.views)
        return AnalyticsBlock(title: "Views, last 30 days", aside: "\(views.reduce(0, +).compactCount) total") {
            AnalyticsLineChart(
                values: views.map(Double.init),
                xLabels: (AnalyticsDates.label(s.daily.first?.date), AnalyticsDates.label(s.daily.dropFirst(15).first?.date), "Today"),
                readout: { i in
                    let day = s.daily[i]
                    return (i == s.daily.count - 1 ? "Today" : AnalyticsDates.label(day.date),
                            "\(day.views) \(day.views == 1 ? "view" : "views") · \(day.responses) \(day.responses == 1 ? "response" : "responses")")
                }
            )
        }
    }

    /// All-time views and the share of distinct viewers who responded.
    private func allTime(_ s: ApiListingStats) -> some View {
        AnalyticsBlock(title: "All time") {
            AnalyticsTotals(items: [
                .init(label: "Views", value: s.viewsTotal.compactCount),
                .init(label: "Viewers", value: s.viewersTotal.compactCount),
                .init(label: "Response rate", value: responseRate(s)),
            ])
        }
    }

    /// Responses per person who viewed, as a percentage ("–" with no viewers).
    private func responseRate(_ s: ApiListingStats) -> String {
        guard s.viewersTotal > 0 else { return "–" }
        let pct = min(Double(s.responsesTotal) / Double(s.viewersTotal), 1) * 100
        return "\(Int(pct.rounded()))%"
    }

    private func people(_ n: Int) -> String {
        "\(n.compactCount) \(n == 1 ? "person" : "people")"
    }

    private static let placeholder = ApiListingStats(
        viewsTotal: 0, viewersTotal: 0, viewsLast30Days: 0, viewersLast30Days: 0,
        responsesTotal: 0, responsesLast30Days: 0, savesTotal: 0, savesLast30Days: 0,
        commentsTotal: 0, commentsLast30Days: 0,
        daily: (0 ..< 30).map { _ in .init(date: "", views: 0, responses: 0, saves: 0) }
    )
}
