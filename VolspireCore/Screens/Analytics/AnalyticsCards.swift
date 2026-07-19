//
//  AnalyticsCards.swift
//  Volspire
//
//  Shared pieces of the analytics dashboard and the per-track detail screen:
//  section label, trend pill, stat tile, chart footer, the sources card, and
//  the trend chart (scrubbable on the dashboard, static on the detail page).
//

import DesignSystem
import SwiftUI

// MARK: - Section label

/// Uppercase tracked micro-label above analytics cards ("TOP TRACKS").
struct AnalyticsSectionLabel: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.appLabel)
            .tracking(0.8)
            .foregroundStyle(Color.vText3)
    }
}

// MARK: - Trend pill

/// Green/red percentage capsule with an up/down arrow (the Lucide up-right
/// glyph, rotated for down).
struct AnalyticsTrendPill: View {
    let trend: Int

    var body: some View {
        let up = trend >= 0
        let tint = up ? Color.green : Color.red
        HStack(spacing: 3) {
            LucideIcon(.arrowUpRight, .xs)
                .rotationEffect(.degrees(up ? 0 : 90))
            Text("\(abs(trend))%").font(.appCaption).fontWeight(.semibold)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
    }
}

// MARK: - Stat tile

/// Brand-tinted icon + big value + caption, on the card fill (streams,
/// unique listeners, avg listen time, …).
struct AnalyticsStatTile: View {
    let value: String
    let label: String
    let icon: LucideIcon.Name

    var body: some View {
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

// MARK: - Chart footer

/// The "N days ago … Today" axis row under a trend chart.
struct AnalyticsChartFooter: View {
    let days: Int

    var body: some View {
        HStack {
            Text("\(days) days ago").font(.appCaption).foregroundStyle(Color.vText3)
            Spacer()
            Text("Today").font(.appCaption).foregroundStyle(Color.vText3)
        }
    }
}

// MARK: - Sources card

/// "Where plays come from" — labelled percentage bars for the play-source
/// breakdown (dashboard: all tracks; detail: a single track).
struct AnalyticsSourcesCard: View {
    let subtitle: String
    let sources: [(label: String, count: Int)]
    /// Denominator for the percentages (clamped to ≥ 1).
    let totalPlays: Int

    var body: some View {
        let total = max(totalPlays, 1)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                AnalyticsSectionLabel("Where plays come from")
                Text(subtitle)
                    .font(.appCaption).foregroundStyle(Color.vText3)
            }
            ForEach(sources, id: \.label) { source in
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

// MARK: - Trend chart (filled area + line, optional scrubbing)

/// The analytics trend chart. Pass a `scrubIndex` binding to enable touch
/// scrubbing — dragging pins a day (dashed rule + dot) and reports its index
/// up; release clears it. Without a binding the chart is static: no gesture
/// is installed, so it never eats scrolls or fires haptics.
struct ScrubbableTrendChart: View {
    let values: [Int]
    @Binding var scrubIndex: Int?
    private let scrubEnabled: Bool

    init(values: [Int], scrubIndex: Binding<Int?>? = nil) {
        self.values = values
        self._scrubIndex = scrubIndex ?? .constant(nil)
        self.scrubEnabled = scrubIndex != nil
    }

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
            .gesture(scrubEnabled ? scrubGesture(in: size) : nil)
        }
    }

    private func scrubGesture(in size: CGSize) -> some Gesture {
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
