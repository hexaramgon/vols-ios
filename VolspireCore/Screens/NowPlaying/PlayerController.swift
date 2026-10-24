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
import Visualizer
import SharedUtilities

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
    /// The current video's item is ready to play — per item, so it resets the
    /// instant a new track's player item arrives (the progress bar's duration
    /// lingers from the previous track for a frame and can't be trusted).
    var videoReady = false
    private var videoReadyObservation: AnyCancellable?

    var state: MediaPlayerState = .paused(media: .none)
    /// True while the current track is loading/buffering (no audio yet) — the UI
    /// shows a spinner in place of the play/pause glyph.
    var isBuffering = false
    var commandProfile: CommandProfile = .init(isSwitchTrackEnabled: false)
    /// Dominant artwork colours for the background wash (empty → brand wash).
    var colors: [Color] = []
    /// The cover shrunk to a 4×4 grid (row-major) — the background mesh's
    /// colours. Empty → the plain gradient wash.
    var meshColors: [Color] = []
    var progress: PlaybackProgress?
    var isScrubbing: Bool = false
    var nowPlayingMeta: MediaMeta?
    var audioEffects: AudioEffects = .default
    /// Repeat toggle — replay the current track indefinitely when it ends. Mirrored
    /// to the player, which owns the auto-advance.
    var isRepeatOn = false
    /// Shuffle toggle — mirrored FROM the player (which owns the queue reorder),
    /// so shuffle-all entry points like a playlist's Shuffle button light it up too.
    var isShuffleOn = false
    /// When false (default), audio edits reset on track change; when true they
    /// carry to every track. Mirrors the web's "Carry to next track".
    var persistAudioEdits: Bool = false
    var showingEffectsSheet: Bool = false
    var trackDetail: ApiTrackDetail?
    /// Saved state reads the shared LibraryStore — the single bookmark truth —
    /// so a save/unsave made on any list is reflected here instantly (and vice
    /// versa). Workspace files aren't tracks and are never "saved".
    /// (Like state and the like/save display counts were removed with the like
    /// button — nothing rendered them; the RPCs remain in SupabaseService.)
    var isSaved: Bool {
        guard currentFileId == nil, let id = state.currentMediaID?.value else { return false }
        return library?.isSaved(id) ?? false
    }
    /// Set this to trigger navigation to an artist's profile (collapses the player).
    var pendingProfileNavigation: String?

    /// Profile behind the artist line, whichever kind of item is playing: a track's
    /// credited artist, or a workspace file's uploader (files have no `trackDetail`,
    /// so their tap used to do nothing at all).
    var currentArtistUserId: String? {
        if let fileArtist = fileArtistIdByMediaId[state.currentMediaID?.value ?? ""] { return fileArtist }
        return trackDetail?.artist?.userId
    }
    /// Non-nil when the current item is a workspace file (not a track) — drives the
    /// comments panel to load file comments instead of track comments. Derived from
    /// `fileIdByMediaId` as the queue advances.
    var currentFileId: String?
    /// Set to request the player auto-expand (e.g. tapping a workspace file).
    var pendingExpand = false
    /// Track-About payload for the centered glass modal. Set by the info strip;
    /// RENDERED BY OverlaidRootView as an in-hierarchy overlay — a material
    /// inside a fullScreenCover can't blur through the presentation boundary,
    /// so presenting it would lose the glass look.
    struct AboutModalPayload: Equatable {
        let artwork: Artwork
        let title: String
        let description: String?
        let tags: [String]
        /// Track length, captured when the card opens — reading the live
        /// progress here re-rendered the card on every playback tick.
        var duration: Double? = nil
    }

    var aboutModal: AboutModalPayload?

    /// media-id → file-id for the current workspace queue. Only file items appear;
    /// track-reference items are absent so they read as normal tracks.
    private var fileIdByMediaId: [String: String] = [:]
    /// Uploader per workspace-file media id — a file has no `trackDetail`, so this
    /// is the only route from the playing item to a profile.
    private var fileArtistIdByMediaId: [String: String] = [:]

    /// One item in a workspace play queue.
    struct WorkspacePlayItem: Sendable {
        let mediaId: String
        let fileId: String?    // nil for a real track (track-reference file)
        let title: String
        let artist: String
        let audioURL: URL
        let coverURL: URL?
        /// Who to open when the artist line is tapped. A file has no track detail
        /// to read an artist off, so its uploader comes along with the queue item.
        var artistUserId: String?
    }

    /// Feeds the expanded player's visualizer. Installed on the player's
    /// post-effects node when the player is attached; passive until then.
    let visualizerTap = VisualizerAudioTap()

    /// Fullscreen visualizer in the expanded player, rendered full-bleed
    /// behind the controls like portrait video. Toggled by the sparkles
    /// button on the artwork slot.
    var showVisualizer = false

    /// Visualizer applies to real audio tracks only — video already owns the
    /// full-bleed layer, and workspace files aren't tracks.
    var visualizerAvailable: Bool {
        guard FeatureFlags.visualizer, currentFileId == nil, !display.isVideoTrack else { return false }
        if case .videoPlayer = display.artwork { return false }
        return true
    }

    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
            // Tap only when the feature is on — otherwise "off" still pays for
            // sample conversion on every audio buffer.
            if let player, FeatureFlags.visualizer {
                visualizerTap.install(on: player.visualizerAudioNode)
            } else {
                visualizerTap.remove()
            }
        }
    }

    weak var mediaState: MediaState?

    /// The shared library store (set by `Dependencies`) — saved state and the
    /// save mutation route through it so every surface stays in sync.
    weak var library: LibraryStore?

    /// Set by `Dependencies` so discrete player actions (like/save) can be logged.
    var analytics: AnalyticsService?

    private var cancellables = Set<AnyCancellable>()
    private let supabaseService = SupabaseService()
    private var lastFetchedTrackId: String?

    /// True when a track is loaded — i.e. the mini player is visible above the
    /// tab bar. THE mini-player predicate (don't re-roll `display.title.isEmpty`).
    var hasMedia: Bool { !display.title.isEmpty }

    /// The mini player's occupied height above the tab bar (0 when hidden).
    var miniPlayerAllowance: CGFloat { hasMedia ? ViewConst.compactNowPlayingHeight + 16 : 0 }

    /// MEASURED height of the custom floating tab bar — written by RootTabView's
    /// onGeometryChange (it varies with Dynamic Type). Default matches the
    /// design-size bar so first layout is right.
    var tabBarHeight: CGFloat = 52

    /// The tab-root scroll clearance WITHOUT the mini player: home safe area +
    /// the floating tab bar. The static form (design-size bar) exists for the
    /// rare view with no controller in scope.
    static var baseBottomInset: CGFloat { ViewConst.safeAreaInsets.bottom + 52 }

    /// Bottom content inset for scrolls that sit under the floating tab bar,
    /// growing when the mini player is showing — shared by every tab-root and
    /// pushed list screen (was copy-pasted 15×). Uses the MEASURED bar height,
    /// so large Dynamic Type can't underlap content.
    var contentBottomInset: CGFloat { ViewConst.safeAreaInsets.bottom + tabBarHeight + miniPlayerAllowance }

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
    /// the folder), starting at `mediaId`. File items load file comments instead of
    /// track ones; otherwise they use the same player as tracks (artwork panel,
    /// swipe to comments) minus the info strip.
    func playWorkspace(_ items: [WorkspacePlayItem], startAt mediaId: String) {
        guard !items.isEmpty else { return }
        var map: [String: String] = [:]
        var artistMap: [String: String] = [:]
        for item in items where item.fileId != nil {
            map[item.mediaId] = item.fileId
            artistMap[item.mediaId] = item.artistUserId
        }
        fileIdByMediaId = map
        fileArtistIdByMediaId = artistMap
        currentFileId = map[mediaId]
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

    /// Plays a single track outside any list context (e.g. a shared-track card in a
    /// DM). Registers it, then plays a one-item queue as a normal (non-workspace)
    /// track.
    func playSingle(_ media: Media) {
        guard media.meta.audioURL != nil else { return }
        fileIdByMediaId = [:]
        fileArtistIdByMediaId = [:]
        currentFileId = nil
        Task {
            await mediaState?.addTrack(media)
            player?.play(media.id, of: [media.id])
        }
    }

    func onForward() {
        player?.forward()
    }

    func onBackward() {
        player?.backward()
    }

    /// Straight to the previous track (no restart-if-3s-in) — the full-screen
    /// video swipe.
    func onPreviousTrack() {
        player?.backward(alwaysPrevious: true)
    }

    /// Toggle repeating the current track (the repeat button).
    func toggleRepeat() {
        isRepeatOn.toggle()
        player?.repeatEnabled = isRepeatOn
    }

    /// Toggle queue shuffle (the shuffle button). State flows back via the
    /// player's `shuffleEnabled` publisher.
    func toggleShuffle() {
        player?.setShuffle(!isShuffleOn)
    }

    /// Sign-out teardown for the controller's own per-user state — the player
    /// itself is cleared by `MediaPlayer.reset()`, whose publishers then reset
    /// the mirrored display/progress/state here.
    func resetForSignOut() {
        trackDetail = nil
        lastFetchedTrackId = nil
        fileIdByMediaId = [:]
        fileArtistIdByMediaId = [:]
        currentFileId = nil
        isRepeatOn = false
        persistAudioEdits = false
        audioEffects = .default
        showVisualizer = false
        pendingProfileNavigation = nil
        pendingExpand = false
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

    /// Saves/unsaves the current track through the shared LibraryStore (which
    /// flips the bookmark optimistically and rolls back on failure).
    func toggleSave() async {
        guard currentFileId == nil, let trackId = state.currentMediaID?.value, let library else { return }
        let next = !isSaved
        Haptics.impact(.soft) // very subtle tap on save/unsave (matches Follow)
        analytics?.log(next ? .trackSaved : .trackUnsaved, trackId: trackId)
        await library.setSaved(next, trackId: trackId)
    }
}

private extension PlayerController {
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
                self.preloadNeighbors()
            }
            .store(in: &cancellables)

        player.$commandProfile
            .sink { [weak self] commandProfile in
                if let commandProfile {
                    self?.commandProfile = commandProfile
                }
            }
            .store(in: &cancellables)

        player.$avPlayer
            .sink { [weak self] avPlayer in self?.observeVideoReadiness(avPlayer) }
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

        player.$shuffleEnabled
            .sink { [weak self] enabled in self?.isShuffleOn = enabled }
            .store(in: &cancellables)
    }

    /// Follows the video player's CURRENT item: false the moment it swaps,
    /// true once that item is ready AND actually playing — "ready" alone
    /// arrives a beat before the first frame draws, which showed a black box
    /// between the cover and the video.
    func observeVideoReadiness(_ avPlayer: AVPlayer?) {
        videoReady = false
        guard let avPlayer else {
            videoReadyObservation = nil
            return
        }
        let playing = avPlayer.publisher(for: \.timeControlStatus).map { $0 == .playing }
        // Per item: starts false, turns true once ready + playing (+ a beat
        // for the first frame), then stays true for that item — a pause or a
        // rebuffer must not swap the video back to the cover.
        videoReadyObservation = avPlayer.publisher(for: \.currentItem)
            .map { item -> AnyPublisher<Bool, Never> in
                guard let item else { return Just(false).eraseToAnyPublisher() }
                return item.publisher(for: \.status)
                    .map { $0 == .readyToPlay }
                    .combineLatest(playing)
                    .map { $0 && $1 }
                    .scan(false) { shown, now in shown || now }
                    .removeDuplicates()
                    .map { ready -> AnyPublisher<Bool, Never> in
                        ready
                            ? Just(true).delay(for: .milliseconds(150), scheduler: DispatchQueue.main).eraseToAnyPublisher()
                            : Just(false).eraseToAnyPublisher()
                    }
                    .switchToLatest()
                    .eraseToAnyPublisher()
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in self?.videoReady = ready }
    }

    func updateDisplay(withMeta meta: MediaMeta?, avPlayer: AVPlayer?) async {
        nowPlayingMeta = meta
        if let meta {
            let isVideo = meta.audioURL.map(MediaPlayer.isVideoURL) ?? false

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

            colors = await meta.colors
            meshColors = await meta.meshColors
        } else {
            display = .placeholder
            nowPlayingMeta = nil
            // Don't clear videoAspect here — meta goes momentarily nil between
            // tracks, and clearing would bounce a full-screen video's panel up. The
            // next track's `updateDisplay` sets it correctly (or clears it if the
            // next track is confirmed non-video).
            colors = [] // no artwork → the background's brand-wash fallback
            meshColors = []
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

    // MARK: Feed neighbours

    /// TikTok-style read-ahead for the feed: the covers of the previous and
    /// next two items, and the next two tracks' details (the RPC is cached,
    /// so landing on them reads from memory). Audio for the next two is
    /// prefetched by the player itself.
    private func preloadNeighbors() {
        guard let player, state.currentMediaID != nil else { return }
        let offsets = [1, 2, -1]
        let covers = offsets.compactMap { player.neighborMeta($0)?.artwork }
        ArtworkView.prefetch(covers, side: RegularNowPlaying.coverSide)
        let ids = [1, 2].compactMap { player.neighborID($0)?.value }
            .filter { fileIdByMediaId[$0] == nil && $0 != state.currentMediaID?.value }
        guard !ids.isEmpty else { return }
        Task { [supabaseService] in
            for id in ids { _ = try? await supabaseService.getTrackMetadata(trackId: id) }
        }
    }

    func fetchTrackDetailIfNeeded() {
        // A workspace file isn't a track — no track detail / like / save to fetch.
        if currentFileId != nil {
            trackDetail = nil
            return
        }
        guard let trackId = state.currentMediaID?.value else { return }
        // Already have THIS track's detail? Nothing to do. Case-insensitive because a
        // MediaID.value and the RPC's `track_id` can differ in case across queue sources
        // ([[user-id-casing]]). Keying off the loaded detail (not `lastFetchedTrackId`)
        // is what self-heals: landing on a track whose fetch was dropped/superseded
        // during rapid skipping still (re)fetches instead of early-returning.
        if let loaded = trackDetail?.trackId,
           loaded.caseInsensitiveCompare(trackId) == .orderedSame { return }

        // Reset per-track UI state + audio effects ONLY on a genuine track change — a
        // self-healing re-fetch of the SAME track must NOT wipe the user's speed/pitch.
        if lastFetchedTrackId?.caseInsensitiveCompare(trackId) != .orderedSame {
            lastFetchedTrackId = trackId
            trackDetail = nil
            // New track starts at 1× unless "carry edits" is on.
            if !persistAudioEdits, audioEffects != .default {
                applyEffects(.default)
            }
        }
        // Independent RPCs, fetched in parallel — serialized, every track skip
        // paid two round-trips before the like/save glyphs settled.
        Task {
            // Saved state — separate RPC, mirrors the web's get_track_interaction_status.
            if let status = try? await supabaseService.getTrackInteractionStatus(trackId: trackId) {
                guard state.currentMediaID?.value.caseInsensitiveCompare(trackId) == .orderedSame else { return }
                // Saved truth lives in the shared store; feed it the server's
                // answer (it ignores ids with an optimistic write in flight).
                library?.reconcileSaved(trackId: trackId, isSaved: status.isSaved)
            }
        }
        Task {
            do {
                let detail = try await supabaseService.getTrackMetadata(trackId: trackId)
                // Write only if this track is STILL the one playing — guard against the
                // CURRENT media id (what `detailLoaded` compares), not the last-requested
                // one, so a superseded fetch can't leave the strip stuck shimmering.
                guard state.currentMediaID?.value.caseInsensitiveCompare(trackId) == .orderedSame else { return }
                trackDetail = detail
            } catch {
                debugLog("[PlayerController] getTrackMetadata failed: \(error)")
            }
        }
    }
}

extension MediaMeta {
    /// Dominant artwork colours — EMPTY when there's no artwork (or extraction
    /// fails), so the player background falls back to the brand wash instead of
    /// tinting grey. (Both consumers are NowPlayingBackground instances.)
    var colors: [Color] {
        get async {
            guard let artwork else { return [] }
            // .fair (10k px), not .high (100k px): the histogram feeds a blurred
            // background wash, where the two are indistinguishable — .high cost
            // ~20MB of transient allocation per track skip.
            return await artwork
                .image?
                .dominantColorFrequencies(with: .fair)?
                .map { Color(uiColor: $0.color) } ?? []
        }
    }
}

extension MediaMeta {
    /// The cover averaged down to 4×4 pixels, row-major from the top-left —
    /// one colour per mesh point, so the background echoes the cover's layout
    /// as well as its palette. Done once per track (a 16-pixel draw); empty
    /// when there's no artwork.
    var meshColors: [Color] {
        get async {
            guard let artwork, let cg = await artwork.image?.cgImage else { return [] }
            let side = 4
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
                guard let ctx = CGContext(
                    data: buffer.baseAddress, width: side, height: side,
                    bitsPerComponent: 8, bytesPerRow: side * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else { return false }
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
                return true
            }
            guard drawn else { return [] }
            return (0..<(side * side)).map { i in
                Color(red: Double(pixels[i * 4]) / 255,
                      green: Double(pixels[i * 4 + 1]) / 255,
                      blue: Double(pixels[i * 4 + 2]) / 255)
            }
        }
    }
}

extension PlayerController {
    /// Any queue item's metadata — what the feed's pages draw.
    func meta(for id: MediaID) -> MediaMeta? {
        player?.mediaState?.metaOfMedia(withID: id)
    }

    /// The queue item `offset` steps from `id` (the feed's centre page).
    func neighborID(of id: MediaID, _ offset: Int) -> MediaID? {
        player?.neighborID(of: id, offset)
    }

    /// Plays exactly the track the feed landed on.
    func skip(to id: MediaID) {
        player?.skip(to: id)
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
