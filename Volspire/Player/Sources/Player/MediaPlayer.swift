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
    public enum Const {
        public static let frequencyBands = 5
    }

    public weak var mediaState: MediaState?
    private(set) var items: [MediaID] = []

    @Published public private(set) var progress: PlaybackProgress?
    @Published public private(set) var state: MediaPlayerState
    @Published public private(set) var commandProfile: CommandProfile?
    @Published public private(set) var playIndicatorSpectrum: [Float]
    @Published public private(set) var visualizerSpectrum: [Float]
    @Published public private(set) var nowPlayingMeta: MediaMeta?
    @Published public private(set) var avPlayer: AVPlayer?
    @Published public var audioEffects: AudioEffects = .default

    private var audioSession: AudioSession
    private var systemMediaInterface: SystemMediaInterface
    private var urlPlayer: URLAudioPlayer
    private var interruptedMediaID: MediaID?

    public init() {
        audioSession = AudioSession()
        systemMediaInterface = SystemMediaInterface()
        urlPlayer = URLAudioPlayer()
        state = .paused(media: .none)
        commandProfile = CommandProfile(isLiveStream: false, isSwitchTrackEnabled: false)
        playIndicatorSpectrum = .init(repeating: 0, count: Const.frequencyBands)
        visualizerSpectrum = .init(repeating: 0, count: AudioSpectrumAnalyzer.defaultBandCount)
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
    }

    public func backward() {
        // If more than 3 seconds in, restart the current track
        if urlPlayer.elapsedTime > 3 {
            urlPlayer.seek(to: 0)
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

        urlPlayer.stop()
        audioSession.setActive(true)

        if let meta = mediaState?.metaOfMedia(withID: mediaID),
           let audioURL = meta.audioURL
        {
            urlPlayer.play(url: audioURL)
            avPlayer = urlPlayer.player
        } else {
            print("MediaPlayer: No audio URL found for \(mediaID)")
            avPlayer = nil
        }

        state = .playing(media: mediaID)
        updateMeta()
        updateCommandProfile()
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
        updateSystemNowPlaying()
    }

    func updateSystemNowPlaying() {
        guard let mediaID = state.currentMediaID,
              let mediaIndex = items.firstIndex(of: mediaID),
              let nowPlayingMeta
        else { return }
        Task {
            let artwork = await nowPlayingMeta.artwork?.image ?? UIImage()
            let prog: NowPlayingInfo.Progress? = progress.map {
                .init(elapsedTime: $0.elapsedTime, duration: $0.duration)
            }
            systemMediaInterface.setNowPlayingInfo(
                .init(
                    meta: nowPlayingMeta,
                    artwork: artwork,
                    isPlaying: state.isPlaying,
                    queue: .init(index: mediaIndex, count: items.count),
                    progress: prog
                )
            )
        }
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
    public func urlAudioPlayer(_: URLAudioPlayer, didUpdateSpectrum spectrum: [Float]) {
        visualizerSpectrum = spectrum
    }

    public func urlAudioPlayer(_: URLAudioPlayer, didUpdateSmallSpectrum spectrum: [Float]) {
        playIndicatorSpectrum = spectrum
    }

    public func urlAudioPlayer(_: URLAudioPlayer, didUpdateProgress prog: PlaybackProgress) {
        progress = prog
        updateSystemNowPlaying()
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
