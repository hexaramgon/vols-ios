//
//  FeedStore.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SharedUtilities

/// Single source of truth for the Home content rails and feeds (popular /
/// demos / samples / explore feed / following) and the explore artists list.
/// Owning these here (rather than in the Home screen's view model) gives
/// mutations elsewhere in the app — upload, delete, edit, block — a direct
/// method to call, so the feed heals without notification-and-refetch hops.
@MainActor @Observable
final class FeedStore {
    // MARK: Server state (populated in Phase 7 — Home rails move here)

    private(set) var popularTracks: [HomeTrack] = []
    private(set) var demos: [HomeTrack] = []
    private(set) var samples: [HomeTrack] = []
    private(set) var feedTracks: [HomeTrack] = []
    private(set) var followingTracks: [HomeTrack] = []
    private(set) var artists: [ExploreArtistItem] = []
    private(set) var loadState: LoadState = .idle

    /// First five popular tracks — the featured carousel.
    var featuredTracks: [HomeTrack] { Array(popularTracks.prefix(5)) }

    // MARK: Dependencies

    private let service: SupabaseService
    private let storage: StorageService

    init(service: SupabaseService, storage: StorageService) {
        self.service = service
        self.storage = storage
    }

    func resetForSignOut() {
        popularTracks = []
        demos = []
        samples = []
        feedTracks = []
        followingTracks = []
        artists = []
        loadState = .idle
    }
}
