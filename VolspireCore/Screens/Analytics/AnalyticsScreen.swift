//
//  AnalyticsScreen.swift
//  Volspire
//
//  Creator dashboard: a headline streams number + a labelled 30-day trend,
//  supporting stats, where plays come from, and a ranked track list.
//

import DesignSystem
import SwiftUI

struct AnalyticsScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @State private var viewModel = AnalyticsViewModel()
    /// Chart window in days (7 or 30) — the range picker in the overview card.
    @State private var chartDays = 30
    /// Index of the day pinned by dragging across the chart (nil when idle).
    @State private var scrubIndex: Int?

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            content
                .padding(.top, 4)
                .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: "Analytics") { dismiss() }
        .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.loaded {
            analyticsSkeleton
        } else if viewModel.loadFailed && viewModel.tracks.isEmpty {
            LoadErrorView { Task { await viewModel.load() } }
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.5)
        } else if viewModel.tracks.isEmpty {
            emptyState
        } else {
            VStack(spacing: 14) {
                overviewCard
                statsRow
                audienceCard
                if !viewModel.topSources.isEmpty {
                    AnalyticsSourcesCard(
                        subtitle: "How listeners reached your tracks",
                        sources: viewModel.topSources,
                        totalPlays: viewModel.totalSourcePlays
                    )
                }
                tracksCard
            }
            .padding(.horizontal, ViewConst.screenPaddings)
        }
    }
}

// MARK: - Overview (headline streams + trend chart)

private extension AnalyticsScreen {
    var overviewCard: some View {
        let series = viewModel.plays(last: chartDays)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    AnalyticsSectionLabel("Total streams")
                    Text(viewModel.totalStreams.formatted())
                        .font(.appDisplay)
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
                Spacer()
                rangePicker
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    // While scrubbing, the label becomes the pinned day's readout.
                    if let index = scrubIndex, series.indices.contains(index) {
                        Text("\(scrubDate(index: index, count: series.count)) · \(series[index]) plays")
                            .font(.appFootnoteSemibold).foregroundStyle(.white)
                            .monospacedDigit()
                    } else {
                        Text("Plays · last \(chartDays) days")
                            .font(.appFootnote).foregroundStyle(Color.vText2)
                    }
                    Spacer()
                    AnalyticsTrendPill(trend: viewModel.trend(days: chartDays))
                        .opacity(scrubIndex == nil ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.15), value: scrubIndex == nil)

                ScrubbableTrendChart(values: series, scrubIndex: $scrubIndex)
                    .frame(height: 90)
                    .id(chartDays) // fresh chart (and geometry) when the window changes

                AnalyticsChartFooter(days: chartDays)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
        .onChange(of: chartDays) { _, _ in scrubIndex = nil }
    }

    /// 7D / 30D window toggle — selected chip is white like the roles chips.
    var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach([7, 30], id: \.self) { days in
                let selected = chartDays == days
                Button {
                    withAnimation(.smooth(duration: 0.25)) { chartDays = days }
                } label: {
                    Text("\(days)D")
                        .font(.appCaptionMedium)
                        .foregroundStyle(selected ? .black : Color.vText2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.06)), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Jul 3"-style label for a scrubbed chart index (oldest → today series).
    func scrubDate(index: Int, count: Int) -> String {
        let daysAgo = count - 1 - index
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Supporting stats

private extension AnalyticsScreen {
    var statsRow: some View {
        HStack(spacing: 12) {
            AnalyticsStatTile(value: viewModel.totalListeners.compactCount, label: "Unique listeners", icon: .users)
            AnalyticsStatTile(value: formatTime(viewModel.avgListenSeconds), label: "Avg. listen time", icon: .clock)
        }
    }
}

// MARK: - Audience (engagement)

private extension AnalyticsScreen {
    /// Active-like pink — same tint as the player's like button.
    static let likedPink = Color(red: 0.957, green: 0.447, blue: 0.714)

    /// Followers / likes / saves / comments with 30-day deltas, each in its
    /// accent (followers use the app's send-accent gradient, likes the like
    /// pink, the rest the brand accent). Hidden if the engagement RPC failed.
    @ViewBuilder
    var audienceCard: some View {
        if let engagement = viewModel.engagement {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    AnalyticsSectionLabel("Audience")
                    Text("Engagement across your profile and tracks · +N is the last 30 days")
                        .font(.appCaption).foregroundStyle(Color.vText3)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    engagementTile(icon: .userCheck, tint: AnyShapeStyle(LinearGradient.sendAccent),
                                   value: engagement.followersTotal, delta: engagement.followers30d, label: "Followers")
                    engagementTile(icon: .heart, tint: AnyShapeStyle(Self.likedPink),
                                   value: engagement.likesTotal, delta: engagement.likes30d, label: "Likes")
                    engagementTile(icon: .bookmark, tint: AnyShapeStyle(Color.brand),
                                   value: engagement.savesTotal, delta: engagement.saves30d, label: "Saves")
                    engagementTile(icon: .messageCircle, tint: AnyShapeStyle(Color.brand),
                                   value: engagement.commentsTotal, delta: engagement.comments30d, label: "Comments")
                }
                if engagement.shares30d > 0 {
                    HStack(spacing: 8) {
                        LucideIcon(.share2, .sm).foregroundStyle(Color.brand)
                        Text("\(engagement.shares30d) shares in the last 30 days")
                            .font(.appFootnote).foregroundStyle(Color.vText2)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    func engagementTile(icon: LucideIcon.Name, tint: AnyShapeStyle, value: Int, delta: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LucideIcon(icon, .md).foregroundStyle(tint)
                Spacer()
                if delta > 0 {
                    Text("+\(delta)")
                        .font(.appCaptionMedium)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
            }
            Text(value.compactCount)
                .font(.appTitle).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label).font(.appCaption).foregroundStyle(Color.vText3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Top tracks (ranked)

private extension AnalyticsScreen {
    var tracksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AnalyticsSectionLabel("Top tracks")
            VStack(spacing: 14) {
                ForEach(Array(viewModel.tracks.enumerated()), id: \.element.id) { index, track in
                    NavigationLink {
                        TrackAnalyticsDetailScreen(track: track)
                    } label: {
                        trackRow(rank: index + 1, track: track)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
    }

    func trackRow(rank: Int, track: TrackAnalyticsItem) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.appFootnote).foregroundStyle(Color.vText3)
                .frame(width: 16)
            ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: 8)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
                Text("\(track.uniqueListeners.compactCount) listeners · \(formatTime(Int(track.avgListenTime))) avg")
                    .font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(track.streams.compactCount).font(.appBodyMedium).foregroundStyle(.white).monospacedDigit()
                Text("streams").font(.appCaption).foregroundStyle(Color.vText3)
            }
            LucideIcon(.chevronRight, .xs)
                .foregroundStyle(Color.vText3)
        }
        .contentShape(.rect)
    }
}

// MARK: - Helpers

private extension AnalyticsScreen {
    func formatTime(_ seconds: Int) -> String { seconds.durationLabel }

    var emptyState: some View {
        EmptyStateView(
            icon: .chartLine,
            title: "No analytics yet",
            message: "Upload a track and your streams, listeners and plays will show up here."
        )
        .padding(.vertical, 80)
    }
}

// MARK: - Loading skeleton

private extension AnalyticsScreen {
    /// Mirrors the loaded dashboard (overview card, two stat tiles, top-tracks
    /// card) as shimmering bones so the layout doesn't pop in.
    var analyticsSkeleton: some View {
        let bone = Color.white.opacity(0.06)
        return VStack(spacing: 14) {
            // Overview card: headline number + trend chart area.
            VStack(alignment: .leading, spacing: 18) {
                Capsule().fill(bone).frame(width: 90, height: 11)
                Capsule().fill(bone).frame(width: 140, height: 30)
                RoundedRectangle(cornerRadius: 10).fill(bone).frame(height: 90)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))

            // Two stat tiles.
            HStack(spacing: 12) {
                ForEach(0 ..< 2, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Circle().fill(bone).frame(width: 18, height: 18)
                        Capsule().fill(bone).frame(width: 70, height: 22)
                        Capsule().fill(bone).frame(width: 100, height: 10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.vCard, in: RoundedRectangle(cornerRadius: 16))
                }
            }

            // Top-tracks card.
            VStack(alignment: .leading, spacing: 14) {
                Capsule().fill(bone).frame(width: 90, height: 11)
                ForEach(0 ..< 4, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bone).frame(width: 46, height: 46)
                        VStack(alignment: .leading, spacing: 6) {
                            Capsule().fill(bone).frame(width: 130, height: 12)
                            Capsule().fill(bone).frame(width: 90, height: 10)
                        }
                        Spacer(minLength: 8)
                        Capsule().fill(bone).frame(width: 36, height: 12)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .shimmering()
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    AnalyticsScreen()
        .environment(playerController)
}
