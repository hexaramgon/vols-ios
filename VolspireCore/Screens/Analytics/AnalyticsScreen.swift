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
                audienceCard
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
        let series = viewModel.plays(last: chartDays)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Total streams")
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
                    trendPill.opacity(scrubIndex == nil ? 1 : 0)
                }
                .animation(.easeInOut(duration: 0.15), value: scrubIndex == nil)

                ScrubbableTrendChart(values: series, scrubIndex: $scrubIndex)
                    .frame(height: 90)
                    .id(chartDays) // fresh chart (and geometry) when the window changes

                HStack {
                    Text("\(chartDays) days ago").font(.appCaption).foregroundStyle(Color.vText3)
                    Spacer()
                    Text("Today").font(.appCaption).foregroundStyle(Color.vText3)
                }
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

    var trendPill: some View {
        let trend = viewModel.trend(days: chartDays)
        let up = trend >= 0
        let tint = up ? Color.green : Color.red
        return HStack(spacing: 3) {
            LucideIcon(.arrowUpRight, .xs)
                .rotationEffect(.degrees(up ? 0 : 90))
            Text("\(abs(trend))%").font(.appCaption).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
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
            statTile(value: viewModel.totalListeners.compactCount, label: "Unique listeners", icon: .users)
            statTile(value: formatTime(viewModel.avgListenSeconds), label: "Avg. listen time", icon: .clock)
        }
    }

    func statTile(value: String, label: String, icon: LucideIcon.Name) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LucideIcon(icon, .sm).foregroundStyle(Color.brand)
            Text(value).font(.appTitle).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.appCaption).foregroundStyle(Color.vText3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 16))
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
                    sectionLabel("Audience")
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
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
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
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: 18))
    }

    func trackRow(rank: Int, track: TrackAnalyticsItem) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.appFootnote).foregroundStyle(Color.vText3)
                .frame(width: 16)
            ArtworkView(track.coverURL.map { .webImage($0) } ?? .placeholder(name: track.title), cornerRadius: 8)
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
    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.appLabel)
            .tracking(0.8)
            .foregroundStyle(Color.vText3)
    }

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

// MARK: - Scrubbable trend chart (drag to inspect a day)

/// The dashboard trend chart with touch scrubbing: drag across it to pin a day
/// (dashed rule + dot) and report its index up via `scrubIndex` — the overview
/// header swaps to that day's date + plays while held; release clears it.
struct ScrubbableTrendChart: View {
    let values: [Int]
    @Binding var scrubIndex: Int?

    var body: some View {
        GeometryReader { geo in
            let maxValue = max(values.max() ?? 0, 1)
            let size = geo.size
            let points = points(in: size, maxValue: maxValue)

            ZStack {
                if let first = points.first, let last = points.last {
                    // Filled area under the line.
                    Path { path in
                        path.move(to: CGPoint(x: first.x, y: size.height))
                        path.addLine(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: last.x, y: size.height))
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

                    // Scrub rule + pinned-day dot.
                    if let index = scrubIndex, points.indices.contains(index) {
                        let point = points[index]
                        Path { path in
                            path.move(to: CGPoint(x: point.x, y: 0))
                            path.addLine(to: CGPoint(x: point.x, y: size.height))
                        }
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        Circle()
                            .fill(Color.brand)
                            .frame(width: 9, height: 9)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .position(point)
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard values.count > 1 else { return }
                        let fraction = min(max(gesture.location.x / max(size.width, 1), 0), 1)
                        let index = Int((fraction * CGFloat(values.count - 1)).rounded())
                        if index != scrubIndex {
                            scrubIndex = index
                            Haptics.impact(.soft)
                        }
                    }
                    .onEnded { _ in scrubIndex = nil }
            )
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
