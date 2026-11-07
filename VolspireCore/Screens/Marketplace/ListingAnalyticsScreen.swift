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
        .appNavBar(title: "Listing Analytics", subtitle: listingTitle) { dismiss() }
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
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
                AnalyticsStatTile(icon: .eye, label: "Views",
                                  value: s.viewsLast30Days.compactCount,
                                  sub: "Last 30 days · \(people(s.viewersLast30Days))")
                AnalyticsStatTile(icon: .send, label: "Responses",
                                  value: s.responsesTotal.compactCount,
                                  sub: "+\(s.responsesLast30Days.compactCount) in the last 30 days")
            }
            GridRow {
                AnalyticsStatTile(icon: .bookmark, label: "Saves",
                                  value: s.savesTotal.compactCount,
                                  sub: "+\(s.savesLast30Days.compactCount) in the last 30 days")
                AnalyticsStatTile(icon: .messageCircle, label: "Comments",
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
            VStack(spacing: 0) {
                row(.eye, "Views", s.viewsTotal.compactCount)
                SettingsDivider()
                row(.users, "People who viewed", s.viewersTotal.compactCount)
                SettingsDivider()
                row(.send, "Response rate", responseRate(s))
            }
            .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }

    private func row(_ icon: LucideIcon.Name, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            LucideIcon(icon, .md).foregroundStyle(Color.vText3)
            Text(label).font(.appSubheadline).foregroundStyle(Color.vText)
            Spacer(minLength: 0)
            Text(value).font(.appSubheadlineSemibold).foregroundStyle(Color.vText).monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
