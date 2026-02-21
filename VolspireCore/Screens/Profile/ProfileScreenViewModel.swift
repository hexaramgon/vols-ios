//
//  ProfileScreenViewModel.swift
//  Volspire
//
//

import Combine
import DesignSystem
import MediaLibrary
import Observation
import Player
import Services
import SwiftUI

// MARK: - UI Models

struct ProfileTrack: Identifiable {
    let id: String
    let title: String
    let coverURL: URL?
    let audioURL: URL?
    let streams: Int
}

enum ProfileLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - ViewModel

@Observable @MainActor
final class ProfileScreenViewModel {
    var username: String = ""
    var bio: String = ""
    var profileImageURL: URL?
    var bannerImageURL: URL?
    var location: String = ""
    var followersCount: Int = 0
    var monthlyListenersCount: Int = 0
    var trackCount: Int = 0
    var tracks: [ProfileTrack] = []
    var loadingState: ProfileLoadingState = .idle

    var latestRelease: ProfileTrack? {
        tracks.first
    }

    var curatedTracks: [ProfileTrack] {
        Array(tracks.dropFirst())
    }

    weak var mediaState: MediaState?
    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
    var cancellables = Set<AnyCancellable>()
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
    }

    func loadProfile(userId: String) async {
        guard loadingState != .loading else { return }
        loadingState = .loading

        do {
            let profile = try await supabaseService.getUserProfile(userId: userId)

            username = profile.username ?? "Unknown"
            bio = profile.bio ?? ""
            profileImageURL = profile.profileImageUrl.flatMap { URL(string: $0) }
            bannerImageURL = profile.bannerImageUrl.flatMap { URL(string: $0) }
            location = profile.location ?? ""
            followersCount = profile.followersCount ?? 0
            monthlyListenersCount = profile.monthlyListenersCount
            trackCount = profile.trackCount
            tracks = profile.tracks.map { track in
                ProfileTrack(
                    id: track.id,
                    title: track.title,
                    coverURL: track.coverUrl.flatMap { URL(string: $0) },
                    audioURL: track.audioUrl.flatMap { URL(string: $0) },
                    streams: track.streams ?? 0
                )
            }
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
        }
    }
}

extension ProfileScreenViewModel: PlayerStateObserving {}
