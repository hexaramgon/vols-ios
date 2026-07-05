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

    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    private var series: [Int] { track.dailyPlaysSeries }
    private var trend: Int { AnalyticsViewModel.weekTrend(from: series) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 14) {
                    statsGrid
                    chartCard
                    if !track.sortedSources.isEmpty { sourcesCard }
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
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            ArtworkView(track.coverURL.map { .webImage($0) } ?? .placeholder(name: track.title), cornerRadius: 8)
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
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile("Streams", track.streams.profileCompact, "play.fill")
            tile("Unique listeners", track.uniqueListeners.profileCompact, "person.2.fill")
            tile("Avg. listen", time(Int(track.avgListenTime)), "clock.fill")
            tile("Avg. seeks", String(format: "%.1f", track.avgSeekCount), "arrow.left.arrow.right")
        }
    }

    func tile(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Color.brand)
            Text(value).font(.appTitle).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.appCaption).foregroundStyle(Color.vText3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Chart

private extension TrackAnalyticsDetailScreen {
    var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Plays · last 30 days")
                Spacer()
                trendPill
            }
            AnalyticsTrendChart(values: series).frame(height: 90)
            HStack {
                Text("30 days ago").font(.appCaption).foregroundStyle(Color.vText3)
                Spacer()
                Text("Today").font(.appCaption).foregroundStyle(Color.vText3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    var trendPill: some View {
        let up = trend >= 0
        let tint = up ? Color.green : Color.red
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text("\(abs(trend))%").font(.appCaption).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
    }
}

// MARK: - Sources

private extension TrackAnalyticsDetailScreen {
    var sourcesCard: some View {
        let total = max(track.sources.values.reduce(0, +), 1)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Where plays come from")
                Text("How listeners reached this track")
                    .font(.appCaption).foregroundStyle(Color.vText3)
            }
            ForEach(track.sortedSources.prefix(6), id: \.label) { source in
                let pct = Int((Double(source.count) / Double(total) * 100).rounded())
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(source.label).font(.appFootnote).foregroundStyle(.white)
                        Spacer()
                        Text("\(pct)%").font(.appCaption).foregroundStyle(Color.vText2).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.06))
                            Capsule().fill(Color.brand.opacity(0.85))
                                .frame(width: max(6, geo.size.width * CGFloat(source.count) / CGFloat(total)))
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 18))
    }
}

// MARK: - Helpers

private extension TrackAnalyticsDetailScreen {
    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.appLabel)
            .tracking(0.8)
            .foregroundStyle(Color.vText3)
    }

    func time(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
