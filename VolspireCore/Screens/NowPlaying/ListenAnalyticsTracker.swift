//
//  ListenAnalyticsTracker.swift
//  Volspire
//
//  The iOS port of the web app's `useListenAnalytics` hook. Subscribes to the
//  shared MediaPlayer and emits the playback funnel — track_play → (counted
//  stream) → track_ended — through the swappable AnalyticsService. Kept separate
//  from PlayerController on purpose: it observes the player directly so the
//  analytics concern stays isolated and easy to remove/replace.
//

import Combine
import Foundation
import MediaLibrary
import Player
import Services

@MainActor
final class ListenAnalyticsTracker {
    private let analytics: AnalyticsService
    private var cancellables = Set<AnyCancellable>()

    /// A play counts once enough of it has actually elapsed: 30s, or 80% of a
    /// short track — matches the web thresholds.
    private static let streamThreshold: TimeInterval = 30
    private static let shortTrackRatio = 0.8

    // Per-listen session — a fresh uuid per track start / replay.
    private var sessionId = UUID().uuidString
    private var currentTrackId: String?

    private var isPlaying = false
    private var duration: TimeInterval = 0
    private var lastElapsed: TimeInterval = 0
    private var accumulatedTime: TimeInterval = 0
    private var streamCounted = false
    private var seekCount = 0

    // Listened spans [start, end] in whole seconds — opened on play/seek, closed
    // on pause/seek/track-change.
    private var segments: [[Int]] = []
    private var segmentStart: Int?

    init(player: MediaPlayer, analytics: AnalyticsService) {
        self.analytics = analytics

        player.$state
            .sink { [weak self] state in self?.handle(state: state) }
            .store(in: &cancellables)

        player.$progress
            .sink { [weak self] progress in self?.handle(progress: progress) }
            .store(in: &cancellables)
    }

    // MARK: - State: track changes + play/pause transitions

    private func handle(state: MediaPlayerState) {
        let newTrackId = state.currentMediaID?.value
        let playing = state.isPlaying

        if newTrackId != currentTrackId {
            endCurrentSession(endedNaturally: nearEnd())
            startSession(trackId: newTrackId, playing: playing)
        }

        if playing != isPlaying {
            if playing {
                openSegment()
            } else {
                closeSegment()
                // A pause that lands at the very end of the (last) track is a
                // natural finish — flush it and arm a fresh session for replays.
                if nearEnd(), let trackId = currentTrackId {
                    emitEnded(trackId: trackId, endedNaturally: true)
                    resetSession(playing: false)
                }
            }
            isPlaying = playing
        }
    }

    // MARK: - Progress: accumulate time, detect seeks, count the stream

    private func handle(progress: PlaybackProgress?) {
        guard let progress else { return }
        duration = progress.duration
        let elapsed = progress.elapsedTime
        defer { lastElapsed = elapsed }

        guard isPlaying else { return }

        let delta = elapsed - lastElapsed
        if delta >= 0, delta < 1.5 {
            // Normal forward playback tick.
            accumulatedTime += delta
        } else if abs(delta) >= 1.5 {
            // A jump = a seek: close the old span, open a new one at the landing.
            closeSegment(at: lastElapsed)
            seekCount += 1
            segmentStart = Int(elapsed.rounded())
        }

        let threshold = duration > 0
            ? min(Self.streamThreshold, duration * Self.shortTrackRatio)
            : Self.streamThreshold
        if !streamCounted, accumulatedTime >= threshold, let trackId = currentTrackId {
            streamCounted = true
            analytics.countStream(
                trackId: trackId,
                sessionId: sessionId,
                metadata: [
                    "accumulated_time": .int(Int(accumulatedTime.rounded())),
                    "duration": .double(duration),
                    "source": .null,
                ]
            )
        }
    }

    // MARK: - Sessions

    private func startSession(trackId: String?, playing: Bool) {
        currentTrackId = trackId
        resetSession(playing: playing)
        guard let trackId else { return }
        analytics.log(
            .trackPlay,
            trackId: trackId,
            sessionId: sessionId,
            metadata: [
                "source": .null,
                "duration": .double(duration),
                "timestamp": .string(MessageTime.isoNow()),
            ]
        )
    }

    private func resetSession(playing: Bool) {
        sessionId = UUID().uuidString
        accumulatedTime = 0
        streamCounted = false
        seekCount = 0
        segments = []
        lastElapsed = 0
        segmentStart = playing ? 0 : nil
        isPlaying = playing
    }

    /// Flush the in-flight listen (on track change / stop) as a `track_ended`.
    private func endCurrentSession(endedNaturally: Bool) {
        guard let trackId = currentTrackId else { return }
        closeSegment()
        emitEnded(trackId: trackId, endedNaturally: endedNaturally)
    }

    private func emitEnded(trackId: String, endedNaturally: Bool) {
        let completion = duration > 0 ? Int(((accumulatedTime / duration) * 100).rounded()) : 0
        analytics.log(
            .trackEnded,
            trackId: trackId,
            sessionId: sessionId,
            metadata: [
                "accumulated_time": .int(Int(accumulatedTime.rounded())),
                "duration": .double(duration),
                "completion_pct": .int(min(100, completion)),
                "ended_naturally": .bool(endedNaturally),
                "seek_count": .int(seekCount),
                "listened_segments": .array(segments.map { .array([.int($0[0]), .int($0[1])]) }),
                "source": .null,
            ]
        )
    }

    // MARK: - Listened segments

    private func openSegment() {
        segmentStart = Int(lastElapsed.rounded())
    }

    private func closeSegment() {
        closeSegment(at: lastElapsed)
    }

    private func closeSegment(at position: TimeInterval) {
        guard let start = segmentStart else { return }
        let end = Int(position.rounded())
        if end > start { segments.append([start, end]) }
        segmentStart = nil
    }

    private func nearEnd() -> Bool {
        duration > 0 && lastElapsed >= duration - 1.5
    }
}
