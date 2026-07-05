//
//  AnalyticsEvent.swift
//  Volspire
//
//  The vendor-neutral analytics event. Mirrors the web app's `AnalyticsEvent`
//  (lib/analytics.ts) so both clients write the same shape into Supabase's
//  `analytics_events` table via the `log_analytics_event` RPC.
//

import Foundation

/// The full event allowlist enforced by the `log_analytics_event` RPC. Using a
/// typed enum (instead of raw strings) makes an `invalid_event_type` error
/// impossible at the call site. Raw values match the web/DB exactly — keep them
/// in sync with the RPC's `IN (...)` list.
public enum AnalyticsEventType: String, Sendable, CaseIterable {
    case audioSettingsChanged = "audio_settings_changed"
    case commentPosted = "comment_posted"
    case connectModalOpened = "connect_modal_opened"
    case connectOnboardingCompleted = "connect_onboarding_completed"
    case connectOnboardingStarted = "connect_onboarding_started"
    case downloadClicked = "download_clicked"
    case downloadModalOpened = "download_modal_opened"
    case packLiked = "pack_liked"
    case packSaved = "pack_saved"
    case pageView = "page_view"
    case playbackError = "playback_error"
    case purchaseAbandoned = "purchase_abandoned"
    case purchaseClicked = "purchase_clicked"
    case purchaseCompleted = "purchase_completed"
    case purchaseInitiated = "purchase_initiated"
    case refundCompleted = "refund_completed"
    case searchPerformed = "search_performed"
    case shareClicked = "share_clicked"
    case streamCounted = "stream_counted"
    case tierImpression = "tier_impression"
    case trackEnded = "track_ended"
    case trackLiked = "track_liked"
    case trackPlay = "track_play"
    case trackSaved = "track_saved"
    case trackUnliked = "track_unliked"
    case trackUnsaved = "track_unsaved"
    case userFollowed = "user_followed"
    case userUnfollowed = "user_unfollowed"
    case visualizerToggled = "visualizer_toggled"
}

public struct AnalyticsEvent: Sendable, Equatable {
    public let type: AnalyticsEventType
    public let trackId: String?
    public let sessionId: String
    public let metadata: [String: AnalyticsValue]

    public init(
        type: AnalyticsEventType,
        trackId: String? = nil,
        sessionId: String,
        metadata: [String: AnalyticsValue] = [:]
    ) {
        self.type = type
        self.trackId = trackId
        self.sessionId = sessionId
        self.metadata = metadata
    }
}
