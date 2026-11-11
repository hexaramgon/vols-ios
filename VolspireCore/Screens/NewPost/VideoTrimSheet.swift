//
//  VideoTrimSheet.swift
//  Volspire
//
//  Time-trim for a video picked in New Track: the clip on top (looping just
//  the kept part, tap to play / pause), a filmstrip with start / end handles
//  and a playhead, the kept times, then Reset and the Cancel / Save footer.
//  Works on the UNTRIMMED prepared clip, so a trim can be widened again; the
//  cut itself (passthrough, no re-encode) is `UploadTrackViewModel.applyVideoTrim`.
//

import AVFoundation
import DesignSystem
import SwiftUI

struct VideoTrimSheet: View {
    let initialRange: ClosedRange<Double>
    let onSave: (ClosedRange<Double>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var model: VideoTrimModel

    init(url: URL, duration: Double, range: ClosedRange<Double>?, onSave: @escaping (ClosedRange<Double>) -> Void) {
        let initial = range ?? 0 ... duration
        initialRange = initial
        self.onSave = onSave
        _model = State(initialValue: VideoTrimModel(url: url, duration: duration, range: initial))
    }

    private var range: ClosedRange<Double> { model.start ... model.end }
    private var isWhole: Bool { model.start <= 0.05 && model.end >= model.duration - 0.05 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .scissors, title: "Trim video",
                        subtitle: "Keep \(Self.time(model.end - model.start)) of \(Self.time(model.duration))") {
                dismiss()
            }

            VStack(alignment: .leading, spacing: 16) {
                preview

                VideoTrimBar(model: model)

                HStack {
                    Text(Self.time(model.start))
                    Spacer()
                    Text(Self.time(model.end - model.start)).foregroundStyle(Color.vText)
                    Spacer()
                    Text(Self.time(model.end))
                }
                .font(.appFootnoteMedium)
                .monospacedDigit()
                .foregroundStyle(Color.vText3)

                Spacer(minLength: 0)

                if !isWhole {
                    Button("Reset to full clip") {
                        Haptics.selection()
                        model.reset()
                    }
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(Color.vText2)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                }

                CancelSendButtons(
                    sendTitle: "Save",
                    canSend: abs(model.start - initialRange.lowerBound) > 0.05
                        || abs(model.end - initialRange.upperBound) > 0.05,
                    isSending: false,
                    onCancel: { dismiss() },
                    onSend: {
                        onSave(range)
                        dismiss()
                    }
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .sheetBackground()
        .task { await model.load() }
        .onDisappear { model.teardown() }
    }

    /// The clip in its own shape (no bars), capped to ~40% of the screen;
    /// tap to play / pause.
    private var preview: some View {
        let maxHeight = (UIScreen.size.height * 0.4).rounded()
        let aspect = model.aspect ?? 16 / 9
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Color.vShade)
            PlayerVideoView(player: model.player, gravity: .resizeAspect)
            if !model.isPlaying {
                LucideIcon(.playFill, .lg)
                    .foregroundStyle(.white)
                    .offset(x: 1)
                    .frame(width: 52, height: 52)
                    .background(.black.opacity(0.35), in: Circle())
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { model.togglePlay() }
        .alwaysDark()
        .animation(.easeInOut(duration: 0.15), value: model.isPlaying)
        .accessibilityLabel(model.isPlaying ? "Pause" : "Play")
        .accessibilityAddTraits(.isButton)
    }

    /// "0:07", "1:32".
    static func time(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}

// MARK: - Model

/// The trim sheet's player + selection. Playback stays inside start...end
/// (it loops back to start); dragging a handle pauses and shows that frame.
@MainActor @Observable
final class VideoTrimModel {
    let player: AVPlayer
    let duration: Double
    var start: Double
    var end: Double
    private(set) var current: Double
    private(set) var isPlaying = false
    private(set) var thumbnails: [UIImage] = []
    /// Width / height of the clip, transform-corrected.
    private(set) var aspect: CGFloat?

    /// The shortest clip a trim can keep.
    static let minLength: Double = 1
    static let thumbnailCount = 8

    private let url: URL
    private var timeObserver: Any?

    init(url: URL, duration: Double, range: ClosedRange<Double>) {
        self.url = url
        self.duration = duration
        start = range.lowerBound
        end = range.upperBound
        current = range.lowerBound
        player = AVPlayer(url: url)
    }

    func load() async {
        attachObserver()
        seek(to: start)
        let asset = AVURLAsset(url: url)
        if let track = try? await asset.loadTracks(withMediaType: .video).first,
           let size = try? await track.load(.naturalSize),
           let transform = try? await track.load(.preferredTransform) {
            let r = size.applying(transform)
            if abs(r.height) > 0 { aspect = abs(r.width) / abs(r.height) }
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 160)
        let times = (0 ..< Self.thumbnailCount).map { i in
            CMTime(seconds: duration * (Double(i) + 0.5) / Double(Self.thumbnailCount), preferredTimescale: 600)
        }
        var images: [UIImage] = []
        for await result in generator.images(for: times) {
            if let cg = try? result.image { images.append(UIImage(cgImage: cg)) }
        }
        thumbnails = images
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            if current < start || current >= end - 0.05 { seek(to: start) }
            player.play()
            isPlaying = true
        }
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    /// A handle moved: pause and show the frame at `time`.
    func scrub(to time: Double) {
        pause()
        seek(to: time)
    }

    func reset() {
        start = 0
        end = duration
        scrub(to: 0)
    }

    func teardown() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func seek(to time: Double) {
        current = time
        player.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func attachObserver() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    private func tick(_ t: Double) {
        guard isPlaying else { return }
        current = t
        // Loop the kept part.
        if t >= end { seek(to: start) }
    }
}

// MARK: - Trim bar

/// The filmstrip with its two handles. Outside the kept range is dimmed; the
/// kept range is framed in ink; the white line is the playhead.
private struct VideoTrimBar: View {
    let model: VideoTrimModel

    private let height: CGFloat = 56
    private let handleWidth: CGFloat = 16
    /// Where each handle was when its drag began.
    @State private var dragOrigin: Double?

    var body: some View {
        GeometryReader { geo in
            let track = max(geo.size.width - handleWidth * 2, 1)
            let perSecond = track / CGFloat(max(model.duration, 0.01))
            let x = { (t: Double) -> CGFloat in handleWidth + CGFloat(t) * perSecond }

            ZStack(alignment: .topLeading) {
                filmstrip(width: track)
                    .offset(x: handleWidth)

                // Dim what gets cut.
                Color.black.opacity(0.55)
                    .frame(width: max(0, x(model.start) - handleWidth), height: height)
                    .offset(x: handleWidth)
                Color.black.opacity(0.55)
                    .frame(width: max(0, handleWidth + track - x(model.end)), height: height)
                    .offset(x: x(model.end))

                // The kept range: an ink frame joining the two handles.
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.vInverse, lineWidth: 3)
                    .frame(width: x(model.end) - x(model.start) + handleWidth * 2, height: height)
                    .offset(x: x(model.start) - handleWidth)
                    .allowsHitTesting(false)

                // Playhead.
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: height + 8)
                    .shadow(color: .black.opacity(0.4), radius: 2)
                    .offset(x: x(min(max(model.current, model.start), model.end)) - 1.5, y: -4)
                    .allowsHitTesting(false)

                handle(leading: true)
                    .offset(x: x(model.start) - handleWidth)
                    .gesture(drag(perSecond: perSecond, leading: true))
                handle(leading: false)
                    .offset(x: x(model.end))
                    .gesture(drag(perSecond: perSecond, leading: false))
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trim range")
        .accessibilityValue("\(VideoTrimSheet.time(model.start)) to \(VideoTrimSheet.time(model.end))")
    }

    private func filmstrip(width: CGFloat) -> some View {
        let count = max(model.thumbnails.count, 1)
        return HStack(spacing: 0) {
            if model.thumbnails.isEmpty {
                Color.vSkeleton
            } else {
                ForEach(model.thumbnails.indices, id: \.self) { i in
                    Image(uiImage: model.thumbnails[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: width / CGFloat(count), height: height)
                        .clipped()
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    private func handle(leading: Bool) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: leading ? 6 : 0, bottomLeadingRadius: leading ? 6 : 0,
            bottomTrailingRadius: leading ? 0 : 6, topTrailingRadius: leading ? 0 : 6,
            style: .continuous
        )
        .fill(Color.vInverse)
        .frame(width: handleWidth, height: height)
        .overlay {
            Capsule().fill(Color.vOnInverse).frame(width: 3, height: 18)
        }
        // A wider grab area than the 16pt handle.
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .padding(.horizontal, -14)
    }

    private func drag(perSecond: CGFloat, leading: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let origin = dragOrigin ?? (leading ? model.start : model.end)
                if dragOrigin == nil {
                    dragOrigin = origin
                    Haptics.selection()
                }
                let moved = origin + Double(value.translation.width / perSecond)
                if leading {
                    model.start = min(max(0, moved), model.end - VideoTrimModel.minLength)
                    model.scrub(to: model.start)
                } else {
                    model.end = max(min(model.duration, moved), model.start + VideoTrimModel.minLength)
                    model.scrub(to: model.end)
                }
            }
            .onEnded { _ in
                dragOrigin = nil
                // Ready to play the kept part from its start.
                model.scrub(to: model.start)
            }
    }
}
