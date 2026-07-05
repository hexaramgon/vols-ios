//
//  AnalyticsService.swift
//  Volspire
//
//  The app-facing analytics facade. Call sites use the typed `log(...)` here and
//  never see the transport. Swapping events backend = construct this with a
//  different `AnalyticsSink` (e.g. `AnalyticsService(sink: PostHogSink())`).
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class AnalyticsService {
    /// App-wide accessor for scattered call sites (views, view models) — mirrors the
    /// web's module-level `logAnalyticsEvent`. Set once in `Dependencies`; still
    /// swappable, since it points at whatever `AnalyticsService` (and sink) you build.
    public static var shared: AnalyticsService?

    private let sink: AnalyticsSink

    /// Ambient session for events not tied to a playback session (likes, search…).
    /// Playback events carry their own per-listen session id (see ListenAnalyticsTracker).
    public let sessionId: String

    /// Device/app context attached to every event under `metadata.env` — the iOS
    /// analogue of the geo/UA the web app's server route stamps on.
    private let env: [String: AnalyticsValue]

    public init(sink: AnalyticsSink) {
        self.sink = sink
        self.sessionId = UUID().uuidString
        self.env = Self.makeEnv()
    }

    /// Log any event. `sessionId` defaults to the ambient app session. Fire-and-forget:
    /// returns immediately; the send happens in a detached task and never throws out.
    public func log(
        _ type: AnalyticsEventType,
        trackId: String? = nil,
        sessionId: String? = nil,
        metadata: [String: AnalyticsValue] = [:]
    ) {
        let event = AnalyticsEvent(
            type: type,
            trackId: trackId,
            sessionId: sessionId ?? self.sessionId,
            metadata: enrich(metadata)
        )
        Task { await sink.send(event) }
    }

    /// A counted stream (the play crossed the listen threshold). Mirrors the web's
    /// `increment_track_stream` call.
    public func countStream(
        trackId: String,
        sessionId: String,
        metadata: [String: AnalyticsValue] = [:]
    ) {
        let enriched = enrich(metadata)
        Task { await sink.incrementStream(trackId: trackId, sessionId: sessionId, metadata: enriched) }
    }

    private func enrich(_ metadata: [String: AnalyticsValue]) -> [String: AnalyticsValue] {
        var out = metadata
        out["env"] = .object(env)
        return out
    }

    private static func makeEnv() -> [String: AnalyticsValue] {
        var env: [String: AnalyticsValue] = ["platform": .string("ios")]
        let info = Bundle.main.infoDictionary
        if let version = info?["CFBundleShortVersionString"] as? String {
            env["app_version"] = .string(version)
        }
        if let build = info?["CFBundleVersion"] as? String {
            env["app_build"] = .string(build)
        }
        #if canImport(UIKit)
        let device = UIDevice.current
        env["os"] = .string("ios")
        env["os_version"] = .string(device.systemVersion)
        env["device"] = .string(device.userInterfaceIdiom == .pad ? "tablet" : "mobile")
        #endif
        return env
    }
}
