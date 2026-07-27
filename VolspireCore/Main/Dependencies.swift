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
    let supabaseService: SupabaseService
    let authManager: AuthManager
    let mediaState: MediaState
    let mediaPlayer: MediaPlayer
    let playerController: PlayerController
    let analytics: AnalyticsService
    /// Observes the player and emits the listen funnel (track_play → stream → track_ended).
    /// Held here so its subscriptions live for the app's lifetime.
    let listenAnalytics: ListenAnalyticsTracker

    // Shared domain stores — the single source of truth for cross-screen server
    // state. Injected via `.environment` in AppView; screens render from these
    // and route mutations through them (see Stores/).
    let libraryStore: LibraryStore
    let workspaceStore: WorkspaceStore
    let socialStore: SocialStore
    let inboxStore: InboxStore
    let listingsStore: ListingsStore
    let feedStore: FeedStore

    init(
        supabaseService: SupabaseService,
        authManager: AuthManager,
        mediaState: MediaState,
        mediaPlayer: MediaPlayer,
        playerController: PlayerController,
        analytics: AnalyticsService,
        listenAnalytics: ListenAnalyticsTracker
    ) {
        self.supabaseService = supabaseService
        self.authManager = authManager
        self.mediaState = mediaState
        self.mediaPlayer = mediaPlayer
        self.playerController = playerController
        self.analytics = analytics
        self.listenAnalytics = listenAnalytics
        let storageService = StorageService()
        libraryStore = LibraryStore(service: supabaseService, storage: storageService, auth: authManager)
        workspaceStore = WorkspaceStore(service: supabaseService, storage: storageService)
        socialStore = SocialStore(service: supabaseService, auth: authManager)
        inboxStore = InboxStore(service: supabaseService)
        listingsStore = ListingsStore(service: supabaseService)
        feedStore = FeedStore(service: supabaseService, storage: storageService)
        libraryStore.mediaState = mediaState
        playerController.library = libraryStore
        feedStore.social = socialStore
    }
}

extension Dependencies {
    /// Auth-boundary teardown (sign-out): silence and fully clear the player,
    /// wipe the in-memory media registry, and reset per-user controller state.
    /// Server-response caches are cleared by `AuthManager.signOut` itself;
    /// Kingfisher's image cache stays (covers, avatars — public content).
    func resetForSignOut() {
        mediaPlayer.reset()
        playerController.resetForSignOut()
        Task { await mediaState.removeAll() }
        libraryStore.resetForSignOut()
        workspaceStore.resetForSignOut()
        socialStore.resetForSignOut()
        inboxStore.resetForSignOut()
        listingsStore.resetForSignOut()
        feedStore.resetForSignOut()
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
            supabaseService: SupabaseService(),
            authManager: AuthManager(),
            mediaState: DefaultMediaState.stub,
            mediaPlayer: mediaPlayer,
            playerController: playerController,
            analytics: analytics,
            listenAnalytics: listenAnalytics
        )
    }()

    static func make() -> Dependencies {
        let mediaState = DefaultMediaState()
        let mediaPlayer = MediaPlayer()
        mediaPlayer.mediaState = mediaState

        let playerController = PlayerController()
        playerController.player = mediaPlayer
        playerController.mediaState = mediaState

        let supabaseService = SupabaseService()
        let authManager = AuthManager()

        // Analytics: vendor-neutral facade over a Supabase sink. To migrate to a
        // different events backend later, swap `SupabaseAnalyticsSink()` here.
        let analytics = AnalyticsService(sink: SupabaseAnalyticsSink())
        AnalyticsService.shared = analytics
        playerController.analytics = analytics
        let listenAnalytics = ListenAnalyticsTracker(player: mediaPlayer, analytics: analytics)

        return Dependencies(
            supabaseService: supabaseService,
            authManager: authManager,
            mediaState: mediaState,
            mediaPlayer: mediaPlayer,
            playerController: playerController,
            analytics: analytics,
            listenAnalytics: listenAnalytics
        )
    }
}
