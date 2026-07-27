//
//  ElasticSlider.swift
//  Volspire
//
//

import SwiftUI

public struct ElasticSlider<LeadingContent: View, TrailingContent: View>: View {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let leadingLabel: LeadingContent?
    private let trailingLabel: TrailingContent?
    @Environment(\.elasticSliderConfig) var config
    @Environment(\.elasticSliderLoading) var isLoading
    @State private var lastStoredValue: CGFloat
    @State private var stretchingValue: CGFloat = 0
    @State private var viewSize: CGSize = .zero
    @GestureState private var isActive: Bool = false
    var onValueChanged: ((Double) -> Void)?
    var onActive: ((Bool) -> Void)?

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        leadingLabel: (() -> LeadingContent)? = nil,
        trailingLabel: (() -> TrailingContent)? = nil,
        onValueChanged: ((Double) -> Void)? = nil,
        onActive: ((Bool) -> Void)? = nil
    ) {
        _value = value
        self.range = range
        lastStoredValue = value.wrappedValue
        self.leadingLabel = leadingLabel?()
        self.trailingLabel = trailingLabel?()
        self.onValueChanged = onValueChanged
        self.onActive = onActive
    }

    public var body: some View {
        Group {
            if config.labelLocation == .bottom {
                bottomLabeledTrack
            } else {
                sideLabeledTrack
            }
        }
        .onChange(of: isActive) {
            onActive?(isActive)
        }
        .onChange(of: value) {
            if !isActive {
                lastStoredValue = value
            }
        }
        .animation(.smooth(duration: 0.3, extraBounce: 0.3), value: isActive)
        .sensoryFeedback(.increase, trigger: isValueExtreme) { config.defaultSensoryFeedback && $1 }
    }
}

// MARK: private

private struct SizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

private extension ElasticSlider {
    var isValueExtreme: Bool {
        value == range.lowerBound || value == range.upperBound
    }

    @ViewBuilder
    func styled(_ content: some View) -> some View {
        if config.syncLabelsStyle {
            ZStack {
                content
                    .foregroundStyle(config.maximumTrackColor)
                    .blendMode(config.blendMode)
                content
                    .foregroundStyle(isActive ? config.minimumTrackActiveColor : config.minimumTrackInactiveColor)
            }
            .animation(nil, value: isActive)
            .blendMode(isActive ? .normal : config.blendMode)
            .transformEffect(.identity)
        } else {
            content
        }
    }

    var bottomLabeledTrack: some View {
        VStack(spacing: 0) {
            track
            HStack(spacing: 0) {
                let padding = (isActive ? 0 : config.growth) + config.maxStretch
                styled(leadingLabel)
                    .padding(.leading, padding - leadingStretch)

                Spacer()
                styled(trailingLabel)
                    .padding(.trailing, padding - trailingStretch)
            }
        }
    }

    var sideLabeledTrack: some View {
        HStack(spacing: 0) {
            let padding = (isActive ? 0 : config.growth) + config.maxStretch
            styled(leadingLabel)
                .offset(x: padding - leadingStretch)
            track

            styled(trailingLabel)
                .offset(x: trailingStretch - padding)
        }
    }

    var track: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Capsule()
                    .fill(config.maximumTrackColor)
                    .blendMode(config.blendMode)

                let fillWidth = max(0, normalized(value)
                    * trackWidth(for: size.width, active: isActive)
                    - leadingStretch
                    + trailingStretch)
                Capsule()
                    .fill(isActive ? config.minimumTrackActiveColor : config.minimumTrackInactiveColor)
                    .blendMode(isActive ? .normal : config.blendMode)
                    .mask(
                        Rectangle()
                            .frame(width: fillWidth)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                // Indeterminate loading: a comet gliding along the track while
                // the media buffers (see `.sliderLoading`). Mounted only while
                // loading so the loop dies with the view.
                if isLoading {
                    TrackLoadingSweep(tint: isActive ? config.minimumTrackActiveColor : config.minimumTrackInactiveColor)
                        .clipShape(Capsule())
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isLoading)
            .preference(key: SizePreferenceKey.self, value: size)
            .frame(
                height: isActive
                    ? config.activeHeight - abs(normalizedStretchingValue) * config.stretchNarrowing
                    : config.inactiveHeight
            )
            .padding(.horizontal, isActive ? 0 : config.growth)
            .padding(.leading, config.maxStretch - leadingStretch)
            .padding(.trailing, config.maxStretch - trailingStretch)
            .onPreferenceChange(SizePreferenceKey.self) { [$viewSize] value in
                $viewSize.wrappedValue = value
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isActive) { _, out, _ in
                        out = true
                    }
                    .onChanged { value in
                        let progress = (value.translation.width / trackWidth(for: size.width, active: true))
                            * range.distance
                            + lastStoredValue
                        self.value = Double(progress).clamped(to: range)
                        if progress < range.lowerBound {
                            stretchingValue = normalized(progress - range.lowerBound)
                        }
                        if progress > range.upperBound {
                            stretchingValue = normalized(progress - range.upperBound)
                        }
                        onValueChanged?(self.value)
                    }
                    .onEnded { _ in
                        lastStoredValue = value
                        stretchingValue = 0
                    }
            )
        }
        .frame(
            height: max(0, isActive
                ? config.activeHeight - abs(normalizedStretchingValue) * config.stretchNarrowing
                : config.inactiveHeight)
        )
    }

    var normalizedStretchingValue: CGFloat {
        guard config.maxStretch != 0 else { return 0 }
        let trackWidth = activeTrackWidth
        guard trackWidth != 0, viewSize.width > config.maxStretch * 2 else { return 0 }
        let max = config.maxStretch / trackWidth / config.pushStretchRatio
        return stretchingValue.clamped(to: -max ... max) / max
    }

    var leadingStretch: CGFloat {
        let value = normalizedStretchingValue
        let stretch = abs(value) * config.maxStretch
        return value < 0 ? stretch : -stretch * config.pullStretchRatio
    }

    var trailingStretch: CGFloat {
        let value = normalizedStretchingValue
        let stretch = abs(value) * config.maxStretch
        return stretchingValue > 0 ? stretch : -stretch * config.pullStretchRatio
    }

    func normalized(_ value: CGFloat) -> CGFloat {
        (value - range.lowerBound) / range.distance
    }

    var activeTrackWidth: CGFloat {
        trackWidth(for: viewSize.width, active: true)
    }

    func trackWidth(for viewWidth: CGFloat, active: Bool) -> CGFloat {
        max(0, viewWidth - config.maxStretch * 2 - (active ? 0 : config.growth * 2))
    }
}

// MARK: Convenience initializers

public extension ElasticSlider where LeadingContent == EmptyView, TrailingContent == EmptyView {
    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        onActive: ((Bool) -> Void)? = nil
    ) {
        _value = value
        self.range = range
        lastStoredValue = value.wrappedValue
        leadingLabel = nil
        trailingLabel = nil
        self.onActive = onActive
    }
}

// MARK: config

public struct ElasticSliderConfig {
    public enum LabelLocation {
        case bottom
        case side
    }

    public let labelLocation: LabelLocation
    public let activeHeight: CGFloat
    public let inactiveHeight: CGFloat
    public let growth: CGFloat
    public let stretchNarrowing: CGFloat
    public let maxStretch: CGFloat
    public let pushStretchRatio: CGFloat
    public let pullStretchRatio: CGFloat
    public let minimumTrackActiveColor: Color
    public let minimumTrackInactiveColor: Color
    public let maximumTrackColor: Color
    public let blendMode: BlendMode
    public let syncLabelsStyle: Bool
    public let defaultSensoryFeedback: Bool

    public init(
        labelLocation: ElasticSliderConfig.LabelLocation = .side,
        activeHeight: CGFloat = 17,
        inactiveHeight: CGFloat = 7,
        growth: CGFloat = 9,
        stretchNarrowing: CGFloat = 4,
        maxStretch: CGFloat = 9,
        pushStretchRatio: CGFloat = 0.2,
        pullStretchRatio: CGFloat = 0.5,
        minimumTrackActiveColor: Color = .init(UIColor.tintColor),
        minimumTrackInactiveColor: Color = .init(UIColor.systemGray3),
        maximumTrackColor: Color = .init(UIColor.systemGray6),
        blendMode: BlendMode = .normal,
        syncLabelsStyle: Bool = false,
        defaultSensoryFeedback: Bool = true
    ) {
        self.labelLocation = labelLocation
        self.activeHeight = activeHeight
        self.inactiveHeight = inactiveHeight
        self.growth = growth
        self.stretchNarrowing = stretchNarrowing
        self.maxStretch = maxStretch
        self.pushStretchRatio = pushStretchRatio
        self.pullStretchRatio = pullStretchRatio
        self.minimumTrackActiveColor = minimumTrackActiveColor
        self.minimumTrackInactiveColor = minimumTrackInactiveColor
        self.maximumTrackColor = maximumTrackColor
        self.blendMode = blendMode
        self.syncLabelsStyle = syncLabelsStyle
        self.defaultSensoryFeedback = defaultSensoryFeedback
    }
}

public extension ElasticSliderConfig {
    /// Compact thumbless bar for inline transports (chat audio attachments,
    /// listing clips, upload previews): calm — no elastic overshoot, no
    /// end-of-track haptic. Use this (not a stock `Slider`) inside scrollable
    /// content: SwiftUI's `Slider` loses its thumb drag under an ancestor
    /// `onTapGesture` (the app-wide tap-to-dismiss-keyboard), while
    /// ElasticSlider's own high-priority drag claims the touch first.
    static var inlineScrub: Self {
        Self(
            maxStretch: 0,
            minimumTrackActiveColor: .white,
            minimumTrackInactiveColor: .white,
            maximumTrackColor: .white.opacity(0.18),
            defaultSensoryFeedback: false
        )
    }
}

// MARK: Loading sweep

/// The slider's indeterminate loading treatment: a soft trail rising into a
/// bright head — a "comet" — sweeping the track left → right on a loop.
/// Looping-animation rules: the loop lives in this child's own state, starts
/// onAppear, and dies when the view unmounts (mount it only while loading).
private struct TrackLoadingSweep: View {
    let tint: Color
    @State private var sweeping = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let band = max(44, width * 0.3)
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(0), location: 0),
                    .init(color: tint.opacity(0.12), location: 0.6),
                    .init(color: tint.opacity(0.7), location: 0.94),
                    .init(color: tint.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: band)
            .offset(x: sweeping ? width : -band)
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: sweeping)
        }
        .allowsHitTesting(false)
        .onAppear { sweeping = true }
    }
}

// MARK: EnvironmentValues

public extension View {
    func sliderStyle(_ config: ElasticSliderConfig) -> some View {
        environment(\.elasticSliderConfig, config)
    }

    /// Shows the slider's indeterminate loading sweep along the track (e.g.
    /// while the player buffers). Purely visual — the slider stays interactive.
    func sliderLoading(_ loading: Bool) -> some View {
        environment(\.elasticSliderLoading, loading)
    }
}

extension EnvironmentValues {
    @Entry var elasticSliderConfig = ElasticSliderConfig()
    @Entry var elasticSliderLoading = false
}

#Preview {
    @Previewable @State var progress = 0.5
    @Previewable @State var volume = 0.5
    let range = 0.0 ... 2
    VStack(spacing: 50) {
        ElasticSlider(
            value: $progress,
            in: range,
            leadingLabel: {
                Text(progress, format: .number.precision(.fractionLength(2)))
            },
            trailingLabel: {
                Text(
                    (range.upperBound - progress) * -1.0,
                    format: .number.precision(.fractionLength(2))
                )
            }
        )
        .sliderStyle(.init(labelLocation: .bottom, maxStretch: 0))
        .padding(.horizontal, 15)
        .frame(height: 50)

        ElasticSlider(
            value: $volume,
            in: 0 ... 1,
            leadingLabel: {
                Image(systemName: "speaker.fill")
                    .padding(.trailing, 4)
            },
            trailingLabel: {
                Image(systemName: "speaker.wave.3.fill")
                    .padding(.leading, 4)
            }
        )
        .sliderStyle(.init(labelLocation: .side, syncLabelsStyle: true))
        .frame(height: 50)
    }
}
