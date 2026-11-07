//
//  EqualizerPanel.swift
//  Volspire
//
//  The EQ tab of the Audio effects sheet: preset chips, a live response curve
//  with one draggable point per band (up/down = gain, sideways = frequency),
//  and a read-out of the selected band. The curve comes from
//  `AudioEqualizer.response`, which matches the audio unit to within ~0.2 dB.
//

import DesignSystem
import Player
import SwiftUI

struct EqualizerPanel: View {
    let equalizer: AudioEqualizer
    /// Every change while dragging (applied live).
    let onChange: (AudioEqualizer) -> Void
    /// A finished edit: drag released or preset picked (analytics).
    let onCommit: () -> Void
    /// True while a finger is on the curve — the sheet turns off swipe-down
    /// only for that long.
    var onDraggingChanged: (Bool) -> Void = { _ in }

    @State private var selected = 0

    private var preset: EqualizerPreset? { EqualizerPreset(matching: equalizer) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            presets
            EqualizerGraph(equalizer: equalizer, selected: $selected, onChange: onChange, onCommit: onCommit,
                           onDraggingChanged: onDraggingChanged)
                .frame(height: 200)
            readout
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EqualizerPreset.allCases) { option in
                    FilterChip(option.title, isOn: option == preset) {
                        onChange(option.equalizer)
                        onCommit()
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.horizontal, -24)
    }

    /// The selected band, then a one-line how-to.
    private var readout: some View {
        let band = AudioEqualizer.bands[selected]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(band.label).foregroundStyle(Color.vText)
                Spacer(minLength: 0)
                Text(EqualizerFormat.frequency(equalizer.frequencies[selected]))
                    .foregroundStyle(Color.vText2)
                Text(EqualizerFormat.gain(equalizer.gains[selected]))
                    .foregroundStyle(Color.vText)
                    .frame(minWidth: 64, alignment: .trailing)
            }
            .font(.appBody)
            .monospacedDigit()

            Text("Drag a point up or down to boost or cut, sideways to change its frequency.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Graph

private struct EqualizerGraph: View {
    let equalizer: AudioEqualizer
    @Binding var selected: Int
    let onChange: (AudioEqualizer) -> Void
    let onCommit: () -> Void
    let onDraggingChanged: (Bool) -> Void

    /// The band under the finger, and where the finger sits relative to its
    /// point, so grabbing a point never makes it jump.
    @State private var drag: (band: Int, offset: CGSize)?

    private static let minFrequency = 20.0
    private static let maxFrequency = 20000.0
    /// The plot shows ±15 dB so a stacked ±12 boost still fits.
    private static let displayRange = 15.0
    private static let gridFrequencies: [Double] = [50, 100, 200, 500, 1000, 2000, 5000, 10000]
    private static let labeledFrequencies: [(Double, String)] = [(100, "100"), (1000, "1k"), (10000, "10k")]
    private static let inset = EdgeInsets(top: 12, leading: 12, bottom: 24, trailing: 12)

    var body: some View {
        GeometryReader { geo in
            let plot = CGRect(
                x: Self.inset.leading,
                y: Self.inset.top,
                width: geo.size.width - Self.inset.leading - Self.inset.trailing,
                height: geo.size.height - Self.inset.top - Self.inset.bottom
            )
            ZStack(alignment: .topLeading) {
                grid(in: plot)
                curveFill(in: plot)
                    .fill(Color.vText.opacity(0.10))
                curve(in: plot)
                    .stroke(Color.vText, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                points(in: plot)
            }
            .contentShape(.rect)
            .highPriorityGesture(dragGesture(in: plot))
        }
        .background(Color.ink(0.05), in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .sensoryFeedback(.selection, trigger: Int(equalizer.gains[selected].rounded()))
        .accessibilityElement(children: .contain)
    }

    // MARK: Mapping

    private func x(_ frequency: Double, in plot: CGRect) -> CGFloat {
        let fraction = log(frequency / Self.minFrequency) / log(Self.maxFrequency / Self.minFrequency)
        return plot.minX + plot.width * CGFloat(fraction)
    }

    private func frequency(atX x: CGFloat, in plot: CGRect) -> Double {
        let fraction = Double((x - plot.minX) / plot.width)
        return Self.minFrequency * pow(Self.maxFrequency / Self.minFrequency, fraction)
    }

    private func y(_ db: Double, in plot: CGRect) -> CGFloat {
        let clamped = min(max(db, -Self.displayRange), Self.displayRange)
        return plot.midY - CGFloat(clamped / Self.displayRange) * plot.height / 2
    }

    private func db(atY y: CGFloat, in plot: CGRect) -> Double {
        Double((plot.midY - y) / (plot.height / 2)) * Self.displayRange
    }

    private func pointCenter(_ band: Int, in plot: CGRect) -> CGPoint {
        CGPoint(
            x: x(Double(equalizer.frequencies[band]), in: plot),
            y: y(Double(equalizer.gains[band]), in: plot)
        )
    }

    // MARK: Layers

    private func grid(in plot: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                for f in Self.gridFrequencies {
                    let px = x(f, in: plot)
                    path.move(to: CGPoint(x: px, y: plot.minY))
                    path.addLine(to: CGPoint(x: px, y: plot.maxY))
                }
                for level in [-12.0, -6, 6, 12] {
                    let py = y(level, in: plot)
                    path.move(to: CGPoint(x: plot.minX, y: py))
                    path.addLine(to: CGPoint(x: plot.maxX, y: py))
                }
            }
            .stroke(Color.ink(0.06), lineWidth: 1)

            // 0 dB, a little stronger.
            Path { path in
                path.move(to: CGPoint(x: plot.minX, y: plot.midY))
                path.addLine(to: CGPoint(x: plot.maxX, y: plot.midY))
            }
            .stroke(Color.ink(0.16), lineWidth: 1)

            ForEach(Self.labeledFrequencies, id: \.0) { f, label in
                Text(label)
                    .position(x: x(f, in: plot), y: plot.maxY + 12)
            }
            ForEach([12.0, 0, -12], id: \.self) { level in
                Text(level > 0 ? "+12" : level < 0 ? "-12" : "0")
                    .position(x: plot.minX + 14, y: y(level, in: plot) - 8)
            }
        }
        .font(.appCaption)
        .foregroundStyle(Color.vText4)
        .accessibilityHidden(true)
    }

    private func curvePoints(in plot: CGRect) -> [CGPoint] {
        let steps = 120
        return (0 ... steps).map { step in
            let px = plot.minX + plot.width * CGFloat(step) / CGFloat(steps)
            let f = frequency(atX: px, in: plot)
            return CGPoint(x: px, y: y(equalizer.response(atFrequency: f), in: plot))
        }
    }

    private func curve(in plot: CGRect) -> Path {
        Path { path in path.addLines(curvePoints(in: plot)) }
    }

    /// The area between the curve and 0 dB.
    private func curveFill(in plot: CGRect) -> Path {
        Path { path in
            let points = curvePoints(in: plot)
            path.move(to: CGPoint(x: plot.minX, y: plot.midY))
            path.addLines(points)
            path.addLine(to: CGPoint(x: plot.maxX, y: plot.midY))
            path.closeSubpath()
        }
    }

    private func points(in plot: CGRect) -> some View {
        ForEach(AudioEqualizer.bands.indices, id: \.self) { band in
            let isSelected = band == selected
            let isDragging = drag?.band == band
            // Solid points in full ink, no outline. Selected is bigger, and
            // bigger again while being dragged.
            let side: CGFloat = isDragging ? 22 : isSelected ? 18 : 12
            Circle()
                .fill(Color.vText)
                .frame(width: side, height: side)
            .position(pointCenter(band, in: plot))
            .animation(.snappy(duration: 0.18), value: isSelected)
            .animation(.snappy(duration: 0.18), value: isDragging)
            .accessibilityElement()
            .accessibilityLabel("\(AudioEqualizer.bands[band].label), \(EqualizerFormat.frequency(equalizer.frequencies[band]))")
            .accessibilityValue(EqualizerFormat.gain(equalizer.gains[band]))
            .accessibilityAdjustableAction { direction in
                let step: Float = direction == .increment ? 1 : -1
                selected = band
                onChange(equalizer.settingGain(equalizer.gains[band] + step, forBand: band))
                onCommit()
            }
        }
    }

    // MARK: Dragging

    private func dragGesture(in plot: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if drag == nil {
                    // Grab the point nearest the touch, wherever it lands.
                    let band = AudioEqualizer.bands.indices.min { a, b in
                        distance(pointCenter(a, in: plot), value.startLocation)
                            < distance(pointCenter(b, in: plot), value.startLocation)
                    } ?? 0
                    let center = pointCenter(band, in: plot)
                    drag = (band, CGSize(width: center.x - value.startLocation.x, height: center.y - value.startLocation.y))
                    selected = band
                    onDraggingChanged(true)
                }
                guard let drag else { return }
                let target = CGPoint(x: value.location.x + drag.offset.width, y: value.location.y + drag.offset.height)
                let gain = Float((db(atY: target.y, in: plot) * 2).rounded() / 2)
                let freq = EqualizerFormat.roundedFrequency(Float(frequency(atX: target.x, in: plot)))
                let next = equalizer
                    .settingGain(gain, forBand: drag.band)
                    .settingFrequency(freq, forBand: drag.band)
                if next != equalizer { onChange(next) }
            }
            .onEnded { _ in
                drag = nil
                onDraggingChanged(false)
                onCommit()
            }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

// MARK: - Formatting

enum EqualizerFormat {
    /// "250 Hz", "1 kHz", "2.5 kHz".
    static func frequency(_ hz: Float) -> String {
        guard hz >= 1000 else { return "\(Int(hz.rounded())) Hz" }
        let khz = hz / 1000
        return khz.rounded() == khz || khz >= 10
            ? "\(Int(khz.rounded())) kHz"
            : String(format: "%.1f kHz", khz)
    }

    /// "+6 dB", "-2.5 dB", "0 dB".
    static func gain(_ db: Float) -> String {
        let sign = db > 0 ? "+" : ""
        let number = db.rounded() == db ? String(format: "%.0f", db) : String(format: "%.1f", db)
        return "\(sign)\(number) dB"
    }

    /// Steps that read cleanly while dragging: 1 Hz under 100, 5 Hz under
    /// 1 kHz, 50 Hz under 10 kHz, then 100 Hz.
    static func roundedFrequency(_ hz: Float) -> Float {
        let step: Float = hz < 100 ? 1 : hz < 1000 ? 5 : hz < 10000 ? 50 : 100
        return (hz / step).rounded() * step
    }
}
