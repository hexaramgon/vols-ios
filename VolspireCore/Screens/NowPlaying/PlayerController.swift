//
//  PlayerController.swift
//  Volspire
//

import Combine
import DesignSystem
import AVFoundation
import MediaLibrary
import Player
import SwiftUI
import UIKit

@Observable @MainActor
final class PlayerController {
    struct Display: Hashable {
        let artwork: Artwork
        let title: String
        let subtitle: String
    }

    var display: Display = .placeholder

    var state: MediaPlayerState = .paused(media: .none)
    var commandProfile: CommandProfile = .init(isLiveStream: false, isSwitchTrackEnabled: false)
    var colors: [UIColor] = []
    var progress: PlaybackProgress?
    var isScrubbing: Bool = false
    var nowPlayingMeta: MediaMeta?
    var visualizerSpectrum: [Float] = []
    var audioEffects: AudioEffects = .default
    var showingEffectsSheet: Bool = false

    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    weak var mediaState: MediaState?

    private var cancellables = Set<AnyCancellable>()

    var isLiveStream: Bool {
        commandProfile.isLiveStream
    }

    var playPauseButton: ButtonType {
        switch state {
        case .playing: .pause
        case .paused: .play
        }
    }

    var backwardButton: ButtonType { .backward }
    var forwardButton: ButtonType { .forward }

    func onPlayPause() {
        player?.togglePlayPause()
    }

    func onForward() {
        player?.forward()
    }

    func onBackward() {
        player?.backward()
    }

    func seek(to time: TimeInterval) {
        player?.seek(to: time)
    }

    func applyEffects(_ effects: AudioEffects) {
        audioEffects = effects
        player?.applyEffects(effects)
    }
}

private extension PlayerController {
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "webm"]

    private func observeMediaPlayerState() {
        guard let player else { return }
        cancellables.removeAll()
        player.$state
            .sink { [weak self] state in
                self?.state = state
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

        player.$visualizerSpectrum
            .sink { [weak self] spectrum in
                self?.visualizerSpectrum = spectrum
            }
            .store(in: &cancellables)
    }

    func updateDisplay(withMeta meta: MediaMeta?, avPlayer: AVPlayer?) async {
        nowPlayingMeta = meta
        if let meta {
            let isVideo = meta.audioURL.map {
                Self.videoExtensions.contains($0.pathExtension.lowercased())
            } ?? false

            let artwork: Artwork
            if isVideo, let avPlayer {
                artwork = .videoPlayer(avPlayer)
            } else {
                artwork = .radio(meta.artwork, name: meta.title)
            }

            display = .init(
                artwork: artwork,
                title: meta.title,
                subtitle: meta.description ?? ""
            )
            colors = await meta.colors.map { UIColor($0) }
        } else {
            display = .placeholder
            nowPlayingMeta = nil
            colors = [UIColor(.graySecondary)]
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
            artwork: .radio(),
            title: "",
            subtitle: ""
        )
    }
}
