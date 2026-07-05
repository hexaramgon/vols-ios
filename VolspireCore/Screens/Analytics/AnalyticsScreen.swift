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

    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

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
                if !viewModel.topSources.isEmpty { sourcesCard }
                tracksCard
            }
            .padding(.horizontal, ViewConst.screenPaddings)
        }
    }
}

// MARK: - Overview (headline streams + trend chart)

private extension AnalyticsScreen {
    var overviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Total streams")
                Text(viewModel.totalStreams.formatted())
                    .font(.appDisplay)
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Plays · last 30 days")
                        .font(.appFootnote).foregroundStyle(Color.vText2)
                    Spacer()
                    trendPill
                }
                AnalyticsTrendChart(values: viewModel.dailyPlays)
                    .frame(height: 90)
                HStack {
                    Text("30 days ago").font(.appCaption).foregroundStyle(Color.vText3)
                    Spacer()
                    Text("Today").font(.appCaption).foregroundStyle(Color.vText3)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    var trendPill: some View {
        let up = viewModel.weekTrend >= 0
        let tint = up ? Color.green : Color.red
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 10, weight: .bold))
            Text("\(abs(viewModel.weekTrend))%").font(.appCaption).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
    }
}

// MARK: - Supporting stats

private extension AnalyticsScreen {
    var statsRow: some View {
        HStack(spacing: 12) {
            statTile(value: viewModel.totalListeners.profileCompact, label: "Unique listeners", icon: "person.2.fill")
            statTile(value: formatTime(viewModel.avgListenSeconds), label: "Avg. listen time", icon: "clock.fill")
        }
    }

    func statTile(value: String, label: String, icon: String) -> some View {
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

// MARK: - Where plays come from

private extension AnalyticsScreen {
    var sourcesCard: some View {
        let total = max(viewModel.totalSourcePlays, 1)
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                sectionLabel("Where plays come from")
                Text("How listeners reached your tracks")
                    .font(.appCaption).foregroundStyle(Color.vText3)
            }
            ForEach(viewModel.topSources, id: \.label) { source in
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

// MARK: - Top tracks (ranked)

private extension AnalyticsScreen {
    var tracksCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Top tracks")
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
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 18))
    }

    func trackRow(rank: Int, track: TrackAnalyticsItem) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.appFootnote).foregroundStyle(Color.vText3)
                .frame(width: 16)
            ArtworkView(track.coverURL.map { .webImage($0) } ?? .placeholder(name: track.title), cornerRadius: 8)
                .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.appBodyMedium).foregroundStyle(.white).lineLimit(1)
                Text("\(track.uniqueListeners.profileCompact) listeners · \(formatTime(Int(track.avgListenTime))) avg")
                    .font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(track.streams.profileCompact).font(.appBodyMedium).foregroundStyle(.white).monospacedDigit()
                Text("streams").font(.appCaption).foregroundStyle(Color.vText3)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.vText3)
        }
        .contentShape(.rect)
    }
}

// MARK: - Helpers

private extension AnalyticsScreen {
    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.appLabel)
            .tracking(0.8)
            .foregroundStyle(Color.vText3)
    }

    func formatTime(_ seconds: Int) -> String {
        "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 34))
                .foregroundStyle(Color.vText3.opacity(0.7))
            Text("No analytics yet").font(.appHeadline).foregroundStyle(.white)
            Text("Upload a track and your streams, listeners and plays will show up here.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
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
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 18))

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
                    .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16))
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
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 18))
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .shimmering()
    }
}

// MARK: - Trend chart (filled area + line)

struct AnalyticsTrendChart: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 0, 1)
            let w = geo.size.width
            let h = geo.size.height
            let points = points(in: CGSize(width: w, height: h), maxValue: maxValue)

            ZStack {
                if let first = points.first, let last = points.last {
                    // Filled area under the line.
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: h))
                        path.addLine(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: last.x, y: h))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [Color.brand.opacity(0.35), Color.brand.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    ))

                    // The line itself.
                    Path { path in
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func points(in size: CGSize, maxValue: Int) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        return values.enumerated().map { index, value in
            CGPoint(
                x: size.width * CGFloat(index) / CGFloat(values.count - 1),
                y: size.height - (CGFloat(value) / CGFloat(maxValue)) * size.height
            )
        }
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    AnalyticsScreen()
        .environment(playerController)
}
