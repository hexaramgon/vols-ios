//
//  TimedCommentsOverlay.swift
//  Volspire
//
//  SoundCloud-style timed comments. On the scrubber: a dot on the track at
//  every timestamped comment's start (dark over the played part, white
//  ahead). Over the artwork: `LiveCommentToast` — as playback
//  reaches a comment, the commenter and their words float in at the top of
//  the cover for a few seconds; tapping it opens the comments.
//
//  Laid over the TimingIndicator: x maps to the slider's track (inset by the
//  slider's `growth`), y is offset to the track's top edge (`trackTop`).
//

import DesignSystem
import Services
import SwiftUI

struct TimedCommentsOverlay: View {
    @Environment(PlayerController.self) private var controller
    let model: NowPlayingCommentsModel

    /// How long a comment stays "live" after its moment (ranges stay for
    /// their whole span, at least this long).
    static let liveSeconds: Double = 3.5
    private static let trackHeight: CGFloat = ElasticSliderConfig.playbackProgress.inactiveHeight
    private static let inset: CGFloat = ElasticSliderConfig.playbackProgress.growth
    /// Top of the slider's track within the TimingIndicator (measured).
    private static let trackTop: CGFloat = 13

    /// The current item's key — comments only count once they're its own.
    private var currentKey: String? {
        controller.currentFileId ?? controller.state.currentMediaID?.value
    }

    private var timed: [ApiTrackComment] {
        model.timedComments(for: currentKey)
    }

    var body: some View {
        let comments = timed
        let duration = controller.progress?.duration ?? 0
        if !comments.isEmpty, duration > 0 {
            GeometryReader { geo in
                let width = max(geo.size.width - Self.inset * 2, 1)
                let elapsed = controller.progress?.elapsedTime ?? 0
                ZStack(alignment: .topLeading) {
                    ForEach(comments) { comment in
                        marker(comment, duration: duration, width: width, elapsed: elapsed)
                    }
                }
                // The slider draws its track this far below the top of the
                // TimingIndicator's frame — line the dots up with it.
                .offset(y: Self.trackTop)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Markers

    private func x(_ seconds: Double, duration: Double, width: CGFloat) -> CGFloat {
        Self.inset + width * CGFloat(min(max(seconds / duration, 0), 1))
    }

    @ViewBuilder
    private func marker(_ c: ApiTrackComment, duration: Double, width: CGFloat, elapsed: Double) -> some View {
        let start = c.timestampSeconds ?? 0
        let passed = elapsed >= start
        let x0 = x(start, duration: duration, width: width)
        // Just where it begins (ranges too): a small, quiet dot on the track,
        // dark over the played (white) part, light over the unplayed (grey).
        MarkerDot(
            passed: passed,
            // Reveal sweeps left → right along the track as comments load.
            delay: 0.45 * min(max(start / duration, 0), 1)
        )
        // Re-run the entrance per item: the same comment id can't carry an
        // "already shown" state from the previous track.
        .id("\(currentKey ?? "")-\(c.id)")
        .offset(x: x0 - 1.5, y: (Self.trackHeight - 3) / 2)
        .allowsHitTesting(false)
    }

    /// One comment dot. Pops in (scale + fade, on a spring) the first time
    /// it appears; local state, so the per-tick progress re-renders of the
    /// overlay don't replay it.
    private struct MarkerDot: View {
        let passed: Bool
        let delay: Double
        @State private var shown = false

        var body: some View {
            Circle()
                .fill(passed ? Color.black.opacity(0.25) : Color.white.opacity(0.5))
                .frame(width: 3, height: 3)
                .scaleEffect(shown ? 1 : 0.01)
                .opacity(shown ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55).delay(delay)) {
                        shown = true
                    }
                }
        }
    }

    /// At most this many comments stack over the cover at once.
    static let maxLive = 3

    /// Every comment live at `t` — the newest moment last — capped to the
    /// most recent `maxLive`, so a burst of comments at one spot stacks
    /// instead of replacing each other.
    static func liveComments(in comments: [ApiTrackComment], at t: Double) -> [ApiTrackComment] {
        let live = comments.filter { c in
            guard let start = c.timestampSeconds else { return false }
            let end = max(c.timestampEndSeconds ?? start, start + liveSeconds)
            return t >= start && t < end
        }
        return Array(live.suffix(maxLive))
    }
}


extension NowPlayingCommentsModel {
    /// Top-level timestamped comments for the playing item (`key` = its file
    /// or track id), in time order — empty until its own comments have loaded.
    func timedComments(for key: String?) -> [ApiTrackComment] {
        guard let loaded = loadedKey, let key,
              loaded.caseInsensitiveCompare(key) == .orderedSame else { return [] }
        return comments
            .filter { $0.parentId == nil && $0.timestampSeconds != nil }
            .sorted { ($0.timestampSeconds ?? 0) < ($1.timestampSeconds ?? 0) }
    }
}

// MARK: - Live comment toast

/// The comments playback is at, floating over the top of the artwork — up to
/// `TimedCommentsOverlay.maxLive` stacked when several land close together:
/// avatar, @name and up to two lines of each on a dark glassy pill. Reads the
/// live progress itself, so only this view re-renders per tick.
struct LiveCommentToast: View {
    @Environment(PlayerController.self) private var controller
    let model: NowPlayingCommentsModel
    var onOpenComments: () -> Void = {}

    private var live: [ApiTrackComment] {
        guard !controller.isScrubbing else { return [] }
        let key = controller.currentFileId ?? controller.state.currentMediaID?.value
        let comments = model.timedComments(for: key)
        guard !comments.isEmpty else { return [] }
        return TimedCommentsOverlay.liveComments(in: comments, at: controller.progress?.elapsedTime ?? 0)
    }

    var body: some View {
        let comments = live
        // Stacked top-down, newest at the bottom: each new one slides in
        // beneath the others; older ones step back a little.
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(Array(comments.enumerated()), id: \.element.id) { i, comment in
                let depth = comments.count - 1 - i
                pill(comment)
                    .scaleEffect(1 - CGFloat(depth) * 0.04, anchor: .trailing)
                    .opacity(1 - Double(depth) * 0.18)
                    // Slides in from the right — from the comments panel,
                    // which lives just off-screen to the right — and back out.
                    .transition(.offset(x: 56).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(.smooth(duration: 0.35), value: comments.map(\.id))
    }

    private func pill(_ comment: ApiTrackComment) -> some View {
        Button {
            model.highlightedCommentId = comment.id
            onOpenComments()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                AvatarView(urlString: comment.user.profileImageUrl, name: comment.user.username, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("@\(comment.user.username ?? "someone")")
                        .font(.appCaptionMedium)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(comment.content)
                        .font(.appFootnote)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Comment by \(comment.user.username ?? "someone"): \(comment.content)")
    }
}
