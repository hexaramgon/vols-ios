//
//  AnalyticsCards.swift
//  Volspire
//
//  Building blocks of the track analytics page, matching the web's
//  `track-analytics-view.tsx`: titled blocks, stat tiles, the labelled source
//  bars, and the single-series line chart. The data (line, area, dots, bars)
//  is drawn in the app's primary blue (`vAccent`); grid and guides stay
//  neutral ink. No border rings — surfaces separate by fill.
//

import DesignSystem
import SwiftUI

// MARK: - Dates

enum AnalyticsDates {
    /// "Oct 3" from an RPC day string ("2026-10-03").
    static func label(_ iso: String?) -> String {
        guard let iso, let date = formatter.date(from: iso) else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - Subject header

/// What the analytics page is about, as the first thing in its content (the
/// nav bar just says "… Analytics"): 64pt art, the name, a caption line.
/// Track, Pack and Listing Analytics all open with it.
struct AnalyticsSubjectHeader<Art: View>: View {
    let title: String
    let caption: String
    @ViewBuilder var art: Art

    var body: some View {
        HStack(spacing: 16) {
            art.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.appTitle3).foregroundStyle(Color.vText).lineLimit(1)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Block

/// A titled block of the detail pane (14 semibold heading, not a section
/// title) with an optional caption on the right.
struct AnalyticsBlock<Content: View>: View {
    let title: String
    var aside: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                Spacer(minLength: 0)
                if let aside {
                    Text(aside).font(.appCaption).foregroundStyle(Color.vText3).monospacedDigit()
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The "No … data yet." placeholder card inside a block.
struct AnalyticsEmptyNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.appSubheadline)
            .foregroundStyle(Color.vText3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 32)
            .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - Stat tile

/// Icon + label, a big tabular value, and a caption — the web's neutral
/// `StatTile`.
struct AnalyticsStatTile: View {
    let label: String
    let value: String
    let sub: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Label only — no icon (the number carries the tile).
            Text(label).font(.appLabel).foregroundStyle(Color.vText3).lineLimit(1)
                .padding(.bottom, 10)
            Text(value)
                .font(.appLargeTitle)
                .foregroundStyle(Color.vText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(sub)
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

// MARK: - All-time totals

/// The "All time" numbers as one scoreboard card: equal columns split by
/// hairlines, each a grey label over a big bold number — the
/// stat tiles' anatomy in a strip, so the totals read as numbers, not as
/// settings rows. (Pack and Listing analytics.)
struct AnalyticsTotals: View {
    struct Item: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let items: [Item]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle().fill(Color.vDivider).frame(width: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.label)
                        .font(.appLabel)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.value)
                        .font(.appTitle)
                        .foregroundStyle(Color.vText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 16)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(items.map { "\($0.label) \($0.value)" }.joined(separator: ", "))
    }
}

// MARK: - Sources

/// "How people found it": one labelled bar per source, longest first. A
/// single ink — the label carries identity, the length carries share.
struct AnalyticsSourceBars: View {
    let sources: [(key: String, count: Int)]

    var body: some View {
        let total = max(sources.reduce(0) { $0 + $1.count }, 1)
        VStack(spacing: 12) {
            ForEach(Array(sources.enumerated()), id: \.element.key) { index, source in
                let pct = Double(source.count) / Double(total) * 100
                VStack(spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(source.key)
                            .font(.appSubheadline).foregroundStyle(Color.vText)
                        Spacer(minLength: 0)
                        Text("\(Int(pct.rounded()))%")
                            .font(.appSubheadline).foregroundStyle(Color.vText2).monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.ink(0.06))
                            Capsule()
                                .fill(index == 0 ? Color.vAccent : Color.vAccent.opacity(0.45))
                                .frame(width: geo.size.width * max(pct, 2) / 100)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }
}

// MARK: - Line chart

/// One series as a smooth line over a soft fill, three recessive guide lines,
/// the peak marked with a dot, and a scrub crosshair with a readout. The max
/// value sits top-left, three x labels underneath.
struct AnalyticsLineChart: View {
    let values: [Double]
    var height: CGFloat = 140
    /// Labels under the x axis: start, middle, end.
    let xLabels: (String, String, String)
    /// Readout for the scrubbed point: a heading and a value line.
    let readout: (Int) -> (label: String, value: String)

    @State private var scrubIndex: Int?

    var body: some View {
        VStack(spacing: 8) {
            Text(maxValue.compactCountLabel)
                .font(.appCaption).foregroundStyle(Color.vText3).monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, -4)
            GeometryReader { geo in
                plot(in: geo.size)
            }
            .frame(height: height)
            HStack {
                Text(xLabels.0)
                Spacer()
                Text(xLabels.1)
                Spacer()
                Text(xLabels.2)
            }
            .font(.appCaption)
            .foregroundStyle(Color.vText3)
            .monospacedDigit()
        }
    }

    private var maxValue: Double { max(values.max() ?? 0, 1) }

    private func xAt(_ i: Int) -> CGFloat {
        values.count <= 1 ? 0.5 : CGFloat(i) / CGFloat(values.count - 1)
    }

    private func point(_ i: Int, in size: CGSize) -> CGPoint {
        CGPoint(x: xAt(i) * size.width, y: (1 - CGFloat(values[i] / maxValue)) * size.height)
    }

    /// Smooth path through every point (cubic segments with mid-x control
    /// points — the web's curve).
    private func linePath(in size: CGSize) -> Path {
        Path { path in
            for i in values.indices {
                let p = point(i, in: size)
                if i == 0 {
                    path.move(to: p)
                } else {
                    let prev = point(i - 1, in: size)
                    let cx = (prev.x + p.x) / 2
                    path.addCurve(to: p, control1: CGPoint(x: cx, y: prev.y), control2: CGPoint(x: cx, y: p.y))
                }
            }
        }
    }

    @ViewBuilder
    private func plot(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            // Guide lines: top and middle dashed, a solid baseline.
            ForEach([0.0, 0.5, 1.0], id: \.self) { f in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: f * size.height))
                    p.addLine(to: CGPoint(x: size.width, y: f * size.height))
                }
                .stroke(
                    f == 1 ? Color.ink(0.12) : Color.ink(0.06),
                    style: StrokeStyle(lineWidth: 1, dash: f == 1 ? [] : [3, 3])
                )
            }

            if !values.isEmpty {
                let line = linePath(in: size)
                // Soft fill under the line.
                Path { p in
                    p.addPath(line)
                    p.addLine(to: CGPoint(x: point(values.count - 1, in: size).x, y: size.height))
                    p.addLine(to: CGPoint(x: point(0, in: size).x, y: size.height))
                    p.closeSubpath()
                }
                .fill(LinearGradient(colors: [Color.vAccent.opacity(0.22), Color.vAccent.opacity(0)],
                                     startPoint: .top, endPoint: .bottom))
                line.stroke(Color.vAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                // Peak: a 10pt blue dot with a 2pt canvas ring.
                if let peak = values.indices.max(by: { values[$0] < values[$1] }), values[peak] > 0 {
                    Circle()
                        .fill(Color.vAccent)
                        .frame(width: 10, height: 10)
                        .background(Circle().fill(Color.vBase).padding(-2))
                        .position(point(peak, in: size))
                }

                if let i = scrubIndex, values.indices.contains(i) {
                    scrubOverlay(index: i, in: size)
                }
            }
        }
        .contentShape(.rect)
        // A small minimum distance so a vertical page scroll that starts on
        // the chart still scrolls; a sideways drag scrubs.
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { g in
                    guard !values.isEmpty else { return }
                    let f = min(max(g.location.x / max(size.width, 1), 0), 1)
                    let i = Int((f * CGFloat(max(values.count - 1, 0))).rounded())
                    if i != scrubIndex {
                        scrubIndex = i
                        Haptics.impact(.soft)
                    }
                }
                .onEnded { _ in scrubIndex = nil }
        )
    }

    /// Crosshair, dot and readout for the scrubbed point.
    private func scrubOverlay(index i: Int, in size: CGSize) -> some View {
        let p = point(i, in: size)
        let info = readout(i)
        let flip = xAt(i) > 0.7
        return ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: p.x, y: 0))
                path.addLine(to: CGPoint(x: p.x, y: size.height))
            }
            .stroke(Color.ink(0.25), lineWidth: 1)
            Circle().fill(Color.vAccent).frame(width: 10, height: 10).position(p)
            VStack(alignment: .leading, spacing: 1) {
                Text(info.label).font(.appCaption).foregroundStyle(Color.vText3)
                Text(info.value).font(.appSubheadlineSemibold).foregroundStyle(Color.vText).monospacedDigit()
            }
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.vSurface, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .alignmentGuide(.leading) { d in flip ? d.width + 8 - p.x : -(p.x + 8) }
            .alignmentGuide(.top) { _ in -4 }
        }
        .allowsHitTesting(false)
    }
}

extension Double {
    /// Compact count for chart labels (heatmap buckets are averages).
    var compactCountLabel: String { Int(rounded()).compactCount }
}
