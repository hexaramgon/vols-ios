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

    func setRemoteCommandProfile(_ profile: CommandProfile) {
        let commands: [RemoteCommand] = [
            .play, .pause, .stop, .togglePausePlay, .nextTrack, .previousTrack, .changePlaybackPosition
        ]
        configureRemoteCommands(
            commands,
            disabledCommands: profile.isSwitchTrackEnabled ? [] : [.nextTrack, .previousTrack]
        )
    }

    func setNowPlayingInfo(_ info: NowPlayingInfo) {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info.mpNowPlayingInfo
        // Drive the lock-screen play/pause icon from our intent, not the actual
        // audio output. While a freshly-skipped track is still loading there's no
        // audio yet, and iOS would otherwise flicker the icon to "paused" until
        // playback starts — set the state explicitly so it stays "playing".
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
    func configureRemoteCommands(_ commands: [RemoteCommand], disabledCommands: [RemoteCommand]) {
        for command in RemoteCommand.allCases {
            command.removeHandler()
            if commands.contains(command) {
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
            }
            command.setDisabled(disabledCommands.contains(command))
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
