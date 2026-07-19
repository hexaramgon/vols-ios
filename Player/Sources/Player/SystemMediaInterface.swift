//
//  SystemMediaInterface.swift
//  Volspire
//
//

import MediaPlayer

@MainActor
protocol SystemMediaInterfaceDelegate: AnyObject {
    func systemMediaInterface(_ interface: SystemMediaInterface, didReceiveRemoteCommand command: RemoteCommand)
    func systemMediaInterface(_ interface: SystemMediaInterface, didReceiveSeekTo positionTime: TimeInterval)
}

@MainActor
class SystemMediaInterface {
    weak var delegate: SystemMediaInterfaceDelegate?
    /// MPRemoteCommandCenter targets are added exactly once (see `registerHandlers`).
    private var handlersRegistered = false

    func setRemoteCommandProfile(_ profile: CommandProfile) {
        // Register the command HANDLERS exactly once. Re-adding targets on a later
        // profile change (notably the FIRST play, when switch-track flips false→true)
        // WEDGES the system now-playing session — the lock screen then keeps showing
        // metadata but IGNORES play-state/rate and REJECTS setPlaybackState. That wedge
        // is why pausing never updated the lock-screen button and iOS bounced back a
        // spurious `.play`. On profile changes we ONLY flip next/previous enabled —
        // never remove/re-add targets.
        if !handlersRegistered {
            registerHandlers()
            handlersRegistered = true
        }
        let switchEnabled = profile.isSwitchTrackEnabled
        RemoteCommand.nextTrack.setDisabled(!switchEnabled)
        RemoteCommand.previousTrack.setDisabled(!switchEnabled)
    }

    func setNowPlayingInfo(_ info: NowPlayingInfo) {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info.mpNowPlayingInfo
        // With handlers registered only once (session no longer wedged), the explicit
        // playback state is honored again — it drives the lock-screen play/pause BUTTON
        // (the scrubber follows the dict's PlaybackRate). Set both so they agree.
        center.playbackState = info.isPlaying ? .playing : .paused
    }

    /// Removes the lock-screen now-playing entry entirely (sign-out teardown).
    func clearNowPlayingInfo() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }
}

private extension SystemMediaInterface {
    /// Adds all command targets ONCE. Enabled/disabled state (next/previous) is toggled
    /// separately in `setRemoteCommandProfile`, so targets are never removed/re-added
    /// mid-session — the thing that wedges the system now-playing session.
    func registerHandlers() {
        let enabled: [RemoteCommand] = [
            .play, .pause, .stop, .togglePausePlay, .nextTrack, .previousTrack, .changePlaybackPosition
        ]
        for command in RemoteCommand.allCases {
            command.removeHandler()
            guard enabled.contains(command) else {
                command.setDisabled(true)
                continue
            }
            command.addHandler { [weak self] remoteCommand, event in
                guard let self else { return .commandFailed }
                if remoteCommand == .changePlaybackPosition,
                   let positionEvent = event as? MPChangePlaybackPositionCommandEvent
                {
                    delegate?.systemMediaInterface(self, didReceiveSeekTo: positionEvent.positionTime)
                } else {
                    delegate?.systemMediaInterface(self, didReceiveRemoteCommand: remoteCommand)
                }
                return .success
            }
            command.setDisabled(false)
        }
    }
}

extension RemoteCommand {
    var mpRemoteCommand: MPRemoteCommand {
        let commandCenter = MPRemoteCommandCenter.shared()
        switch self {
        case .pause:
            return commandCenter.pauseCommand
        case .play:
            return commandCenter.playCommand
        case .stop:
            return commandCenter.stopCommand
        case .togglePausePlay:
            return commandCenter.togglePlayPauseCommand
        case .nextTrack:
            return commandCenter.nextTrackCommand
        case .previousTrack:
            return commandCenter.previousTrackCommand
        case .changePlaybackPosition:
            return commandCenter.changePlaybackPositionCommand
        }
    }

    func removeHandler() {
        mpRemoteCommand.removeTarget(nil)
    }

    func addHandler(_ handler: @escaping (RemoteCommand, MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        mpRemoteCommand.addTarget { handler(self, $0) }
    }

    func setDisabled(_ isDisabled: Bool) {
        mpRemoteCommand.isEnabled = !isDisabled
    }
}

extension NowPlayingInfo {
    var mpNowPlayingInfo: [String: Any] {
        var info = [String: Any]()
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        info[MPMediaItemPropertyTitle] = meta.title
        info[MPMediaItemPropertyArtist] = meta.artist
        // Never publish a zero-sized artwork (the pre-cover placeholder) —
        // iOS can silently discard the whole info dictionary for it, dropping
        // the play-state update that came with it.
        if artwork.size.width > 0, artwork.size.height > 0 {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
        }
        if let queue {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queue.index
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queue.count
        }
        if let progress {
            info[MPMediaItemPropertyPlaybackDuration] = progress.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = progress.elapsedTime
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? playbackRate : 0.0
        return info
    }
}
