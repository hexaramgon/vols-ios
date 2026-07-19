//
//  TrackAnalyticsDetailScreen.swift
//  Volspire
//
//  A single track's performance — opened from the analytics "Top tracks" list.
//  Renders the already-loaded analytics item, so no extra fetch is needed.
//

import DesignSystem
import SwiftUI

struct TrackAnalyticsDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    let track: TrackAnalyticsItem

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    private var series: [Int] { track.dailyPlaysSeries }
    private var trend: Int { AnalyticsViewModel.weekTrend(from: series) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    statsGrid
                    chartCard
                    if !track.sortedSources.isEmpty {
                        AnalyticsSourcesCard(
                            subtitle: "How listeners reached this track",
                            sources: Array(track.sortedSources.prefix(6)),
                            totalPlays: track.sources.values.reduce(0, +)
                        )
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 4)
                .padding(.bottom, bottomInset)
            }
            .scrollIndicators(.hidden)
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.vBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
    }
}

// MARK: - Header

private extension TrackAnalyticsDetailScreen {
    var header: some View {
        HStack(spacing: 12) {
            BackButton(shadow: false)

            ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: 8)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).font(.appHeadline).foregroundStyle(.white).lineLimit(1)
                if let genre = track.genre, !genre.isEmpty {
                    Text(genre).font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, ViewConst.safeAreaInsets.top + 8)
        .padding(.bottom, 16)
    }
}

// MARK: - Stats

private extension TrackAnalyticsDetailScreen {
    var statsGrid: some View {
        // Lucide icons matching the dashboard's tiles (.repeat is the closest
        // bundled glyph to the old bidirectional-arrows SF symbol for seeks).
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            AnalyticsStatTile(value: track.streams.compactCount, label: "Streams", icon: .playFill)
            AnalyticsStatTile(value: track.uniqueListeners.compactCount, label: "Unique listeners", icon: .users)
            AnalyticsStatTile(value: time(Int(track.avgListenTime)), label: "Avg. listen", icon: .clock)
            AnalyticsStatTile(value: String(format: "%.1f", track.avgSeekCount), label: "Avg. seeks", icon: .repeat)
        }
    }
}

// MARK: - Chart

private extension TrackAnalyticsDetailScreen {
    var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AnalyticsSectionLabel("Plays · last 30 days")
                Spacer()
                AnalyticsTrendPill(trend: trend)
            }
            // No scrub binding → static chart (no drag gesture).
            ScrubbableTrendChart(values: series).frame(height: 90)
            AnalyticsChartFooter(days: 30)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Helpers

private extension TrackAnalyticsDetailScreen {
    func time(_ seconds: Int) -> String { seconds.durationLabel }
}
