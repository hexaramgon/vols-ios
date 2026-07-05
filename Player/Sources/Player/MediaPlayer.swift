//
//  MediaPlayer.swift
//  Volspire
//

import AVFoundation
import Combine
import MediaLibrary
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

    private var audioSession: AudioSession
    private var systemMediaInterface: SystemMediaInterface
    private var urlPlayer: URLAudioPlayer
    private var interruptedMediaID: MediaID?
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
        commandProfile = CommandProfile(isLiveStream: false, isSwitchTrackEnabled: false)
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
        guard let index = items.firstIndex(of: mediaID) else {
            print("MediaPlayer Error: there is no mediaID \(mediaID) in items.")
            return
        }
        self.items = items
        playItem(at: index)
    }

    public func forward() {
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

    public func backward() {
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
            isLiveStream: false,
            isSwitchTrackEnabled: items.count > 1
        )
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
        audioSession.setActive(false)
        guard case let .playing(mediaID) = state else { return }
        interruptedMediaID = mediaID
        pause()
    }

    func audioSessionInterruptionEnded(shouldResume: Bool) {
        audioSession.setActive(true)
        guard let mediaToResume = interruptedMediaID else { return }
        interruptedMediaID = nil
        if shouldResume, let index = items.firstIndex(of: mediaToResume) {
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
    public func urlAudioPlayer(_: URLAudioPlayer, didUpdateProgress prog: PlaybackProgress) {
        // Only update the app's own progress here. The system now-playing info is
        // NOT re-pushed every tick — the OS interpolates the scrubber from the
        // elapsed time + rate we set on state changes. The one exception: push
        // once when a remote track's duration first becomes known.
        progress = prog
        if !pushedDurationForCurrentTrack, prog.duration > 0 {
            updateSystemNowPlaying()
        }
    }

    public func urlAudioPlayer(_: URLAudioPlayer, didSetupVideoPlayer player: AVPlayer?) {
        avPlayer = player
    }

    public func urlAudioPlayer(_: URLAudioPlayer, didChangeBuffering isBuffering: Bool) {
        self.isBuffering = isBuffering
    }

    public func urlAudioPlayerDidFinishPlaying(_: URLAudioPlayer) {
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
