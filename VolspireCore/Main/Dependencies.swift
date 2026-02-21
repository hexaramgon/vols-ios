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

    init(
        apiService: APIService,
        supabaseService: SupabaseService,
        authManager: AuthManager,
        dataController: DataController,
        mediaState: MediaState,
        mediaPlayer: MediaPlayer,
        playerController: PlayerController
    ) {
        self.apiService = apiService
        self.supabaseService = supabaseService
        self.authManager = authManager
        self.dataController = dataController
        self.mediaState = mediaState
        self.mediaPlayer = mediaPlayer
        self.playerController = playerController
    }
}

extension Dependencies {
    static var stub: Dependencies = {
        let mediaPlayer = MediaPlayer()
        return Dependencies(
            apiService: APIService(baseURL: ""),
            supabaseService: SupabaseService(),
            authManager: AuthManager(),
            dataController: DataController(),
            mediaState: DefaultMediaState.stub,
            mediaPlayer: mediaPlayer,
            playerController: PlayerController(),
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

        return Dependencies(
            apiService: apiService,
            supabaseService: supabaseService,
            authManager: authManager,
            dataController: dataController,
            mediaState: mediaState,
            mediaPlayer: mediaPlayer,
            playerController: playerController
        )
    }
}
