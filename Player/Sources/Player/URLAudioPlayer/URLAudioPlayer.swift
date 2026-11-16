//
//  URLAudioPlayer.swift
//  Volspire
//
//  Dual-mode player:
//  • Audio files: AudioKit (AudioEngine → VariSpeed → TimePitch → EQ → Limiter → Mixer).
//  • Video files: Muted AVPlayer for video display + AudioKit for audio output.
//    This lets AudioKit effects (speed, pitch, EQ) apply to video audio too.
//    AVPlayer and AudioKit are kept in sync on play/pause/seek.
//

import AudioKit
import AVFoundation
import Combine
import MediaLibrary
import SharedUtilities
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
    nonisolated(unsafe) private let equalizer: EqualizerNode
    nonisolated(unsafe) private let limiter: PeakLimiter
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

    /// De-click on track switches: stopping the player mid-waveform is a hard
    /// discontinuity, audible as a click — especially on a prefetched skip, where
    /// the next track starts in the same instant. The outgoing track is faded out
    /// first (the next load waits for it), and the next one fades in.
    private var fadeOutTask: Task<Void, Never>?
    private var fadeInTask: Task<Void, Never>?
    private static let fadeDuration: TimeInterval = 0.03
    private static let fadeSteps = 6

    // Next-track prefetch: download the upcoming track to a local file while the
    // current one plays, so a skip has no download gap (and the lock screen never
    // shows "paused" mid-buffer). Spotify-style read-ahead.
    private var prefetchedFiles: [URL: URL] = [:]
    private var prefetchTasks: [URL: URLSessionDownloadTask] = [:]
    /// Read-ahead whose link is still being resolved (keeps it from starting twice).
    private var prefetchResolving: Set<URL> = []
    /// Read-ahead videos whose audio is being extracted (same guard).
    private var videoPrefetchExtracting: Set<URL> = []

    /// Exchanges a queued URL for a fetchable one just before downloading
    /// (set via `MediaPlayer.resolveMediaURL`). Downloads, the prefetch cache
    /// and `currentURL` all stay keyed by the original URL.
    var resolveRemoteURL: (@MainActor (URL) async -> URL?)?

    // MARK: - State

    /// Exposed to MediaPlayer.isVideoURL so the app's display-mode check and the
    /// engine's video-mode check can never disagree on a format.
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "webm"]

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
        // Graph: AudioPlayer → VariSpeed (resampling) → TimePitch (phase vocoder) → EQ
        // → Limiter → Mixer.
        // VariSpeed handles varispeed (pitch follows speed) cleanly; TimePitch handles
        // tempo-only changes when "preserve pitch" is on. Only one is active at a time.
        // EQ sits after both so its bands stay at fixed frequencies when varispeed
        // shifts the pitch. The limiter catches overlapping boosts. Both stay in the
        // path even when the EQ is flat — toggling their bypass mid-playback clicks.
        let vs = VariSpeed(akPlayer)
        let tp = TimePitch(vs)
        let eq = EqualizerNode(tp)
        let lim = PeakLimiter(eq)
        let mx = Mixer(lim)
        variSpeed = vs
        timePitch = tp
        equalizer = eq
        limiter = lim
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

    func applyEqualizer(_ settings: AudioEqualizer) {
        equalizer.apply(settings)
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
                        guard self.currentURL == url else { return }
                        self.fail("Audio extraction failed – \(error)")
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
        let isVideo = Self.videoExtensions.contains(url.pathExtension.lowercased())
        guard !url.isFileURL,
              // A prefetched video goes straight into the played-audio cache,
              // so only cacheable (stable-URL) videos are read ahead.
              !isVideo || AudioFileCache.isCacheable(url),
              // Already on disk from an earlier play / read-ahead.
              (isVideo ? cachedVideo(for: url) == nil : AudioFileCache.file(for: url) == nil),
              prefetchedFiles[url] == nil,
              prefetchTasks[url] == nil,
              !prefetchResolving.contains(url),
              !videoPrefetchExtracting.contains(url)
        else { return }

        prefetchResolving.insert(url)
        Task {
            let fetchURL = await self.fetchableURL(url)
            // Dropped from the read-ahead window while resolving.
            guard self.prefetchResolving.remove(url) != nil, let fetchURL else { return }
            self.startPrefetch(url, from: fetchURL, isVideo: isVideo)
        }
    }

    /// Video read-ahead runs only on unmetered networks: a video track can
    /// be 100MB+, so on cellular / Low Data Mode it still loads on demand.
    private static let videoPrefetchSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        return URLSession(configuration: config)
    }()

    private func startPrefetch(_ url: URL, from fetchURL: URL, isVideo: Bool) {
        let session = isVideo ? Self.videoPrefetchSession : URLSession.shared
        let generation = AudioFileCache.generation
        let task = session.downloadTask(with: fetchURL) { [weak self] tmpURL, response, error in
            // Claimed synchronously here — see `claimDownload`.
            let outcome = Self.claimDownload(tmpURL, response: response, error: error, from: url, prefix: "prefetch-")
            Task { @MainActor [weak self] in
                // Signed out meanwhile (or the player's gone): nobody owns it.
                guard let self, AudioFileCache.generation == generation else {
                    if case let .file(local) = outcome { try? FileManager.default.removeItem(at: local) }
                    return
                }
                self.prefetchTasks[url] = nil
                guard case let .file(local) = outcome else { return }
                if isVideo {
                    await self.cacheVideoReadAhead(local, for: url, generation: generation)
                } else {
                    self.prefetchedFiles[url] = local
                }
            }
        }
        prefetchTasks[url] = task
        task.resume()
    }

    /// A read-ahead video also needs its audio extracted before it can play
    /// (AudioKit can't open a video) — done now, so the skip is instant, and
    /// both files go into the played-audio cache.
    private func cacheVideoReadAhead(_ video: URL, for url: URL, generation: Int) async {
        videoPrefetchExtracting.insert(url)
        defer { videoPrefetchExtracting.remove(url) }
        guard let audio = try? await extractAudioTrack(from: video) else {
            try? FileManager.default.removeItem(at: video)
            return
        }
        // Signed out during the extraction — drop both, don't refill the cache.
        guard AudioFileCache.generation == generation else {
            try? FileManager.default.removeItem(at: video)
            try? FileManager.default.removeItem(at: audio)
            return
        }
        cacheVideo(video, audio: audio, for: url)
    }

    /// Both halves of a video into the cache — or neither (one alone can't play).
    private func cacheVideo(_ video: URL, audio: URL, for url: URL) {
        if AudioFileCache.adopt(video, for: url),
           AudioFileCache.adopt(audio, for: url, part: .extractedAudio) {
            return
        }
        try? FileManager.default.removeItem(at: video)
        try? FileManager.default.removeItem(at: audio)
    }

    /// A cached video track: its video (display) and extracted audio (playback).
    private func cachedVideo(for url: URL) -> (video: URL, audio: URL)? {
        guard let audio = AudioFileCache.file(for: url, part: .extractedAudio),
              let video = AudioFileCache.file(for: url) else { return nil }
        return (video, audio)
    }

    /// Drops read-ahead (in-flight or finished) for every URL not in `keep`.
    func retainPrefetch(_ keep: Set<URL>) {
        prefetchResolving.formIntersection(keep)
        for (url, task) in prefetchTasks where !keep.contains(url) {
            task.cancel()
            prefetchTasks[url] = nil
        }
        for (url, file) in prefetchedFiles where !keep.contains(url) {
            releaseDownloadedFile(file, for: url)
            prefetchedFiles[url] = nil
        }
    }

    /// A fully downloaded file nobody plays from any more: into the played-
    /// audio cache (a later play skips the download), else deleted.
    private func releaseDownloadedFile(_ file: URL, for url: URL) {
        if !AudioFileCache.adopt(file, for: url) {
            try? FileManager.default.removeItem(at: file)
        }
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
        // Played before (Previous, replay, repeat-all, a re-tap) → straight from
        // the played-audio cache: no link signing, no download. Not owned here
        // (tempFileURL stays nil), so cleanup leaves it in place.
        if !isVideoMode, let cached = AudioFileCache.file(for: remoteURL) {
            loadAndPlayAudio(fileURL: cached)
            return
        }
        // A video played or read ahead before: the cached video for display +
        // its already-extracted audio — no download, no extraction.
        if isVideoMode, let cached = cachedVideo(for: remoteURL) {
            setupVideoDisplay(fileURL: cached.video)
            loadAndPlayAudio(fileURL: cached.audio)
            return
        }
        downloadTask?.cancel()
        downloadTask = nil
        Task {
            guard let fetchURL = await self.fetchableURL(remoteURL) else {
                guard self.currentURL == remoteURL else { return }
                self.fail("No playable link for \(remoteURL.lastPathComponent)")
                return
            }
            // Skipped past while the link was resolving.
            guard self.currentURL == remoteURL else { return }
            self.startDownload(remoteURL, from: fetchURL)
        }
    }

    /// The URL to actually fetch for `url` (see `resolveRemoteURL`).
    func fetchableURL(_ url: URL) async -> URL? {
        guard let resolveRemoteURL else { return url }
        return await resolveRemoteURL(url)
    }

    func startDownload(_ remoteURL: URL, from fetchURL: URL) {
        let task = URLSession.shared.downloadTask(with: fetchURL) { [weak self] tmpURL, response, error in
            // Claimed synchronously here — see `claimDownload`.
            let outcome = Self.claimDownload(tmpURL, response: response, error: error, from: remoteURL)
            Task { @MainActor [weak self] in
                guard let self, self.currentURL == remoteURL else {
                    // Skipped past while downloading — nobody owns the file.
                    if case let .file(local) = outcome { try? FileManager.default.removeItem(at: local) }
                    return
                }
                switch outcome {
                case .cancelled:
                    return
                case let .failed(reason):
                    self.fail(reason)
                case let .file(dest):
                    self.tempFileURL = dest
                    if self.isVideoMode {
                        self.setupVideoDisplay(fileURL: dest)
                        do {
                            let audioURL = try await self.extractAudioTrack(from: dest)
                            guard self.currentURL == remoteURL else { return }
                            self.extractedAudioURL = audioURL
                            self.loadAndPlayAudio(fileURL: audioURL)
                        } catch {
                            guard self.currentURL == remoteURL else { return }
                            self.fail("Audio extraction failed – \(error)")
                        }
                    } else {
                        self.loadAndPlayAudio(fileURL: dest)
                    }
                }
            }
        }
        task.resume()
        downloadTask = task
    }

    func loadAndPlayAudio(fileURL: URL) {
        // The outgoing track is still fading out — load once it's silent.
        if let fadeOutTask {
            let url = currentURL
            Task {
                await fadeOutTask.value
                guard self.currentURL == url else { return } // skipped again meanwhile
                self.loadAndPlayAudio(fileURL: fileURL)
            }
            return
        }
        do {
            try akPlayer.load(url: fileURL)
        } catch {
            fail("Failed to load – \(error)")
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
            fail("Engine start failed – \(error)")
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
        fadeIn()

        // Start the muted video player in sync
        if isVideoMode {
            syncVideoPlayback()
        }

        startProgressUpdates()
    }

    func resumeAudio() {
        guard !akPlayer.isPlaying else { return }
        // A switch faded the mixer out and was paused before the next track
        // started — make sure the resumed audio is audible.
        fadeInTask?.cancel()
        fadeInTask = nil
        mixer.volume = 1
        do {
            if !engine.avEngine.isRunning {
                try engine.start()
            }
        } catch {
            debugLog("URLAudioPlayer: Engine start failed – \(error)")
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
                debugLog("URLAudioPlayer: Failed to reload on resume – \(error)")
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
        // Mid-switch the player still holds the outgoing track's file.
        guard fadeOutTask == nil else { return }
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
            debugLog("URLAudioPlayer: Seek failed – \(error)")
        }
        effectsProcessor.reapply(variSpeed: variSpeed, timePitch: timePitch)
    }

    /// `stopEngine: false` keeps the audio engine running — used when switching
    /// tracks so the audio session never goes idle during the download gap (which
    /// makes iOS show the lock-screen controls as paused, Spotify-style buffering).
    func cleanupAudio(stopEngine: Bool = true) {
        stopProgressUpdates()

        akPlayer.completionHandler = nil
        fadeInTask?.cancel()
        fadeInTask = nil

        if stopEngine {
            fadeOutTask?.cancel()
            fadeOutTask = nil
            akPlayer.stop()
            engine.stop()
            mixer.volume = 1
            return
        }

        // Track switch: fade the outgoing audio out before stopping it.
        // Already fading (rapid skips) → that fade stops it.
        guard fadeOutTask == nil else { return }
        guard akPlayer.isPlaying, engine.avEngine.isRunning, mixer.volume > 0 else {
            akPlayer.stop()
            return
        }
        fadeOutTask = Task { [weak self] in
            guard let self else { return }
            await self.rampMixer(to: 0)
            // The last volume step only takes effect on the next render cycle —
            // stopping right away discards the end of the fade (a hard cut).
            try? await Task.sleep(nanoseconds: UInt64(Self.renderSettleTime * 1_000_000_000))
            // Cancelled by a full stop, which already stopped the player and
            // may have started a newer fade — leave its state alone.
            guard !Task.isCancelled else { return }
            self.akPlayer.stop()
            self.fadeOutTask = nil
        }
    }

    /// Ramps the mixer up from silence for a newly started track.
    func fadeIn() {
        fadeInTask?.cancel()
        mixer.volume = 0
        // The effect chain (TimePitch especially) delays the new track's audio and
        // emits a short glitch as it starts up — stay silent through that window,
        // then ramp in as the real audio arrives.
        let delay = effectChainLatency + Self.renderSettleTime
        fadeInTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.rampMixer(to: 1)
        }
    }

    /// Processing delay of the effect units between the player and the mixer.
    var effectChainLatency: TimeInterval {
        [variSpeed.avAudioNode, timePitch.avAudioNode, equalizer.avAudioNode, limiter.avAudioNode]
            .reduce(0) { $0 + $1.latency }
    }

    /// Roughly two render cycles: long enough for a volume change to be heard.
    static var renderSettleTime: TimeInterval {
        max(0.02, AVAudioSession.sharedInstance().ioBufferDuration * 2)
    }

    /// Steps the mixer volume to `target` over `fadeDuration`. A cancelled ramp
    /// leaves the volume wherever it got to (the canceller sets it).
    func rampMixer(to target: AUValue) async {
        let start = mixer.volume
        let steps = Self.fadeSteps
        let stepNanos = UInt64(Self.fadeDuration / Double(steps) * 1_000_000_000)
        for step in 1 ... steps {
            try? await Task.sleep(nanoseconds: stepNanos)
            if Task.isCancelled { return }
            mixer.volume = start + (target - start) * AUValue(step) / AUValue(steps)
        }
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

/// What became of a finished download task, decided inside URLSession's
/// completion closure (where the temp file still exists).
private enum DownloadOutcome: Sendable {
    case file(URL)
    case cancelled
    case failed(String)
}

private extension URLAudioPlayer {
    /// Validates a finished download and moves it somewhere we own. MUST run
    /// synchronously inside the completion closure: URLSession deletes `tmpURL`
    /// the moment that closure returns, so a move after a `Task` hop races the
    /// deletion. A non-2xx reply (expired signed URL, 404) is a failure, not a
    /// file — otherwise the server's error page gets saved as audio.
    nonisolated static func claimDownload(
        _ tmpURL: URL?,
        response: URLResponse?,
        error: Error?,
        from remoteURL: URL,
        prefix: String = ""
    ) -> DownloadOutcome {
        if let error {
            if (error as? URLError)?.code == .cancelled { return .cancelled }
            return .failed("Download failed – \(error)")
        }
        if let status = (response as? HTTPURLResponse)?.statusCode, !(200 ..< 300).contains(status) {
            return .failed("Download failed – HTTP \(status)")
        }
        guard let tmpURL else { return .failed("Download failed – no file") }
        let ext = remoteURL.pathExtension.isEmpty ? "mp3" : remoteURL.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(prefix + UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            return .file(dest)
        } catch {
            return .failed("Failed to move temp file – \(error)")
        }
    }

    /// The current URL can't play. Clears buffering (so the UI stops spinning)
    /// and reports up; `MediaPlayer` tears down and pauses.
    func fail(_ reason: String) {
        debugLog("URLAudioPlayer: \(reason)")
        // A cached copy may be what failed (a read-ahead is cached before it's
        // ever decoded) — drop it, or every replay would hit it and fail again.
        if let currentURL { AudioFileCache.remove(currentURL) }
        setBuffering(false)
        delegate?.urlAudioPlayerDidFail(self)
    }

    func cleanup(stopEngine: Bool = true) {
        downloadTask?.cancel()
        downloadTask = nil
        // A skip (stopEngine == false) keeps the read-ahead; a full stop drops it.
        if stopEngine {
            prefetchTasks.values.forEach { $0.cancel() }
            prefetchTasks.removeAll()
            for (url, file) in prefetchedFiles { releaseDownloadedFile(file, for: url) }
            prefetchedFiles.removeAll()
        }
        setBuffering(false)
        shouldPlayWhenReady = true

        cleanupAudio(stopEngine: stopEngine)
        if isVideoMode {
            cleanupVideo()
        }

        // Clean up temp files. A file that loaded fine goes into the played-
        // audio cache instead (a failed load isn't cached — it would fail the
        // same way forever): audio as-is; a video as video + extracted audio.
        // The display player was released above, so moving its file is safe.
        if let tempFileURL {
            if !isVideoMode, loadedFileURL == tempFileURL, let currentURL {
                releaseDownloadedFile(tempFileURL, for: currentURL)
            } else if isVideoMode, let extractedAudioURL, loadedFileURL == extractedAudioURL,
                      let currentURL, AudioFileCache.isCacheable(currentURL) {
                cacheVideo(tempFileURL, audio: extractedAudioURL, for: currentURL)
                self.extractedAudioURL = nil
            } else {
                try? FileManager.default.removeItem(at: tempFileURL)
            }
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
    /// The current URL couldn't be downloaded, decoded or started.
    func urlAudioPlayerDidFail(_ player: URLAudioPlayer)
}

public struct PlaybackProgress: Equatable, Sendable {
    public let elapsedTime: TimeInterval
    public let duration: TimeInterval

    public init(elapsedTime: TimeInterval, duration: TimeInterval) {
        self.elapsedTime = elapsedTime
        self.duration = duration
    }
}
