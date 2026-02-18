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
            loadMockData(userId: userId)
        }
    }

    private func loadMockData(userId: String) {
        username = "DJ Shadow"
        bio = "Producer & beat maker from Los Angeles. Making music since 2018."
        profileImageURL = URL(string: "https://picsum.photos/seed/profile/200")
        bannerImageURL = URL(string: "https://picsum.photos/seed/banner/800/400")
        location = "Los Angeles, CA"
        followersCount = 1_243
        monthlyListenersCount = 8_502
        trackCount = 5
        tracks = [
            ProfileTrack(
                id: "t1",
                title: "Midnight Drive",
                coverURL: URL(string: "https://picsum.photos/seed/track1/400"),
                audioURL: nil,
                streams: 12_400
            ),
            ProfileTrack(
                id: "t2",
                title: "Summer Vibes",
                coverURL: URL(string: "https://picsum.photos/seed/track2/400"),
                audioURL: nil,
                streams: 8_320
            ),
            ProfileTrack(
                id: "t3",
                title: "City Lights",
                coverURL: URL(string: "https://picsum.photos/seed/track3/400"),
                audioURL: nil,
                streams: 5_190
            ),
            ProfileTrack(
                id: "t4",
                title: "Late Night Session",
                coverURL: URL(string: "https://picsum.photos/seed/track4/400"),
                audioURL: nil,
                streams: 3_740
            ),
            ProfileTrack(
                id: "t5",
                title: "Ocean Breeze",
                coverURL: URL(string: "https://picsum.photos/seed/track5/400"),
                audioURL: nil,
                streams: 2_100
            ),
        ]
        loadingState = .loaded
    }
}

extension ProfileScreenViewModel: PlayerStateObserving {}
