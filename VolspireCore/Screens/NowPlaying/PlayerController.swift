//
//  PlayerController.swift
//  Volspire
//

import Combine
import DesignSystem
import AVFoundation
import MediaLibrary
import Player
import Services
import SwiftUI
import UIKit

@Observable @MainActor
final class PlayerController {
    struct Display: Hashable {
        let artwork: Artwork
        /// Album artwork for contexts that should not show video (e.g. info strip thumbnail).
        let albumArtwork: Artwork
        let title: String
        let subtitle: String
        /// True when the track is a video (known from metadata) even before its
        /// AVPlayer is ready — lets the UI show a loading state instead of briefly
        /// flashing the album cover while the video player spins up.
        var isVideoTrack: Bool = false
    }

    var display: Display = .placeholder

    /// Rotation-corrected pixel size of the currently playing video (nil for audio
    /// or before it loads). Drives the full-bleed portrait-video layout in the
    /// expanded player.
    var videoAspect: CGSize?

    var state: MediaPlayerState = .paused(media: .none)
    /// True while the current track is loading/buffering (no audio yet) — the UI
    /// shows a spinner in place of the play/pause glyph.
    var isBuffering = false
    var commandProfile: CommandProfile = .init(isLiveStream: false, isSwitchTrackEnabled: false)
    var colors: [UIColor] = []
    var progress: PlaybackProgress?
    var isScrubbing: Bool = false
    var nowPlayingMeta: MediaMeta?
    var audioEffects: AudioEffects = .default
    /// When false (default), audio edits reset on track change; when true they
    /// carry to every track. Mirrors the web's "Carry to next track".
    var persistAudioEdits: Bool = false
    var showingEffectsSheet: Bool = false
    var trackDetail: ApiTrackDetail?
    /// Save/like state for the current track (mirrors the web's track interactions).
    var isLiked = false
    var isSaved = false
    var likeCount = 0
    var saveCount = 0
    /// Set this to trigger navigation to an artist's profile (collapses the player).
    var pendingProfileNavigation: String?
    /// Non-nil when the current item is a workspace file (not a track) — drives the
    /// comments panel to load file comments instead of track comments. Derived from
    /// `fileIdByMediaId` as the queue advances.
    var currentFileId: String?
    /// Set to request the player auto-expand (e.g. tapping a workspace file).
    var pendingExpand = false
    /// media-id → file-id for the current workspace queue. Only file items appear;
    /// track-reference items are absent so they read as normal tracks.
    private var fileIdByMediaId: [String: String] = [:]

    /// One item in a workspace play queue.
    struct WorkspacePlayItem: Sendable {
        let mediaId: String
        let fileId: String?    // nil for a real track (track-reference file)
        let title: String
        let artist: String
        let audioURL: URL
        let coverURL: URL?
    }

    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    weak var mediaState: MediaState?

    /// Set by `Dependencies` so discrete player actions (like/save) can be logged.
    var analytics: AnalyticsService?

    private var cancellables = Set<AnyCancellable>()
    private let supabaseService = SupabaseService()
    private var lastFetchedTrackId: String?

    var isLiveStream: Bool {
        commandProfile.isLiveStream
    }

    /// True when the current video is clearly portrait (taller than wide) — drives
    /// the full-bleed TikTok/Reels-style backdrop in the expanded player.
    var isPortraitVideo: Bool {
        guard let a = videoAspect, a.width > 0, a.height > 0 else { return false }
        return a.height > a.width * 1.05
    }

    /// The raw AVPlayer backing the current video, for a full-screen backdrop layer.
    var videoAVPlayer: AVPlayer? {
        if case let .videoPlayer(player) = display.artwork { return player }
        return nil
    }

    var playPauseButton: ButtonType {
        switch state {
        case .playing: .pause
        case .paused: .play
        }
    }

    /// True while the current track is loading and can't be controlled yet — the
    /// play/pause button is disabled + dimmed during this window.
    var isLoadingTrack: Bool { isBuffering && state.isPlaying }

    var backwardButton: ButtonType { .backward }
    var forwardButton: ButtonType { .forward }

    func onPlayPause() {
        player?.togglePlayPause()
    }

    /// Plays a workspace folder's files as a queue (so Next/Previous move through
    /// the folder), starting at `mediaId`. File items load file comments and open
    /// straight to the comments panel; track-reference items behave like tracks.
    func playWorkspace(_ items: [WorkspacePlayItem], startAt mediaId: String) {
        guard !items.isEmpty else { return }
        var map: [String: String] = [:]
        for item in items where item.fileId != nil { map[item.mediaId] = item.fileId }
        fileIdByMediaId = map
        currentFileId = map[mediaId]
        pendingExpand = currentFileId != nil   // files open straight to comments
        Task {
            for item in items {
                await mediaState?.addTrack(
                    Media(
                        id: MediaID(item.mediaId),
                        meta: MediaMeta(artwork: item.coverURL, title: item.title, artist: item.artist, audioURL: item.audioURL)
                    )
                )
            }
            player?.play(MediaID(mediaId), of: items.map { MediaID($0.mediaId) })
        }
    }

    func onForward() {
        player?.forward()
    }

    func onBackward() {
        player?.backward()
    }

    func seek(to time: TimeInterval) {
        // Optimistically reflect the new position so the scrubber doesn't snap back
        // to the stale elapsed time for a moment before the player's next progress
        // tick (every 0.5s) lands — that was the "rubber band" on release.
        if let duration = progress?.duration {
            progress = PlaybackProgress(elapsedTime: time, duration: duration)
        }
        player?.seek(to: time)
    }

    func applyEffects(_ effects: AudioEffects) {
        audioEffects = effects
        player?.applyEffects(effects)
    }

    /// Likes/unlikes the current track, optimistically updating state + count.
    func toggleLike() async {
        guard let trackId = state.currentMediaID?.value else { return }
        let next = !isLiked
        isLiked = next
        likeCount = max(0, likeCount + (next ? 1 : -1))
        analytics?.log(next ? .trackLiked : .trackUnliked, trackId: trackId)
        do {
            if next { try await supabaseService.likeTrack(trackId: trackId) }
            else { try await supabaseService.unlikeTrack(trackId: trackId) }
        } catch {
            isLiked = !next
            likeCount = max(0, likeCount + (next ? -1 : 1))
            print("[PlayerController] toggleLike failed: \(error)")
        }
    }

    /// Saves/unsaves the current track, optimistically updating state + count.
    func toggleSave() async {
        guard let trackId = state.currentMediaID?.value else { return }
        let next = !isSaved
        isSaved = next
        Haptics.impact(.soft) // very subtle tap on save/unsave (matches Follow)
        saveCount = max(0, saveCount + (next ? 1 : -1))
        analytics?.log(next ? .trackSaved : .trackUnsaved, trackId: trackId)
        do {
            if next { try await supabaseService.saveTrack(trackId: trackId) }
            else { try await supabaseService.unsaveTrack(trackId: trackId) }
        } catch {
            isSaved = !next
            saveCount = max(0, saveCount + (next ? -1 : 1))
            print("[PlayerController] toggleSave failed: \(error)")
        }
    }
}

private extension PlayerController {
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "webm"]

    private func observeMediaPlayerState() {
        guard let player else { return }
        cancellables.removeAll()
        player.$state
            .sink { [weak self] state in
                guard let self else { return }
                self.state = state
                // Whether the current queue item is a workspace file (vs a track).
                self.currentFileId = self.fileIdByMediaId[state.currentMediaID?.value ?? ""]
                self.fetchTrackDetailIfNeeded()
            }
            .store(in: &cancellables)

        player.$commandProfile
            .sink { [weak self] commandProfile in
                if let commandProfile {
                    self?.commandProfile = commandProfile
                }
            }
            .store(in: &cancellables)

        player.$nowPlayingMeta
            .combineLatest(player.$avPlayer)
            .sink { [weak self] meta, avPlayer in
                guard let self else { return }
                Task {
                    await self.updateDisplay(withMeta: meta, avPlayer: avPlayer)
                }
            }.store(in: &cancellables)

        player.$progress
            .sink { [weak self] prog in
                guard let self, !self.isScrubbing else { return }
                self.progress = prog
            }
            .store(in: &cancellables)

        player.$isBuffering
            .sink { [weak self] buffering in self?.isBuffering = buffering }
            .store(in: &cancellables)
    }

    func updateDisplay(withMeta meta: MediaMeta?, avPlayer: AVPlayer?) async {
        nowPlayingMeta = meta
        if let meta {
            let isVideo = meta.audioURL.map {
                Self.videoExtensions.contains($0.pathExtension.lowercased())
            } ?? false

            let albumArtwork: Artwork = .placeholder(meta.artwork, name: meta.title)
            let artwork: Artwork
            if isVideo, let avPlayer {
                artwork = .videoPlayer(avPlayer)
            } else {
                artwork = albumArtwork
            }

            display = .init(
                artwork: artwork,
                albumArtwork: albumArtwork,
                title: meta.title,
                subtitle: meta.artist ?? "",
                isVideoTrack: isVideo
            )

            // Load the video's real (rotation-corrected) aspect so the expanded
            // player can go full-bleed for portrait clips.
            if isVideo {
                // It's a video track: KEEP the current full-screen state and resolve
                // the new size in the background. Never clear here — the player item
                // and its size aren't ready yet while buffering, and clearing would
                // bounce the panel up and back down. Retry until the size resolves
                // (re-fetching currentItem each time, since it's nil mid-load),
                // re-checking the track token so a since-changed track is ignored.
                let token = meta.audioURL
                if let player = avPlayer {
                    Task { [weak self] in
                        for _ in 0 ..< 20 {
                            if let item = player.currentItem,
                               let aspect = await Self.loadVideoAspect(item) {
                                guard let self, self.nowPlayingMeta?.audioURL == token else { return }
                                self.videoAspect = aspect
                                return
                            }
                            try? await Task.sleep(for: .milliseconds(350))
                            guard let self, self.nowPlayingMeta?.audioURL == token else { return }
                        }
                    }
                }
            } else {
                // Confirmed a non-video track → not full screen.
                videoAspect = nil
            }

            colors = await meta.colors.map { UIColor($0) }
        } else {
            display = .placeholder
            nowPlayingMeta = nil
            // Don't clear videoAspect here — meta goes momentarily nil between
            // tracks, and clearing would bounce a full-screen video's panel up. The
            // next track's `updateDisplay` sets it correctly (or clears it if the
            // next track is confirmed non-video).
            colors = [UIColor(.graySecondary)]
        }
    }

    /// Reads a video's natural size and applies its preferred transform, so a
    /// portrait clip recorded on a landscape sensor reports as portrait. Stays
    /// MainActor-isolated (the `await`s free the actor during the metadata I/O) so
    /// the non-Sendable `AVPlayerItem` never crosses an isolation boundary.
    static func loadVideoAspect(_ item: AVPlayerItem) async -> CGSize? {
        let asset = item.asset
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let size = try? await track.load(.naturalSize),
              let transform = try? await track.load(.preferredTransform)
        else { return nil }
        let resolved = size.applying(transform)
        let w = abs(resolved.width), h = abs(resolved.height)
        guard w > 0, h > 0 else { return nil }
        return CGSize(width: w, height: h)
    }

    func fetchTrackDetailIfNeeded() {
        // A workspace file isn't a track — no track detail / like / save to fetch.
        if currentFileId != nil {
            trackDetail = nil; isLiked = false; isSaved = false; likeCount = 0; saveCount = 0
            return
        }
        guard let trackId = state.currentMediaID?.value,
              trackId != lastFetchedTrackId else { return }
        lastFetchedTrackId = trackId
        trackDetail = nil
        isLiked = false
        isSaved = false
        likeCount = 0
        saveCount = 0

        // The audio engine persists effects across tracks, so unless "carry" is on
        // we reset to default when the track changes (new track starts at 1×).
        if !persistAudioEdits, audioEffects != .default {
            applyEffects(.default)
        }
        Task {
            do {
                let detail = try await supabaseService.getTrackMetadata(trackId: trackId)
                guard lastFetchedTrackId == trackId else { return } // track changed mid-fetch
                trackDetail = detail
                likeCount = detail.likes ?? 0
                saveCount = detail.saves ?? 0
            } catch {
                print("[PlayerController] getTrackMetadata failed: \(error)")
            }
            // Save/like state — separate RPC, mirrors the web's get_track_interaction_status.
            if let status = try? await supabaseService.getTrackInteractionStatus(trackId: trackId) {
                guard lastFetchedTrackId == trackId else { return }
                isLiked = status.isLiked
                isSaved = status.isSaved
            }
        }
    }
}

extension MediaMeta {
    var colors: [Color] {
        get async {
            guard let artwork else { return [.graySecondary] }
            return await artwork
                .image?
                .dominantColorFrequencies(with: .high)?
                .map { Color(uiColor: $0.color) } ?? [.graySecondary]
        }
    }
}

extension PlayerController.Display {
    static var placeholder: Self {
        .init(
            artwork: .placeholder(),
            albumArtwork: .placeholder(),
            title: "",
            subtitle: ""
        )
    }
}
