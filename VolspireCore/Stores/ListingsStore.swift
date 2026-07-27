//
//  ListingsStore.swift
//  Volspire
//
//

import Foundation
import Observation
import Services
import SharedUtilities

/// Single source of truth for the collab board: the public listings feed and
/// the user's saved listings. The Home Collab tab, the All-tab rail, and the
/// listing detail screen all render from and mutate this one object, so a
/// save/close/response made in the detail is instantly reflected on the board.
@MainActor @Observable
final class ListingsStore {
    // MARK: Server state

    /// The public board feed.
    private(set) var listings: [ApiListing] = []
    private(set) var listingsLoadState: LoadState = .idle
    /// The user's saved listings.
    private(set) var savedListings: [ApiListing] = []
    private(set) var savedLoadState: LoadState = .idle
    /// Lowercased ids of saved listings — the viewer truth for board rows
    /// (`viewerHasSaved` only comes back on the detail RPC).
    private(set) var savedListingIds: Set<String> = []

    // MARK: Dependencies

    private let service: SupabaseService

    init(service: SupabaseService) {
        self.service = service
    }

    func resetForSignOut() {
        listings = []
        listingsLoadState = .idle
        savedListings = []
        savedLoadState = .idle
        savedListingIds = []
    }
}
