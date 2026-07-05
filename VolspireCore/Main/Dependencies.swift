//
//  Dependencies.swift
//  Volspire
//
//

import MediaLibrary
import Observation
import Player
import Services

@MainActor
class Dependencies: Observable {
    let apiService: APIService
    let supabaseService: SupabaseService
    let authManager: AuthManager
    let dataController: DataController
    let mediaState: MediaState
    let mediaPlayer: MediaPlayer
    let playerController: PlayerController
    let analytics: AnalyticsService
    /// Observes the player and emits the listen funnel (track_play → stream → track_ended).
    /// Held here so its subscriptions live for the app's lifetime.
    let listenAnalytics: ListenAnalyticsTracker

    init(
        apiService: APIService,
        supabaseService: SupabaseService,
        authManager: AuthManager,
        dataController: DataController,
        mediaState: MediaState,
        mediaPlayer: MediaPlayer,
        playerController: PlayerController,
        analytics: AnalyticsService,
        listenAnalytics: ListenAnalyticsTracker
    ) {
        self.apiService = apiService
        self.supabaseService = supabaseService
        self.authManager = authManager
        self.dataController = dataController
        self.mediaState = mediaState
        self.mediaPlayer = mediaPlayer
        self.playerController = playerController
        self.analytics = analytics
        self.listenAnalytics = listenAnalytics
    }
}

extension Dependencies {
    static var stub: Dependencies = {
        let mediaPlayer = MediaPlayer()
        let analytics = AnalyticsService(sink: NoopAnalyticsSink())
        AnalyticsService.shared = analytics
        let listenAnalytics = ListenAnalyticsTracker(player: mediaPlayer, analytics: analytics)
        let playerController = PlayerController()
        playerController.analytics = analytics
        return Dependencies(
            apiService: APIService(baseURL: ""),
            supabaseService: SupabaseService(),
            authManager: AuthManager(),
            dataController: DataController(),
            mediaState: DefaultMediaState.stub,
            mediaPlayer: mediaPlayer,
            playerController: playerController,
            analytics: analytics,
            listenAnalytics: listenAnalytics
        )
    }()

    static func make() -> Dependencies {
        let dataController = DataController()
        let mediaState = DefaultMediaState()
        let mediaPlayer = MediaPlayer()
        mediaPlayer.mediaState = mediaState

        let playerController = PlayerController()
        playerController.player = mediaPlayer
        playerController.mediaState = mediaState

        let apiService = APIService(baseURL: "https://volspire.ru")
        let supabaseService = SupabaseService()
        let authManager = AuthManager()

        // Analytics: vendor-neutral facade over a Supabase sink. To migrate to a
        // different events backend later, swap `SupabaseAnalyticsSink()` here.
        let analytics = AnalyticsService(sink: SupabaseAnalyticsSink())
        AnalyticsService.shared = analytics
        playerController.analytics = analytics
        let listenAnalytics = ListenAnalyticsTracker(player: mediaPlayer, analytics: analytics)

        return Dependencies(
            apiService: apiService,
            supabaseService: supabaseService,
            authManager: authManager,
            dataController: dataController,
            mediaState: mediaState,
            mediaPlayer: mediaPlayer,
            playerController: playerController,
            analytics: analytics,
            listenAnalytics: listenAnalytics
        )
    }
}
