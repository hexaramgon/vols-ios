//
//  URLAudioPlayer.swift
//  Volspire
//

import AVFoundation
import Combine
import MediaLibrary

@MainActor
public final class URLAudioPlayer {
    public weak var delegate: URLAudioPlayerDelegate?
    public private(set) var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var statusObservation: NSKeyValueObservation?
    private var timeObserverToken: Any?
    private var spectrumUpdateTimer: Timer?
    private let tapProcessor = AudioTapProcessor()
    public let effectsProcessor = AudioEffectsProcessor()
    private var didPlayToEndTask: Task<Void, Never>?

    public private(set) var currentURL: URL?
    public private(set) var duration: TimeInterval = 0
    public private(set) var elapsedTime: TimeInterval = 0

    public init() {}

    public func applyEffects(_ effects: AudioEffects) {
        effectsProcessor.apply(effects, to: player)
    }

    public func play(url: URL) {
        if currentURL == url, player?.rate != 0 {
            return
        }
        stop()
        currentURL = url
        setupPlayer(url: url)
    }

    public func resume() {
        player?.play()
        // Re-apply speed if it was changed
        let rate = effectsProcessor.playbackRate
        if rate != 1.0 {
            player?.rate = rate
        }
        startSpectrumUpdates()
    }

    public func pause() {
        player?.pause()
        stopSpectrumUpdates()
        tapProcessor.reset()
        delegate?.urlAudioPlayer(
            self,
            didUpdateSpectrum: .init(repeating: 0, count: AudioSpectrumAnalyzer.defaultBandCount)
        )
        delegate?.urlAudioPlayer(
            self,
            didUpdateSmallSpectrum: .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
        )
    }

    public func stop() {
        cleanup()
    }

    public func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }
}

// MARK: - Private

private extension URLAudioPlayer {
    func setupPlayer(url: URL) {
        let asset = AVURLAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        playerItem?.audioTimePitchAlgorithm = .varispeed

        // Install audio processing tap for real-time FFT spectrum
        if let item = playerItem {
            tapProcessor.installTap(on: item)
        }

        player = AVPlayer(playerItem: playerItem)

        setupObservers()
        player?.play()

        // Apply current speed setting
        let rate = effectsProcessor.playbackRate
        if rate != 1.0 {
            player?.rate = rate
        }
    }

    func setupObservers() {
        statusObservation = playerItem?.observe(\.status, options: [.new, .initial]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                self?.handleStatusChange(item)
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player?.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedTime = time.seconds
                self.delegate?.urlAudioPlayer(
                    self,
                    didUpdateProgress: .init(
                        elapsedTime: self.elapsedTime,
                        duration: self.duration
                    )
                )
            }
        }

        observePlayToEnd()
    }

    func observePlayToEnd() {
        guard let playerItem else { return }
        didPlayToEndTask?.cancel()
        didPlayToEndTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                self?.delegate?.urlAudioPlayerDidFinishPlaying(self!)
            }
        }
    }

    func handleStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            Task {
                if let dur = try? await item.asset.load(.duration) {
                    duration = dur.seconds.isNaN ? 0 : dur.seconds
                }
            }
            startSpectrumUpdates()
        case .failed:
            if let error = item.error {
                print("URLAudioPlayer: Error - \(error.localizedDescription)")
            }
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    func startSpectrumUpdates() {
        spectrumUpdateTimer?.invalidate()
        spectrumUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSpectrum()
            }
        }
    }

    func stopSpectrumUpdates() {
        spectrumUpdateTimer?.invalidate()
        spectrumUpdateTimer = nil
    }

    func updateSpectrum() {
        let isPlaying = player?.rate != 0 && player?.error == nil
        if isPlaying {
            // Full hi-res spectrum for Now Playing visualizer
            let fullSpectrum = tapProcessor.spectrum
            delegate?.urlAudioPlayer(self, didUpdateSpectrum: fullSpectrum)

            // Downsample to small band count for list-row activity indicators
            let small = downsample(fullSpectrum, to: MediaPlayer.Const.frequencyBands)
            delegate?.urlAudioPlayer(self, didUpdateSmallSpectrum: small)
        } else {
            delegate?.urlAudioPlayer(
                self,
                didUpdateSpectrum: [Float](repeating: 0, count: AudioSpectrumAnalyzer.defaultBandCount)
            )
            delegate?.urlAudioPlayer(
                self,
                didUpdateSmallSpectrum: [Float](repeating: 0, count: MediaPlayer.Const.frequencyBands)
            )
        }
    }

    func downsample(_ spectrum: [Float], to bandCount: Int) -> [Float] {
        guard !spectrum.isEmpty, bandCount > 0 else {
            return [Float](repeating: 0, count: bandCount)
        }
        let chunkSize = spectrum.count / bandCount
        guard chunkSize > 0 else { return Array(spectrum.prefix(bandCount)) }
        var result = [Float](repeating: 0, count: bandCount)
        for i in 0 ..< bandCount {
            let start = i * chunkSize
            let end = min(start + chunkSize, spectrum.count)
            let slice = spectrum[start ..< end]
            result[i] = slice.reduce(0, +) / Float(slice.count)
        }
        return result
    }

    func cleanup() {
        player?.pause()

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        didPlayToEndTask?.cancel()
        didPlayToEndTask = nil
        stopSpectrumUpdates()
        statusObservation = nil
        player?.replaceCurrentItem(with: nil)
        playerItem = nil
        player = nil
        currentURL = nil
        duration = 0
        elapsedTime = 0
        tapProcessor.reset()

        delegate?.urlAudioPlayer(
            self,
            didUpdateSpectrum: .init(repeating: 0, count: AudioSpectrumAnalyzer.defaultBandCount)
        )
        delegate?.urlAudioPlayer(
            self,
            didUpdateSmallSpectrum: .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
        )
    }
}

// MARK: - Delegate

@MainActor
public protocol URLAudioPlayerDelegate: AnyObject {
    func urlAudioPlayer(_ player: URLAudioPlayer, didUpdateSpectrum spectrum: [Float])
    func urlAudioPlayer(_ player: URLAudioPlayer, didUpdateSmallSpectrum spectrum: [Float])
    func urlAudioPlayer(_ player: URLAudioPlayer, didUpdateProgress progress: PlaybackProgress)
    func urlAudioPlayerDidFinishPlaying(_ player: URLAudioPlayer)
}

public struct PlaybackProgress: Equatable, Sendable {
    public let elapsedTime: TimeInterval
    public let duration: TimeInterval
}
