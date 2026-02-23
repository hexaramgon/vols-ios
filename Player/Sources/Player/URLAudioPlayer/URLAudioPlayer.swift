//
//  URLAudioPlayer.swift
//  Volspire
//
//  Dual-mode player:
//  • Audio files: AudioKit (AudioEngine → TimePitch → Mixer) with RawDataTap.
//  • Video files: Muted AVPlayer for video display + AudioKit for audio output.
//    This lets AudioKit effects (speed, pitch) apply to video audio too.
//    AVPlayer and AudioKit are kept in sync on play/pause/seek.
//

import AudioKit
import AVFoundation
import Combine
import MediaLibrary

@MainActor
public final class URLAudioPlayer {
    public weak var delegate: URLAudioPlayerDelegate?

    // MARK: - AudioKit nodes (used for ALL playback audio)

    nonisolated(unsafe) private let engine = AudioEngine()
    nonisolated(unsafe) private let akPlayer = AudioPlayer()
    nonisolated(unsafe) private let timePitch: TimePitch
    nonisolated(unsafe) private let mixer: Mixer
    nonisolated(unsafe) private var rawDataTap: RawDataTap?

    // MARK: - AVPlayer (video display only — muted)

    private var videoPlayer: AVPlayer?
    private var videoPlayerItem: AVPlayerItem?
    private var videoStatusObservation: NSKeyValueObservation?

    // MARK: - Analysis

    private let analyzer = AudioSpectrumAnalyzer()

    // MARK: - Timers / tasks

    private var progressTimer: Timer?
    private var spectrumUpdateTimer: Timer?
    private var downloadTask: URLSessionDownloadTask?

    // MARK: - State

    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "webm"]

    public let effectsProcessor = AudioEffectsProcessor()
    private var tempFileURL: URL?
    private var extractedAudioURL: URL?
    private var loadedFileURL: URL?
    private var pausedAtTime: TimeInterval?
    private var isVideoMode = false
    public private(set) var currentURL: URL?
    public private(set) var duration: TimeInterval = 0
    public private(set) var elapsedTime: TimeInterval = 0

    /// Set for video files so the UI can display the video layer.
    public private(set) var avPlayer: AVPlayer?

    // MARK: - Init

    public init() {
        let tp = TimePitch(akPlayer)
        let mx = Mixer(tp)
        timePitch = tp
        mixer = mx
        engine.output = mx
    }

    // MARK: - Public Interface

    public func applyEffects(_ effects: AudioEffects) {
        effectsProcessor.apply(effects, to: timePitch)
        // If video mode, also sync AVPlayer rate to match speed
        if isVideoMode {
            syncVideoRate()
        }
    }

    public func play(url: URL) {
        if currentURL == url, akPlayer.isPlaying { return }
        stop()
        currentURL = url
        isVideoMode = Self.videoExtensions.contains(url.pathExtension.lowercased())

        if url.isFileURL {
            if isVideoMode {
                setupVideoDisplay(fileURL: url)
                Task {
                    do {
                        let audioURL = try await self.extractAudioTrack(from: url)
                        guard self.currentURL == url else { return }
                        self.extractedAudioURL = audioURL
                        self.loadAndPlayAudio(fileURL: audioURL)
                    } catch {
                        print("URLAudioPlayer: Audio extraction failed – \(error)")
                    }
                }
            } else {
                loadAndPlayAudio(fileURL: url)
            }
        } else {
            downloadAndPlay(remoteURL: url)
        }
    }

    public func resume() {
        resumeAudio()
        if isVideoMode {
            syncVideoPlayback()
        }
    }

    public func pause() {
        pauseAudio()
        if isVideoMode {
            videoPlayer?.pause()
        }
    }

    public func stop() {
        cleanup()
    }

    public func seek(to time: TimeInterval) {
        seekAudio(to: time)
        if isVideoMode {
            let cmTime = CMTime(seconds: time, preferredTimescale: 600)
            videoPlayer?.seek(to: cmTime)
            syncVideoPlayback()
        }
    }
}

// MARK: - Video Display (muted AVPlayer for video layer only)

private extension URLAudioPlayer {
    /// Create a muted AVPlayer so the UI can show the video layer.
    func setupVideoDisplay(fileURL: URL) {
        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        videoPlayerItem = item

        let vp = AVPlayer(playerItem: item)
        vp.isMuted = true  // Audio comes from AudioKit
        videoPlayer = vp
        avPlayer = vp
        delegate?.urlAudioPlayer(self, didSetupVideoPlayer: vp)
    }

    /// Keep the muted video player in sync with AudioKit playback.
    func syncVideoPlayback() {
        guard let vp = videoPlayer else { return }
        let akTime = akPlayer.currentTime
        let cmTime = CMTime(seconds: akTime, preferredTimescale: 600)
        vp.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        vp.play()
        syncVideoRate()
    }

    /// Match video playback rate to current effects speed.
    func syncVideoRate() {
        guard let vp = videoPlayer, vp.rate != 0 else { return }
        vp.rate = effectsProcessor.playbackRate
    }

    func cleanupVideo() {
        videoPlayer?.pause()
        videoStatusObservation = nil
        videoPlayer?.replaceCurrentItem(with: nil)
        videoPlayerItem = nil
        videoPlayer = nil
        avPlayer = nil
        delegate?.urlAudioPlayer(self, didSetupVideoPlayer: nil)
    }

    /// Extract the audio track from a video container into a temp .m4a
    /// that AudioKit's AudioPlayer (AVAudioFile) can open.
    func extractAudioTrack(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let session = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw NSError(
                domain: "URLAudioPlayer",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create export session"]
            )
        }

        session.outputURL = outputURL
        session.outputFileType = .m4a

        await session.export()

        guard session.status == .completed else {
            throw session.error ?? NSError(
                domain: "URLAudioPlayer",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Audio extraction failed"]
            )
        }

        return outputURL
    }
}

// MARK: - Audio Playback (AudioKit)

private extension URLAudioPlayer {
    func downloadAndPlay(remoteURL: URL) {
        downloadTask?.cancel()
        let task = URLSession.shared.downloadTask(with: remoteURL) { [weak self] tmpURL, _, error in
            Task { @MainActor [weak self] in
                guard let self, self.currentURL == remoteURL else { return }
                if let error {
                    print("URLAudioPlayer: Download failed – \(error.localizedDescription)")
                    return
                }
                guard let tmpURL else { return }

                let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                do {
                    try FileManager.default.moveItem(at: tmpURL, to: dest)
                    self.tempFileURL = dest

                    if self.isVideoMode {
                        self.setupVideoDisplay(fileURL: dest)
                        do {
                            let audioURL = try await self.extractAudioTrack(from: dest)
                            guard self.currentURL == remoteURL else { return }
                            self.extractedAudioURL = audioURL
                            self.loadAndPlayAudio(fileURL: audioURL)
                        } catch {
                            print("URLAudioPlayer: Audio extraction failed – \(error)")
                        }
                    } else {
                        self.loadAndPlayAudio(fileURL: dest)
                    }
                } catch {
                    print("URLAudioPlayer: Failed to move temp file – \(error)")
                }
            }
        }
        task.resume()
        downloadTask = task
    }

    func loadAndPlayAudio(fileURL: URL) {
        do {
            try akPlayer.load(url: fileURL)
        } catch {
            print("URLAudioPlayer: Failed to load – \(error.localizedDescription)")
            return
        }

        loadedFileURL = fileURL
        pausedAtTime = nil
        duration = akPlayer.duration

        do {
            if !engine.avEngine.isRunning {
                try engine.start()
            }
        } catch {
            print("URLAudioPlayer: Engine start failed – \(error)")
            return
        }

        installSpectrumTap()
        installCompletionHandler()

        effectsProcessor.reapply(to: timePitch)
        akPlayer.play()

        // Start the muted video player in sync
        if isVideoMode {
            syncVideoPlayback()
        }

        startProgressUpdates()
        startSpectrumUpdates()
    }

    func resumeAudio() {
        guard !akPlayer.isPlaying else { return }
        do {
            if !engine.avEngine.isRunning {
                try engine.start()
            }
        } catch {
            print("URLAudioPlayer: Engine start failed – \(error)")
        }

        if let savedTime = pausedAtTime, let fileURL = loadedFileURL {
            akPlayer.completionHandler = nil
            do {
                try akPlayer.load(url: fileURL)
                akPlayer.play()
                akPlayer.seek(time: savedTime)
                installCompletionHandler()
            } catch {
                print("URLAudioPlayer: Failed to reload on resume – \(error)")
                akPlayer.play()
                installCompletionHandler()
            }
        } else {
            akPlayer.play()
        }

        pausedAtTime = nil
        effectsProcessor.reapply(to: timePitch)

        if rawDataTap == nil {
            installSpectrumTap()
        }

        startProgressUpdates()
        startSpectrumUpdates()
    }

    func pauseAudio() {
        pausedAtTime = akPlayer.currentTime
        akPlayer.completionHandler = nil
        akPlayer.stop()

        stopProgressUpdates()
        spectrumUpdateTimer?.invalidate()
        spectrumUpdateTimer = nil
    }

    func seekAudio(to time: TimeInterval) {
        guard let fileURL = loadedFileURL else { return }
        akPlayer.completionHandler = nil
        do {
            try akPlayer.load(url: fileURL)
            akPlayer.play()
            akPlayer.seek(time: time)
            installCompletionHandler()
            elapsedTime = time
        } catch {
            print("URLAudioPlayer: Seek failed – \(error)")
        }
        effectsProcessor.reapply(to: timePitch)
    }

    func cleanupAudio() {
        spectrumUpdateTimer?.invalidate()
        spectrumUpdateTimer = nil
        rawDataTap?.stop()
        rawDataTap = nil

        stopProgressUpdates()
        analyzer.reset()

        akPlayer.completionHandler = nil
        akPlayer.stop()
        engine.stop()
    }
}

// MARK: - Private – Spectrum & Completion

private extension URLAudioPlayer {
    func installCompletionHandler() {
        akPlayer.completionHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.urlAudioPlayerDidFinishPlaying(self)
            }
        }
    }

    func installSpectrumTap() {
        rawDataTap?.stop()
        rawDataTap = RawDataTap(mixer, bufferSize: 2048)
        rawDataTap?.start()
    }

    func startSpectrumUpdates() {
        spectrumUpdateTimer?.invalidate()
        spectrumUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollSpectrum()
            }
        }
    }

    func stopSpectrumUpdates() {
        spectrumUpdateTimer?.invalidate()
        spectrumUpdateTimer = nil
    }

    func pollSpectrum() {
        guard let tap = rawDataTap else { return }
        let rawData = tap.data
        guard !rawData.isEmpty else { return }

        let fullSpectrum = analyzer.analyzeRaw(samples: rawData, channelCount: 1)
        delegate?.urlAudioPlayer(self, didUpdateSpectrum: fullSpectrum)

        let small = downsample(fullSpectrum, to: MediaPlayer.Const.frequencyBands)
        delegate?.urlAudioPlayer(self, didUpdateSmallSpectrum: small)
    }
}

// MARK: - Private – Progress

private extension URLAudioPlayer {
    func startProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.elapsedTime = self.akPlayer.currentTime
                self.delegate?.urlAudioPlayer(
                    self,
                    didUpdateProgress: .init(
                        elapsedTime: self.elapsedTime,
                        duration: self.duration
                    )
                )
            }
        }
    }

    func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - Private – Helpers

private extension URLAudioPlayer {
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
        downloadTask?.cancel()
        downloadTask = nil

        cleanupAudio()
        if isVideoMode {
            cleanupVideo()
        }

        // Clean up temp files
        if let tempFileURL {
            try? FileManager.default.removeItem(at: tempFileURL)
            self.tempFileURL = nil
        }
        if let extractedAudioURL {
            try? FileManager.default.removeItem(at: extractedAudioURL)
            self.extractedAudioURL = nil
        }

        avPlayer = nil
        currentURL = nil
        loadedFileURL = nil
        pausedAtTime = nil
        isVideoMode = false
        duration = 0
        elapsedTime = 0

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
    func urlAudioPlayer(_ player: URLAudioPlayer, didSetupVideoPlayer avPlayer: AVPlayer?)
    func urlAudioPlayerDidFinishPlaying(_ player: URLAudioPlayer)
}

public struct PlaybackProgress: Equatable, Sendable {
    public let elapsedTime: TimeInterval
    public let duration: TimeInterval
}
