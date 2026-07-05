//
//  URLAudioPlayer.swift
//  Volspire
//
//  Dual-mode player:
//  • Audio files: AudioKit (AudioEngine → VariSpeed → TimePitch → Mixer).
//  • Video files: Muted AVPlayer for video display + AudioKit for audio output.
//    This lets AudioKit effects (speed, pitch) apply to video audio too.
//    AVPlayer and AudioKit are kept in sync on play/pause/seek.
//

import AudioKit
import AVFoundation
import Combine
import MediaLibrary
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class URLAudioPlayer {
    public weak var delegate: URLAudioPlayerDelegate?

    // MARK: - AudioKit nodes (used for ALL playback audio)

    nonisolated(unsafe) private let engine = AudioEngine()
    nonisolated(unsafe) private let akPlayer = AudioPlayer()
    nonisolated(unsafe) private let variSpeed: VariSpeed
    nonisolated(unsafe) private let timePitch: TimePitch
    nonisolated(unsafe) private let mixer: Mixer

    // MARK: - AVPlayer (video display only — muted)

    private var videoPlayer: AVPlayer?
    private var videoPlayerItem: AVPlayerItem?
    private var videoStatusObservation: NSKeyValueObservation?

    // MARK: - Timers / tasks

    private var progressTimer: Timer?
    private var downloadTask: URLSessionDownloadTask?

    // Next-track prefetch: download the upcoming track to a local file while the
    // current one plays, so a skip has no download gap (and the lock screen never
    // shows "paused" mid-buffer). Spotify-style read-ahead.
    private var prefetchedFiles: [URL: URL] = [:]
    private var prefetchTasks: [URL: URLSessionDownloadTask] = [:]

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

    /// The intended playback state once the current URL finishes loading. Lets a
    /// pause issued mid-load actually stick instead of auto-playing when it loads.
    private var shouldPlayWhenReady = true
    /// True while the current URL is downloading/decoding and no audio is playing
    /// yet — the UI shows a loading state instead of an ambiguous play/pause.
    public private(set) var isBuffering = false

    private func setBuffering(_ value: Bool) {
        guard isBuffering != value else { return }
        isBuffering = value
        delegate?.urlAudioPlayer(self, didChangeBuffering: value)
    }

    /// Set for video files so the UI can display the video layer.
    public private(set) var avPlayer: AVPlayer?

    /// Token for the foreground observer (removed on deinit).
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?

    // MARK: - Init

    public init() {
        // Graph: AudioPlayer → VariSpeed (resampling) → TimePitch (phase vocoder) → Mixer.
        // VariSpeed handles varispeed (pitch follows speed) cleanly; TimePitch handles
        // tempo-only changes when "preserve pitch" is on. Only one is active at a time.
        let vs = VariSpeed(akPlayer)
        let tp = TimePitch(vs)
        let mx = Mixer(tp)
        variSpeed = vs
        timePitch = tp
        mixer = mx
        engine.output = mx

        #if canImport(UIKit)
        // Returning from the background: the muted video AVPlayer's rendering was
        // suspended while AudioKit kept the audio going, so they've drifted. Snap the
        // video back to the audio playhead so it isn't stuttery / out of sync.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.resyncVideoToAudio() }
        }
        #endif
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Public Interface

    public func applyEffects(_ effects: AudioEffects) {
        effectsProcessor.apply(effects, variSpeed: variSpeed, timePitch: timePitch)
        // If video mode, also sync AVPlayer rate to match speed
        if isVideoMode {
            syncVideoRate()
        }
    }

    public func play(url: URL) {
        if currentURL == url, akPlayer.isPlaying { return }
        // Keep the engine running across the switch so the audio session never goes
        // idle while the next track downloads — otherwise iOS shows the lock-screen
        // controls as paused during the buffer.
        cleanup(stopEngine: false)
        currentURL = url
        shouldPlayWhenReady = true
        setBuffering(true)
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

    /// Download an upcoming track to a local file ahead of time so playing it
    /// later is gapless (no download gap, no lock-screen pause on skip). No-op for
    /// local files, videos, or URLs already prefetched / in flight.
    public func prefetch(url: URL) {
        guard !url.isFileURL,
              !Self.videoExtensions.contains(url.pathExtension.lowercased()),
              prefetchedFiles[url] == nil,
              prefetchTasks[url] == nil
        else { return }

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmpURL, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.prefetchTasks[url] = nil
                guard error == nil, let tmpURL else { return }
                let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("prefetch-\(UUID().uuidString)")
                    .appendingPathExtension(ext)
                do {
                    try FileManager.default.moveItem(at: tmpURL, to: dest)
                    self.prefetchedFiles[url] = dest
                } catch {
                    print("URLAudioPlayer: Prefetch move failed – \(error)")
                }
            }
        }
        prefetchTasks[url] = task
        task.resume()
    }

    public func resume() {
        shouldPlayWhenReady = true
        // Still loading — playback will start automatically once it's ready.
        guard !isBuffering else { return }
        resumeAudio()
        if isVideoMode {
            syncVideoPlayback()
        }
    }

    public func pause() {
        shouldPlayWhenReady = false
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

    /// Snap the muted video player back to the audio (AudioKit) playhead — used when
    /// returning from the background, where the video renderer was suspended while
    /// the audio kept advancing.
    func resyncVideoToAudio() {
        guard isVideoMode, let vp = videoPlayer else { return }
        let cmTime = CMTime(seconds: akPlayer.currentTime, preferredTimescale: 600)
        vp.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if akPlayer.isPlaying {
            vp.play()
            syncVideoRate()
        } else {
            vp.pause()
        }
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
        // Prefetched while the previous track played → play the local copy now,
        // skipping the download entirely (gapless skip).
        if !isVideoMode, let local = prefetchedFiles.removeValue(forKey: remoteURL) {
            tempFileURL = local // owned now, cleaned up with the rest
            loadAndPlayAudio(fileURL: local)
            return
        }
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

        // Loaded — no longer buffering.
        setBuffering(false)

        // If the user paused while this was loading, stay paused (the file is
        // loaded, so a later resume plays it from the start). Otherwise play.
        guard shouldPlayWhenReady else { return }

        installCompletionHandler()

        effectsProcessor.reapply(variSpeed: variSpeed, timePitch: timePitch)
        akPlayer.play()

        // Start the muted video player in sync
        if isVideoMode {
            syncVideoPlayback()
        }

        startProgressUpdates()
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
        effectsProcessor.reapply(variSpeed: variSpeed, timePitch: timePitch)

        startProgressUpdates()
    }

    func pauseAudio() {
        pausedAtTime = akPlayer.currentTime
        akPlayer.completionHandler = nil
        akPlayer.stop()

        stopProgressUpdates()
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
        effectsProcessor.reapply(variSpeed: variSpeed, timePitch: timePitch)
    }

    /// `stopEngine: false` keeps the audio engine running — used when switching
    /// tracks so the audio session never goes idle during the download gap (which
    /// makes iOS show the lock-screen controls as paused, Spotify-style buffering).
    func cleanupAudio(stopEngine: Bool = true) {
        stopProgressUpdates()

        akPlayer.completionHandler = nil
        akPlayer.stop()
        if stopEngine { engine.stop() }
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
}

// MARK: - Private – Progress

private extension URLAudioPlayer {
    func startProgressUpdates() {
        progressTimer?.invalidate()
        // Emit once immediately so the (already-known) duration lands right away —
        // the timer's first tick is 0.5s out, which made the duration appear late.
        emitProgress()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.emitProgress() }
        }
    }

    private func emitProgress() {
        elapsedTime = akPlayer.currentTime
        delegate?.urlAudioPlayer(
            self,
            didUpdateProgress: .init(elapsedTime: elapsedTime, duration: duration)
        )
    }

    func stopProgressUpdates() {
        progressTimer?.invalidate()
        progressTimer = nil
    }
}

// MARK: - Private – Helpers

private extension URLAudioPlayer {
    func cleanup(stopEngine: Bool = true) {
        downloadTask?.cancel()
        downloadTask = nil
        // A skip (stopEngine == false) keeps the read-ahead; a full stop drops it.
        if stopEngine {
            prefetchTasks.values.forEach { $0.cancel() }
            prefetchTasks.removeAll()
            for file in prefetchedFiles.values { try? FileManager.default.removeItem(at: file) }
            prefetchedFiles.removeAll()
        }
        setBuffering(false)
        shouldPlayWhenReady = true

        cleanupAudio(stopEngine: stopEngine)
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
    }
}

// MARK: - Delegate

@MainActor
public protocol URLAudioPlayerDelegate: AnyObject {
    func urlAudioPlayer(_ player: URLAudioPlayer, didUpdateProgress progress: PlaybackProgress)
    func urlAudioPlayer(_ player: URLAudioPlayer, didSetupVideoPlayer avPlayer: AVPlayer?)
    func urlAudioPlayer(_ player: URLAudioPlayer, didChangeBuffering isBuffering: Bool)
    func urlAudioPlayerDidFinishPlaying(_ player: URLAudioPlayer)
}

public struct PlaybackProgress: Equatable, Sendable {
    public let elapsedTime: TimeInterval
    public let duration: TimeInterval

    public init(elapsedTime: TimeInterval, duration: TimeInterval) {
        self.elapsedTime = elapsedTime
        self.duration = duration
    }
}
