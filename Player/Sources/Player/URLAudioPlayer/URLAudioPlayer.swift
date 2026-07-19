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
final class URLAudioPlayer {
    weak var delegate: URLAudioPlayerDelegate?

    // MARK: - AudioKit nodes (used for ALL playback audio)

    nonisolated(unsafe) private let engine = AudioEngine()
    nonisolated(unsafe) private let akPlayer = AudioPlayer()
    nonisolated(unsafe) private let variSpeed: VariSpeed
    nonisolated(unsafe) private let timePitch: TimePitch
    nonisolated(unsafe) private let mixer: Mixer

    /// Post-effects output node for audio-reactive visuals (the visualizer's
    /// tap installs here). The mixer is created once and never replaced, so a
    /// tap survives engine stop/start cycles.
    var visualizerAudioNode: AVAudioNode { mixer.avAudioNode }

    // MARK: - AVPlayer (video display only — muted)

    private var videoPlayer: AVPlayer?
    private var videoPlayerItem: AVPlayerItem?

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

    let effectsProcessor = AudioEffectsProcessor()
    private var tempFileURL: URL?
    private var extractedAudioURL: URL?
    private var loadedFileURL: URL?
    private var pausedAtTime: TimeInterval?
    private var isVideoMode = false
    private(set) var currentURL: URL?
    private(set) var duration: TimeInterval = 0
    private(set) var elapsedTime: TimeInterval = 0

    /// The intended playback state once the current URL finishes loading. Lets a
    /// pause issued mid-load actually stick instead of auto-playing when it loads.
    private var shouldPlayWhenReady = true
    /// True while the current URL is downloading/decoding and no audio is playing
    /// yet — the UI shows a loading state instead of an ambiguous play/pause.
    private(set) var isBuffering = false

    private func setBuffering(_ value: Bool) {
        guard isBuffering != value else { return }
        isBuffering = value
        delegate?.urlAudioPlayer(self, didChangeBuffering: value)
    }

    /// Tokens for the foreground/background observers (removed on deinit).
    nonisolated(unsafe) private var foregroundObserver: NSObjectProtocol?
    nonisolated(unsafe) private var backgroundObserver: NSObjectProtocol?

    // MARK: - Init

    init() {
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
        // Backgrounding (incl. screen lock): detach the muted video player's
        // item. It can't render back there anyway, and while it HAS an item
        // iOS ties the lock-screen Now Playing timebase to the AVPlayer — whose
        // suspended rate (0) freezes the scrubber while AudioKit audio keeps
        // playing. With no item attached, the system honours our own
        // elapsed/rate pushes. Reattached + resynced on foreground above.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.detachVideoForBackground() }
        }
        #endif
    }

    deinit {
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
    }

    // MARK: - Public Interface

    func applyEffects(_ effects: AudioEffects) {
        effectsProcessor.apply(effects, variSpeed: variSpeed, timePitch: timePitch)
        // If video mode, also sync AVPlayer rate to match speed
        if isVideoMode {
            syncVideoRate()
        }
    }

    func play(url: URL) {
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
    func prefetch(url: URL) {
        guard !url.isFileURL,
              !Self.videoExtensions.contains(url.pathExtension.lowercased()),
              prefetchedFiles[url] == nil,
              prefetchTasks[url] == nil
        else { return }

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tmpURL, _, error in
            // Move the temp file SYNCHRONOUSLY here — URLSession deletes it the moment
            // this delegate closure returns, so the previous `Task { @MainActor }` hop
            // moved it too late and always failed ("No such file or directory"), which
            // silently disabled prefetch/gapless. Only the state update hops to main.
            guard error == nil, let tmpURL else {
                Task { @MainActor [weak self] in self?.prefetchTasks[url] = nil }
                return
            }
            let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("prefetch-\(UUID().uuidString)")
                .appendingPathExtension(ext)
            let moved: URL?
            do {
                try FileManager.default.moveItem(at: tmpURL, to: dest)
                moved = dest
            } catch {
                print("URLAudioPlayer: Prefetch move failed – \(error)")
                moved = nil
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.prefetchTasks[url] = nil
                if let moved { self.prefetchedFiles[url] = moved }
            }
        }
        prefetchTasks[url] = task
        task.resume()
    }

    func resume() {
        shouldPlayWhenReady = true
        // Still loading — playback will start automatically once it's ready.
        guard !isBuffering else { return }
        resumeAudio()
        if isVideoMode {
            syncVideoPlayback()
        }
    }

    func pause() {
        shouldPlayWhenReady = false
        pauseAudio()
        if isVideoMode {
            videoPlayer?.pause()
        }
    }

    func stop() {
        cleanup()
    }

    func seek(to time: TimeInterval) {
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

    /// Backgrounding: pull the item out of the muted video player so it stops
    /// feeding the system Now Playing timebase (see the observer in `init` —
    /// a suspended AVPlayer's 0 rate froze the lock-screen scrubber).
    func detachVideoForBackground() {
        guard isVideoMode, let vp = videoPlayer, vp.currentItem != nil else { return }
        vp.pause()
        vp.replaceCurrentItem(with: nil)
    }

    /// Snap the muted video player back to the audio (AudioKit) playhead — used when
    /// returning from the background, where the video renderer was suspended while
    /// the audio kept advancing. Also reattaches the item dropped by
    /// `detachVideoForBackground`.
    func resyncVideoToAudio() {
        guard isVideoMode, let vp = videoPlayer else { return }
        if vp.currentItem == nil, let videoPlayerItem {
            vp.replaceCurrentItem(with: videoPlayerItem)
        }
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
        videoPlayer?.replaceCurrentItem(with: nil)
        videoPlayerItem = nil
        videoPlayer = nil
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

        // Standard resume first: a paused player continues from its paused
        // frame instantly — no file reload, no seek, no stutter.
        if akPlayer.status == .paused {
            akPlayer.resume()
            installCompletionHandler()
        }

        // Fallback: the player isn't resumable (an interruption tore the
        // engine down and dropped the scheduled audio) — reload the file and
        // seek back to where we were.
        if !akPlayer.isPlaying, let savedTime = pausedAtTime, let fileURL = loadedFileURL {
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
        } else if !akPlayer.isPlaying {
            akPlayer.play()
            installCompletionHandler()
        }

        pausedAtTime = nil
        effectsProcessor.reapply(variSpeed: variSpeed, timePitch: timePitch)

        startProgressUpdates()
    }

    func pauseAudio() {
        // A system interruption (another app taking audio) stops the engine
        // BEFORE we're notified — by the time this pause runs, currentTime may
        // have already snapped to 0. Fall back to the last ticked position so
        // resume doesn't restart the track from the beginning.
        let current = akPlayer.currentTime
        pausedAtTime = current > 0 ? current : elapsedTime
        // The completion handler is disarmed because an engine teardown mid-pause can
        // fire it spuriously (phantom "track finished" → auto-skip); resume re-arms it.
        akPlayer.completionHandler = nil
        akPlayer.pause()
        // Stop the engine so the audio session goes IDLE and iOS shows the lock-screen
        // controls as PAUSED. A running engine keeps the session "active/playing" — the
        // exact reason track SWITCHES keep it running (via a different path that doesn't
        // call pauseAudio) to avoid a paused flash. On a real user/interruption pause we
        // WANT paused, so we stop it. resumeAudio restarts the engine; if stopping drops
        // the queued audio, its fallback reloads + seeks back to `pausedAtTime`.
        engine.stop()

        stopProgressUpdates()
    }

    func seekAudio(to time: TimeInterval) {
        akPlayer.completionHandler = nil
        // A full load() is still required — AudioKit's seek(time:) needs the edit-time
        // reset that load() performs (a bare seek mis-seeks to start/end). But reuse the
        // player's already-open AVAudioFile via load(file:) so we DON'T reopen it from
        // disk on every scrub release AND every repeat-one loop boundary. load(url:) is
        // literally `AVAudioFile(forReading:)` + `load(file:)` internally, so this is
        // the same schedule/edit-time reset minus the disk read. Falls back to the URL
        // reopen if the open file isn't available.
        do {
            if let file = akPlayer.file {
                try akPlayer.load(file: file)
            } else if let fileURL = loadedFileURL {
                try akPlayer.load(url: fileURL)
            } else {
                return
            }
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
        // the timer's first tick is a beat out, which made the duration appear late.
        emitProgress()
        // 10Hz: at 0.5s a tick moved the scrubber ~2% of the bar on a short
        // track — visible steps. Ticks are cheap (no system now-playing push).
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.emitProgress() }
        }
    }

    private func emitProgress() {
        // Only trust currentTime while the player is actually running — a tick
        // landing in the window between a system interruption stopping the
        // engine and the notification arriving would clobber the real position
        // with 0, and every resume path restores from this value.
        if akPlayer.isPlaying {
            elapsedTime = akPlayer.currentTime
        }
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
protocol URLAudioPlayerDelegate: AnyObject {
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
