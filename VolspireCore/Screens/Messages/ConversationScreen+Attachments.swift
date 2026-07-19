//
//  ConversationScreen+Attachments.swift
//  Volspire
//
//  Thread loading skeleton and the inline audio-attachment player + its coordinator.
//

import AVFoundation
import DesignSystem
import Kingfisher
import MediaLibrary
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Loading skeleton (alternating bubble bones, soft pulse)

struct ThreadSkeleton: View {
    private let bone = Color.white.opacity(0.07)

    /// (fromMe, width) — a plausible-looking back-and-forth.
    private let rows: [(Bool, CGFloat)] = [
        (false, 180), (false, 120), (true, 200), (true, 90),
        (false, 220), (true, 150), (false, 110), (true, 230),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    if row.0 { Spacer(minLength: 56) }
                    UnevenRoundedRectangle(
                        topLeadingRadius: 19,
                        bottomLeadingRadius: row.0 ? 19 : 5,
                        bottomTrailingRadius: row.0 ? 5 : 19,
                        topTrailingRadius: 19,
                        style: .continuous
                    )
                    .fill(bone)
                    .frame(width: row.1, height: 40)
                    if !row.0 { Spacer(minLength: 56) }
                }
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shimmering()
    }
}

// MARK: - Audio attachment player

/// Inline audio player (play/pause + scrubber + time), mirroring the web's
/// AudioPreview. Streams the signed URL with its own AVPlayer. Shared beyond
/// chat: listing detail renders its audio clips with this same player.
/// Coordinates inline audio attachments so only one plays at a time — starting one
/// pauses whichever was already playing (each has its own AVPlayer and would
/// otherwise overlap).
@MainActor
private final class AudioAttachmentCoordinator {
    static let shared = AudioAttachmentCoordinator()
    private var activeToken: UUID?
    private var pauseActive: (() -> Void)?

    func play(token: UUID, pauseSelf: @escaping () -> Void) {
        if activeToken != token { pauseActive?() }
        activeToken = token
        pauseActive = pauseSelf
    }

    func stop(token: UUID) {
        if activeToken == token { activeToken = nil; pauseActive = nil }
    }
}

struct AudioAttachmentPlayer: View {
    let url: URL
    let name: String?
    /// Chat bubbles pin the fixed bubble width; pass nil to fill the container
    /// (listing clips).
    var fixedWidth: CGFloat? = 264
    /// Fired when this attachment starts playing (used to pause the app's music).
    var onStartPlaying: () -> Void = {}
    /// Fired on a long press (opens the attachment options sheet). While the
    /// press is held, the bubble darkens and sinks slightly as feedback.
    var onLongPress: (() -> Void)? = nil

    /// Long-press feedback state — drives the darken + sink.
    @State private var pressed = false

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var endObserver: (any NSObjectProtocol)?
    @State private var playToken = UUID()

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
                    LucideIcon(.music, .md).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "Audio").font(.appSubheadlineMedium).foregroundStyle(.white).lineLimit(1)
                    Text(metaText).font(.appCaption2).foregroundStyle(Color.vText3)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 11) {
                Button { toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        // Swap the glyph instantly (like the expanded player) — no fade.
                        .contentTransition(.identity)
                        .animation(nil, value: isPlaying)
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)

                // The player-style bar, not a stock `Slider` — see `.inlineScrub`.
                ElasticSlider(
                    value: Binding(get: { current }, set: { current = $0 }),
                    in: 0 ... max(duration, 0.1),
                    onActive: { active in
                        if active {
                            isSeeking = true
                        } else {
                            // Leave `isSeeking` true until the seek lands (see `seek`).
                            seek(to: current)
                        }
                    }
                )
                .sliderStyle(.inlineScrub)
                .frame(height: 22)

                Text("\(fmt(current)) / \(fmt(duration))")
                    .font(.appCaption2)
                    .foregroundStyle(Color.vText3)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(width: fixedWidth)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Press feedback for the long-press options: darken + sink while held.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(pressed ? 0.22 : 0))
                .allowsHitTesting(false)
        )
        .scaleEffect(pressed ? 0.97 : 1)
        .onLongPressGesture(minimumDuration: 0.4) {
            onLongPress?()
        } onPressingChanged: { pressing in
            guard onLongPress != nil else { return }
            // Ease in with a slight delay so quick taps (play, scrub) don't
            // flash the dim; release restores immediately.
            withAnimation(pressing ? .easeInOut(duration: 0.22).delay(0.08) : .easeOut(duration: 0.18)) {
                pressed = pressing
            }
        }
        .onDisappear(perform: teardown)
    }

    private var metaText: String {
        let ext = (name as NSString?)?.pathExtension.uppercased() ?? ""
        if duration > 0 {
            return ext.isEmpty ? fmt(duration) : "\(ext) · \(fmt(duration))"
        }
        return ext.isEmpty ? "Audio" : ext
    }

    /// Creates the AVPlayer, its observers, and the duration load lazily on first
    /// play. A thread full of clips otherwise spins up N AVPlayers + N remote
    /// `.duration` fetches in `onAppear` — before anyone taps play (open jank, data,
    /// battery). Idempotent: returns the existing player once created.
    @discardableResult
    private func ensurePlayer() -> AVPlayer {
        if let player { return player }
        let p = AVPlayer(url: url)
        player = p
        // Both callbacks are delivered on the main queue (`queue: .main`), so
        // hopping onto the main actor is assumption, not a thread switch.
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { time in
            MainActor.assumeIsolated {
                if !isSeeking { current = time.seconds }
            }
        }
        Task {
            guard let item = p.currentItem else { return }
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite {
                duration = d.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isPlaying = false
                current = 0
                p.seek(to: .zero)
                AudioAttachmentCoordinator.shared.stop(token: playToken)
            }
        }
        return p
    }

    private func teardown() {
        AudioAttachmentCoordinator.shared.stop(token: playToken)
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
    }

    private func toggle() {
        let player = ensurePlayer()
        if isPlaying {
            player.pause()
            isPlaying = false
            AudioAttachmentCoordinator.shared.stop(token: playToken)
        } else {
            if duration > 0, current >= duration - 0.1 { player.seek(to: .zero); current = 0 }
            // Pause the app's music and any other playing attachment first.
            onStartPlaying()
            AudioAttachmentCoordinator.shared.play(token: playToken) {
                player.pause()
                isPlaying = false
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { isSeeking = false; return }
        // Precise seek, and keep swallowing periodic-observer ticks until it lands.
        // Otherwise the observer fires once with the pre-seek time and the thumb
        // rubber-bands back to the old position before the player catches up.
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { _ in
            Task { @MainActor in isSeeking = false }
        }
    }

    private func fmt(_ s: Double) -> String { s.durationLabel }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    ConversationScreen(conversation: ActiveConversation(
        convoId: "preview", otherUserId: nil, username: "DJ Shadow", avatarURL: nil
    ))
    .withRouter()
    .environment(dependencies)
    .environment(playerController)
    .environment(ConversationState())
    .environment(AvatarPreviewState())
}
