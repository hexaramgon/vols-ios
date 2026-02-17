//
//  HomeScreenViewModel.swift
//  Volspire
//
//  Created by GitHub Copilot on 01.02.2026.
//

import Foundation
import MediaLibrary
import Player
import Services

// MARK: - UI Models

struct HomeFilter: Identifiable {
    let id: String
    let title: String
    let hasModal: Bool

    init(id: String, title: String, hasModal: Bool = false) {
        self.id = id
        self.title = title
        self.hasModal = hasModal
    }
}

struct FollowingUser: Identifiable {
    let id: String
    let username: String
    let profileImageURL: URL?
}

struct HomeTrack: Identifiable {
    let id: String
    let title: String
    let artist: String
    let coverURL: URL?
    let audioURL: URL?
}

struct FeaturedItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let label: String
    let imageURL: URL?
}

// MARK: - Loading State

enum HomeLoadingState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - ViewModel

@Observable
@MainActor
class HomeScreenViewModel {
    var activeFilters: Set<String> = []
    var following: [FollowingUser] = []
    var filters: [HomeFilter] = []
    var loadingState: HomeLoadingState = .idle
    var errorMessage: String?

    // Sections
    var featuredItems: [FeaturedItem] = []
    var recommendedTracks: [HomeTrack] = []
    var trendingTracks: [HomeTrack] = []
    var newReleases: [HomeTrack] = []
    var recentlyPlayed: [HomeTrack] = []
    var topProducers: [FollowingUser] = []

    weak var mediaState: MediaState?
    weak var player: MediaPlayer?

    private let supabaseService: SupabaseService

    init(supabaseService: SupabaseService = SupabaseService()) {
        self.supabaseService = supabaseService
        loadFilters()
    }

    func toggleFilter(_ id: String) {
        if activeFilters.contains(id) {
            activeFilters.remove(id)
        } else {
            activeFilters.insert(id)
        }
    }

    /// Play a track from the home screen by adding it to the media library and starting playback.
    func playTrack(_ track: HomeTrack) {
        guard let audioURL = track.audioURL else { return }

        let mediaID = MediaID(track.id)
        let media = Media(
            id: mediaID,
            meta: MediaMeta(
                artwork: track.coverURL,
                title: track.title,
                artist: track.artist,
                audioURL: audioURL
            )
        )

        // Ensure the track is in the media state so the player can resolve it
        Task {
            await mediaState?.addTrack(media)
        }

        // Collect all tracks in the current section for queue context
        let allSectionTracks = (recommendedTracks + trendingTracks + newReleases + recentlyPlayed)
            .filter { $0.audioURL != nil }

        // Add all section tracks to media state for queue navigation
        Task {
            for t in allSectionTracks where t.id != track.id {
                let m = Media(
                    id: MediaID(t.id),
                    meta: MediaMeta(
                        artwork: t.coverURL,
                        title: t.title,
                        artist: t.artist,
                        audioURL: t.audioURL
                    )
                )
                await mediaState?.addTrack(m)
            }
        }

        let queueIDs = allSectionTracks.map { MediaID($0.id) }
        player?.play(mediaID, of: queueIDs.isEmpty ? [mediaID] : queueIDs)
    }

    /// Load home data from Supabase
    func loadHomeData() async {
        guard loadingState != .loading else { return }
        
        loadingState = .loading
        errorMessage = nil
        
        do {
            let response = try await supabaseService.getHomeTracks()
            
            // Map API response to UI models
            featuredItems = response.featuredItems?.map { item in
                FeaturedItem(
                    id: item.id,
                    title: item.title,
                    subtitle: item.subtitle ?? "",
                    label: item.label ?? "",
                    imageURL: item.imageUrl.flatMap { URL(string: $0) }
                )
            } ?? []
            
            recommendedTracks = mapTracks(response.recommendedTracks)
            trendingTracks = mapTracks(response.trendingTracks)
            newReleases = mapTracks(response.newReleases)
            recentlyPlayed = mapTracks(response.recentlyPlayed)
            
            topProducers = response.topProducers?.map { producer in
                FollowingUser(
                    id: producer.id,
                    username: producer.username,
                    profileImageURL: producer.profileImageUrl.flatMap { URL(string: $0) }
                )
            } ?? []
            
            following = response.following?.map { user in
                FollowingUser(
                    id: user.id,
                    username: user.username,
                    profileImageURL: user.profileImageUrl.flatMap { URL(string: $0) }
                )
            } ?? []
            
            loadingState = .loaded
        } catch {
            loadingState = .error(error.localizedDescription)
            errorMessage = error.localizedDescription
            
            // Fall back to mock data on error
            loadMockData()
        }
    }
    
    /// Refresh home data
    func refresh() async {
        await loadHomeData()
    }

    private func mapTracks(_ apiTracks: [ApiHomeTrack]?) -> [HomeTrack] {
        apiTracks?.map { track in
            HomeTrack(
                id: track.id,
                title: track.title,
                artist: track.artist ?? "Unknown Artist",
                coverURL: track.coverUrl.flatMap { URL(string: $0) },
                audioURL: track.audioUrl.flatMap { URL(string: $0) }
            )
        } ?? []
    }

    private func loadFilters() {
        // Filters are static UI elements
        filters = [
            HomeFilter(id: "location", title: "Location ▼", hasModal: true),
            HomeFilter(id: "occupation", title: "Occupation ▼", hasModal: true),
            HomeFilter(id: "genre", title: "Genre ▼", hasModal: true),
            HomeFilter(id: "for-sale", title: "For Sale"),
            HomeFilter(id: "trending", title: "Trending"),
            HomeFilter(id: "recent", title: "Recent"),
        ]
    }

    private func loadMockData() {
        // Mock Following Users
        following = [
            FollowingUser(
                id: "1",
                username: "DJ Shadow",
                profileImageURL: URL(string: "https://picsum.photos/seed/user1/100")
            ),
            FollowingUser(
                id: "2",
                username: "Producer X",
                profileImageURL: URL(string: "https://picsum.photos/seed/user2/100")
            ),
            FollowingUser(
                id: "3",
                username: "BeatMaker",
                profileImageURL: URL(string: "https://picsum.photos/seed/user3/100")
            ),
            FollowingUser(
                id: "4",
                username: "VocalQueen",
                profileImageURL: URL(string: "https://picsum.photos/seed/user4/100")
            ),
            FollowingUser(
                id: "5",
                username: "SynthLord",
                profileImageURL: URL(string: "https://picsum.photos/seed/user5/100")
            ),
            FollowingUser(
                id: "6",
                username: "DrumKing",
                profileImageURL: URL(string: "https://picsum.photos/seed/user6/100")
            ),
        ]

        // Featured Items (Hero Section)
        featuredItems = [
            FeaturedItem(
                id: "f1",
                title: "Summer Beats Collection",
                subtitle: "The hottest tracks of the season",
                label: "Playlist",
                imageURL: URL(string: "https://picsum.photos/seed/hero1/600/340")
            ),
            FeaturedItem(
                id: "f2",
                title: "Rising Stars 2026",
                subtitle: "Discover the next big artists",
                label: "Featured",
                imageURL: URL(string: "https://picsum.photos/seed/hero2/600/340")
            ),
            FeaturedItem(
                id: "f3",
                title: "Late Night Vibes",
                subtitle: "Chill beats for the evening",
                label: "Mood",
                imageURL: URL(string: "https://picsum.photos/seed/hero3/600/340")
            ),
        ]

        // Recommended Tracks
        recommendedTracks = [
            HomeTrack(
                id: "r1",
                title: "Midnight Drive",
                artist: "DJ Shadow",
                coverURL: URL(string: "https://picsum.photos/seed/rec1/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "r2",
                title: "Summer Vibes",
                artist: "Producer X",
                coverURL: URL(string: "https://picsum.photos/seed/rec2/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "r3",
                title: "City Lights",
                artist: "BeatMaker",
                coverURL: URL(string: "https://picsum.photos/seed/rec3/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "r4",
                title: "Ocean Waves",
                artist: "VocalQueen",
                coverURL: URL(string: "https://picsum.photos/seed/rec4/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "r5",
                title: "Neon Dreams",
                artist: "SynthLord",
                coverURL: URL(string: "https://picsum.photos/seed/rec5/400"),
                audioURL: nil
            ),
        ]

        // Trending Tracks
        trendingTracks = [
            HomeTrack(
                id: "t1",
                title: "Fire Starter",
                artist: "HotBeats",
                coverURL: URL(string: "https://picsum.photos/seed/trend1/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "t2",
                title: "Viral Wave",
                artist: "TikTok King",
                coverURL: URL(string: "https://picsum.photos/seed/trend2/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "t3",
                title: "Chart Topper",
                artist: "PopStar",
                coverURL: URL(string: "https://picsum.photos/seed/trend3/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "t4",
                title: "Bass Drop",
                artist: "EDM Master",
                coverURL: URL(string: "https://picsum.photos/seed/trend4/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "t5",
                title: "Golden Hour",
                artist: "Sunset Crew",
                coverURL: URL(string: "https://picsum.photos/seed/trend5/400"),
                audioURL: nil
            ),
        ]

        // New Releases
        newReleases = [
            HomeTrack(
                id: "n1",
                title: "Fresh Start",
                artist: "NewArtist",
                coverURL: URL(string: "https://picsum.photos/seed/new1/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "n2",
                title: "Debut Single",
                artist: "Rising Star",
                coverURL: URL(string: "https://picsum.photos/seed/new2/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "n3",
                title: "First Light",
                artist: "Dawn",
                coverURL: URL(string: "https://picsum.photos/seed/new3/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "n4",
                title: "Genesis",
                artist: "Origin",
                coverURL: URL(string: "https://picsum.photos/seed/new4/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "n5",
                title: "Day One",
                artist: "Premiere",
                coverURL: URL(string: "https://picsum.photos/seed/new5/400"),
                audioURL: nil
            ),
        ]

        // Recently Played
        recentlyPlayed = [
            HomeTrack(
                id: "p1",
                title: "Yesterday's Jam",
                artist: "Nostalgia",
                coverURL: URL(string: "https://picsum.photos/seed/played1/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "p2",
                title: "On Repeat",
                artist: "LoopMaster",
                coverURL: URL(string: "https://picsum.photos/seed/played2/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "p3",
                title: "Favorite Song",
                artist: "Classic",
                coverURL: URL(string: "https://picsum.photos/seed/played3/400"),
                audioURL: nil
            ),
            HomeTrack(
                id: "p4",
                title: "Throwback",
                artist: "Retro",
                coverURL: URL(string: "https://picsum.photos/seed/played4/400"),
                audioURL: nil
            ),
        ]

        // Top Producers
        topProducers = [
            FollowingUser(
                id: "tp1",
                username: "Metro Boomin",
                profileImageURL: URL(string: "https://picsum.photos/seed/prod1/200")
            ),
            FollowingUser(
                id: "tp2",
                username: "Pharrell",
                profileImageURL: URL(string: "https://picsum.photos/seed/prod2/200")
            ),
            FollowingUser(
                id: "tp3",
                username: "Hit-Boy",
                profileImageURL: URL(string: "https://picsum.photos/seed/prod3/200")
            ),
            FollowingUser(
                id: "tp4",
                username: "Mustard",
                profileImageURL: URL(string: "https://picsum.photos/seed/prod4/200")
            ),
            FollowingUser(
                id: "tp5",
                username: "London",
                profileImageURL: URL(string: "https://picsum.photos/seed/prod5/200")
            ),
        ]
    }
}
