//
//  MediaPlayer.swift
//  Volspire
//

import AVFoundation
import Combine
import MediaLibrary
import SharedUtilities
import UIKit

public enum MediaPlayerState: Equatable, Hashable {
    case playing(media: MediaID)
    case paused(media: MediaID?)
}

@MainActor
public final class MediaPlayer {
    public weak var mediaState: MediaState?
    private(set) var items: [MediaID] = []

    @Published public private(set) var progress: PlaybackProgress?
    @Published public private(set) var state: MediaPlayerState
    /// True while the current track is loading/buffering and no audio is playing
    /// yet — distinct from `state` (which reflects the intended play/pause).
    @Published public private(set) var isBuffering = false
    @Published public private(set) var commandProfile: CommandProfile?
    @Published public private(set) var nowPlayingMeta: MediaMeta?
    @Published public private(set) var avPlayer: AVPlayer?
    @Published public var audioEffects: AudioEffects = .default
    /// When true, the current track replays itself indefinitely when it ends
    /// (repeat-one); when false the queue advances normally. Driven by the repeat button.
    public var repeatEnabled = false
    /// Shuffle mode. On: `items` becomes a shuffled reordering of the queue with
    /// the current track pinned first; off restores the order the queue was
    /// started with. Persists across queue swaps — a queue started while shuffle
    /// is on gets shuffled too.
    @Published public private(set) var shuffleEnabled = false
    /// The queue in the order it was handed to `play(_:of:)`, so turning shuffle
    /// off can restore it.
    private var originalItems: [MediaID] = []

    private var audioSession: AudioSession
    private var systemMediaInterface: SystemMediaInterface
    private var urlPlayer: URLAudioPlayer

    /// Post-effects audio node the visualizer taps — see `URLAudioPlayer`.
    public var visualizerAudioNode: AVAudioNode { urlPlayer.visualizerAudioNode }
    private var interruptedMediaID: MediaID?
    /// Where playback was when the interruption hit — restored on resume.
    private var interruptedElapsedTime: TimeInterval = 0
    /// A position to restore after a track had to be RELOADED (interruption
    /// teardown, engine loss): applied on the first progress tick once the
    /// duration is known, and only if the track is still the current one.
    private var pendingResumeSeek: (mediaID: MediaID, time: TimeInterval)?
    /// Decoded now-playing artwork, resolved once per track rather than on every
    /// system-info push (the per-tick re-decode was a real CPU cost).
    private var cachedArtwork: UIImage?
    private var cachedArtworkID: MediaID?
    /// Remote tracks download async, so `duration` isn't known at the play push.
    /// We push once when it first becomes known, then let the OS interpolate.
    private var pushedDurationForCurrentTrack = false

    public init() {
        audioSession = AudioSession()
        systemMediaInterface = SystemMediaInterface()
        urlPlayer = URLAudioPlayer()
        state = .paused(media: .none)
        commandProfile = CommandProfile(isSwitchTrackEnabled: false)
        systemMediaInterface.setRemoteCommandProfile(commandProfile!)
        audioSession.delegate = self
        systemMediaInterface.delegate = self
        urlPlayer.delegate = self
    }

    // MARK: - Public Playback Controls

    public func togglePlayPause() {
        if state.isPlaying {
            pause()
        } else {
            resume()
        }
    }

    public func play(_ mediaID: MediaID, of items: [MediaID]) {
        guard items.contains(mediaID) else {
            print("MediaPlayer Error: there is no mediaID \(mediaID) in items.")
            return
        }
        originalItems = items
        self.items = shuffleEnabled ? Self.shuffledOrder(items, pinnedFirst: mediaID) : items
        guard let index = self.items.firstIndex(of: mediaID) else { return }
        playItem(at: index)
    }

    /// Turns shuffle on/off, reordering the live queue in place. The current
    /// track keeps playing: on shuffle it's pinned to the front with the rest
    /// shuffled behind it; off restores the original queue order at whatever
    /// position the track sits there.
    public func setShuffle(_ enabled: Bool) {
        guard enabled != shuffleEnabled else { return }
        shuffleEnabled = enabled
        guard !items.isEmpty else { return }
        if enabled {
            if let current = state.currentMediaID {
                items = Self.shuffledOrder(items, pinnedFirst: current)
            } else {
                items.shuffle()
            }
        } else if !originalItems.isEmpty {
            items = originalItems
        }
        // The upcoming track changed: re-point the gapless read-ahead and re-push
        // the lock-screen queue position.
        if let current = state.currentMediaID, let index = items.firstIndex(of: current) {
            prefetchNextTrack(after: index)
            updateSystemNowPlaying()
        }
    }

    public func forward() {
        // Repeat-one locks playback to the current track — skipping just restarts it.
        if repeatEnabled {
            seek(to: 0)
            return
        }
        // A single-track queue wraps to itself: restart instead of a dead button
        // (e.g. playing the only track on someone's profile).
        if items.count == 1 {
            seek(to: 0)
            return
        }
        guard items.count > 1,
              let mediaID = state.currentMediaID,
              let index = items.firstIndex(of: mediaID)
        else {
            return
        }
        let nextIndex = items.indices.contains(index + 1) ? index + 1 : 0
        playItem(at: nextIndex)
    }

    public func seek(to time: TimeInterval) {
        urlPlayer.seek(to: time)
        updateSystemNowPlaying()
    }

    public func applyEffects(_ effects: AudioEffects) {
        audioEffects = effects
        urlPlayer.applyEffects(effects)
        // Push the new rate so the system scrubber keeps interpolating correctly
        // (e.g. after changing speed to 1.5×).
        updateSystemNowPlaying()
    }

    /// Full teardown for sign-out: stops the audio engine (dropping the
    /// prefetched next track), clears the queue and every piece of published
    /// state, wipes the lock-screen entry, and deactivates the audio session.
    public func reset() {
        urlPlayer.stop()
        items = []
        originalItems = []
        shuffleEnabled = false
        repeatEnabled = false
        state = .paused(media: .none)
        progress = nil
        isBuffering = false
        nowPlayingMeta = nil
        avPlayer = nil
        cachedArtwork = nil
        cachedArtworkID = nil
        pushedDurationForCurrentTrack = false
        interruptedMediaID = nil
        interruptedElapsedTime = 0
        pendingResumeSeek = nil
        audioEffects = .default
        updateCommandProfile()
        systemMediaInterface.clearNowPlayingInfo()
        audioSession.setActive(false)
    }

    public func backward() {
        // Repeat-one locks playback to the current track — skipping just restarts it.
        if repeatEnabled {
            seek(to: 0)
            return
        }
        // Single-track queue: previous always means "start over".
        if items.count == 1 {
            seek(to: 0)
            return
        }
        // If more than 3 seconds in, restart the current track. Route through
        // `seek` (not `urlPlayer` directly) so the lock-screen scrubber is pushed
        // back to 0 too — otherwise it keeps showing the old position.
        if urlPlayer.elapsedTime > 3 {
            seek(to: 0)
            return
        }
        guard items.count > 1,
              let mediaID = state.currentMediaID,
              let index = items.firstIndex(of: mediaID)
        else {
            return
        }
        let nextIndex = items.indices.contains(index - 1) ? index - 1 : items.count - 1
        playItem(at: nextIndex)
    }
}

private extension MediaPlayer {
    func resume() {
        guard let mediaID = state.currentMediaID else {
            if let first = items.first {
                play(first, of: items)
            }
            return
        }

        if urlPlayer.currentURL != nil {
            audioSession.setActive(true)
            urlPlayer.resume()
            state = .playing(media: mediaID)
            updateCommandProfile()
            updateSystemNowPlaying()
        } else {
            if let index = items.firstIndex(of: mediaID) {
                // The engine lost the file (interruption teardown) — reload,
                // then restore the position we were at instead of starting over.
                if let elapsed = progress?.elapsedTime, elapsed > 1 {
                    pendingResumeSeek = (mediaID, elapsed)
                }
                playItem(at: index)
            }
        }
    }

    func pause() {
        guard case let .playing(mediaID) = state else { return }
        urlPlayer.pause()
        state = .paused(media: mediaID)
        updateSystemNowPlaying()
    }

    func playItem(at index: Int) {
        guard let mediaID = items[safe: index] else {
            print("MediaPlayer Error: Invalid index \(index)")
            return
        }

        if case let .playing(currentID) = state, currentID == mediaID {
            return
        }

        // NOTE: do NOT call `urlPlayer.stop()` here. That's a full teardown that
        // stops the audio engine and discards the prefetched next track — which
        // reintroduces the download/buffer gap that flips the lock screen to paused
        // on skip. `play(url:)` below already stops the current track while keeping
        // the engine + read-ahead alive (gapless switch).
        //
        // Reset the published progress now so the in-app scrubber snaps back to 0
        // (the URL player won't push a tick until the new track starts).
        progress = nil
        audioSession.setActive(true)

        if let meta = mediaState?.metaOfMedia(withID: mediaID),
           let audioURL = meta.audioURL
        {
            urlPlayer.play(url: audioURL)
        } else {
            print("MediaPlayer: No audio URL found for \(mediaID)")
            avPlayer = nil
        }

        state = .playing(media: mediaID)
        updateMeta()
        updateCommandProfile()
        prefetchNextTrack(after: index)
    }

    /// A shuffled queue order with `pinned` first — so enabling shuffle (or
    /// starting a queue with shuffle on) never interrupts the chosen track.
    static func shuffledOrder(_ items: [MediaID], pinnedFirst pinned: MediaID) -> [MediaID] {
        [pinned] + items.filter { $0 != pinned }.shuffled()
    }

    /// Download the next track ahead of time so skipping to it is gapless (no
    /// buffer gap, so the lock-screen controls don't flip to paused on skip).
    func prefetchNextTrack(after index: Int) {
        guard items.count > 1 else { return }
        let nextIndex = items.indices.contains(index + 1) ? index + 1 : 0
        guard nextIndex != index,
              let nextID = items[safe: nextIndex],
              let meta = mediaState?.metaOfMedia(withID: nextID),
              let url = meta.audioURL
        else { return }
        urlPlayer.prefetch(url: url)
    }

    func updateCommandProfile() {
        let profile = CommandProfile(
            // Enabled for a single-track queue too — forward/backward restart
            // the track (see forward()/backward()) instead of going dead.
            isSwitchTrackEnabled: !items.isEmpty
        )
        // Only reconfigure when the profile actually changed. Re-registering
        // every MPRemoteCommandCenter handler on each resume/track switch can
        // wedge the system now-playing session — the lock screen then keeps
        // showing metadata but stops honoring play-state/rate updates.
        guard profile != commandProfile else { return }
        systemMediaInterface.setRemoteCommandProfile(profile)
        commandProfile = profile
    }

    func updateMeta() {
        guard let mediaID = state.currentMediaID,
              let meta = mediaState?.metaOfMedia(withID: mediaID)
        else { return }
        nowPlayingMeta = meta

        // Resolve the cover once per track (the expensive part) instead of on
        // every push; refresh the now-playing info when it lands.
        if cachedArtworkID != mediaID {
            cachedArtworkID = mediaID
            cachedArtwork = nil
            pushedDurationForCurrentTrack = false
            Task { [weak self] in
                let image = await meta.artwork?.image
                guard let self, self.cachedArtworkID == mediaID else { return }
                self.cachedArtwork = image
                self.updateSystemNowPlaying()
            }
        }
        updateSystemNowPlaying()
    }

    /// Pushes the system now-playing info. Cheap and synchronous: it reuses the
    /// cached artwork and sets the real elapsed time + playback rate so the OS
    /// interpolates the scrubber between pushes. Call this only when something
    /// actually changes (track, play/pause, seek, speed) — NOT on every progress
    /// tick.
    func updateSystemNowPlaying() {
        guard let mediaID = state.currentMediaID,
              let mediaIndex = items.firstIndex(of: mediaID),
              let nowPlayingMeta
        else { return }

        // Always publish elapsed + duration so a track change resets the lock-screen
        // scrubber to 0 (a nil here would leave the OS interpolating from the previous
        // track). The real duration is re-pushed once known via `pushedDurationForCurrentTrack`.
        let prog = NowPlayingInfo.Progress(
            elapsedTime: urlPlayer.elapsedTime,
            duration: urlPlayer.duration
        )
        if urlPlayer.duration > 0 { pushedDurationForCurrentTrack = true }
        systemMediaInterface.setNowPlayingInfo(
            .init(
                meta: nowPlayingMeta,
                artwork: cachedArtwork ?? UIImage(),
                isPlaying: state.isPlaying,
                playbackRate: Double(audioEffects.speed),
                queue: .init(index: mediaIndex, count: items.count),
                progress: prog
            )
        )
    }
}

public extension MediaPlayerState {
    var currentMediaID: MediaID? {
        switch self {
        case let .paused(mediaID): mediaID
        case let .playing(mediaID): mediaID
        }
    }

    var isPlaying: Bool {
        if case .playing = self {
            return true
        }
        return false
    }
}

// MARK: - AudioSessionDelegate

extension MediaPlayer: AudioSessionDelegate {
    func audioSessionInterruptionBegan() {
        // Apple's guidance: by the time `.began` arrives the system has ALREADY
        // interrupted our session — do not deactivate it again; just bring our
        // own state in line. (We reactivate on resume.)
        guard case let .playing(mediaID) = state else { return }
        interruptedMediaID = mediaID
        interruptedElapsedTime = urlPlayer.elapsedTime
        pause()
    }

    func audioSessionInterruptionEnded(shouldResume: Bool) {
        audioSession.setActive(true)
        guard let mediaToResume = interruptedMediaID else { return }
        interruptedMediaID = nil
        guard shouldResume else { return }
        if state.currentMediaID == mediaToResume, urlPlayer.currentURL != nil {
            // The track is still loaded, paused right where the interruption
            // hit — continue in place. (Reloading via playItem restarted it
            // from 0:00 every time another app briefly took the audio.)
            resume()
        } else if let index = items.firstIndex(of: mediaToResume) {
            // The player genuinely lost the track — reload, then restore the
            // interrupted position once it's ready.
            pendingResumeSeek = (mediaToResume, interruptedElapsedTime)
            playItem(at: index)
        }
    }
}

// MARK: - SystemMediaInterfaceDelegate

extension MediaPlayer: SystemMediaInterfaceDelegate {
    func systemMediaInterface(_: SystemMediaInterface, didReceiveRemoteCommand command: RemoteCommand) {
        switch command {
        case .play:
            resume()
        case .stop, .pause:
            pause()
        case .togglePausePlay:
            togglePlayPause()
        case .nextTrack:
            forward()
        case .previousTrack:
            backward()
        case .changePlaybackPosition:
            break // handled via didReceiveSeekTo
        }
    }

    func systemMediaInterface(_: SystemMediaInterface, didReceiveSeekTo positionTime: TimeInterval) {
        seek(to: positionTime)
    }
}

// MARK: - URLAudioPlayerDelegate

extension MediaPlayer: URLAudioPlayerDelegate {
    func urlAudioPlayer(_: URLAudioPlayer, didUpdateProgress prog: PlaybackProgress) {
        // Only update the app's own progress here. The system now-playing info is
        // NOT re-pushed every tick — the OS interpolates the scrubber from the
        // elapsed time + rate we set on state changes. The one exception: push
        // once when a remote track's duration first becomes known.
        progress = prog
        // Restore the pre-interruption position after a forced reload, once the
        // track is actually ready (seeking before the file loads is a no-op).
        if let pending = pendingResumeSeek {
            if state.currentMediaID != pending.mediaID {
                pendingResumeSeek = nil // user moved on — stale
            } else if prog.duration > 0 {
                pendingResumeSeek = nil
                if pending.time > 1, pending.time < prog.duration - 1 {
                    seek(to: pending.time)
                }
            }
        }
        if !pushedDurationForCurrentTrack, prog.duration > 0 {
            updateSystemNowPlaying()
        }
    }

    func urlAudioPlayer(_: URLAudioPlayer, didSetupVideoPlayer player: AVPlayer?) {
        avPlayer = player
    }

    func urlAudioPlayer(_: URLAudioPlayer, didChangeBuffering isBuffering: Bool) {
        self.isBuffering = isBuffering
        // Re-assert the lock-screen snapshot once audio actually flows after a
        // switch: if any earlier push was dropped mid-flight (rapid skipping),
        // this self-heals the play state + elapsed instead of staying stuck.
        if !isBuffering {
            updateSystemNowPlaying()
        }
    }

    func urlAudioPlayerDidFinishPlaying(_: URLAudioPlayer) {
        // Repeat-one — or a single-track queue (e.g. a profile whose only post
        // is one video) — restarts from the top and keeps looping, matching how
        // longer queues wrap around at the end instead of stopping. `seek(to: 0)`
        // reloads the file, replays it and re-arms the finish handler. (playItem
        // no-ops when the target is already the current track, so it can't be
        // used to replay the same one.)
        if repeatEnabled || items.count == 1, state.currentMediaID != nil {
            seek(to: 0)
            return
        }
        if items.count > 1,
           let mediaID = state.currentMediaID,
           let index = items.firstIndex(of: mediaID)
        {
            let nextIndex = items.indices.contains(index + 1) ? index + 1 : 0
            playItem(at: nextIndex)
        } else {
            if let mediaID = state.currentMediaID {
                state = .paused(media: mediaID)
                urlPlayer.stop()
            }
        }
    }
}
