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
    /// Defensive: flips on a confirmed response only (skeleton until then).
    private(set) var listingsLoaded = false
    /// The user's saved listings (lazy — first open of the Saved toggle).
    private(set) var savedListings: [ApiListing] = []
    private(set) var savedListingsLoaded = false
    /// Lowercased ids of saved listings — the viewer truth for rows
    /// (`viewerHasSaved` only comes back on the detail RPC).
    private(set) var savedListingIds: Set<String> = []

    // MARK: Dependencies

    private let service: SupabaseService

    // MARK: In-flight guards

    private var savingIds: Set<String> = []
    private var listingsTask: Task<Void, Never>?
    private var savedTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(service: SupabaseService) {
        self.service = service

        // A just-posted listing should appear on the board without a pull;
        // block/unblock changes what the server returns for every read.
        observers.append(NotificationCenter.default.addObserver(
            forName: .ownContentPosted, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.listingsLoaded else { return }
                Task { await self.refreshListings() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .userBlockStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task {
                    if self.listingsLoaded { await self.refreshListings() }
                    if self.savedListingsLoaded { await self.refreshSaved() }
                }
            }
        })
    }

    func resetForSignOut() {
        listingsTask?.cancel()
        savedTask?.cancel()
        listingsTask = nil
        savedTask = nil
        savingIds = []
        listings = []
        listingsLoaded = false
        savedListings = []
        savedListingsLoaded = false
        savedListingIds = []
    }

    // MARK: - Loads (both RPCs are uncached — always fresh)

    func loadListingsIfNeeded() async {
        if let listingsTask { return await listingsTask.value }
        guard !listingsLoaded else { return }
        let task = Task { await fetchListings() }
        listingsTask = task
        await task.value
        listingsTask = nil
    }

    func refreshListings() async {
        await fetchListings()
    }

    private func fetchListings() async {
        do {
            listings = try await service.getListings(category: nil)
            listingsLoaded = true
        } catch {
            debugLog("[ListingsStore] listings load: \(error)")
        }
    }

    func loadSavedIfNeeded() async {
        if let savedTask { return await savedTask.value }
        guard !savedListingsLoaded else { return }
        let task = Task { await fetchSaved() }
        savedTask = task
        await task.value
        savedTask = nil
    }

    func refreshSaved() async {
        await fetchSaved()
    }

    private func fetchSaved() async {
        do {
            let rows = try await service.getSavedListings()
            savedListings = rows
            var ids = Set(rows.map { key($0.listingId) })
            for id in savingIds { ids.insert(id) } // keep optimistic saves visible
            savedListingIds = ids
            savedListingsLoaded = true
        } catch {
            debugLog("[ListingsStore] saved load: \(error)")
        }
    }

    // MARK: - Viewer save state

    func isSaved(_ listingId: String, fallback: Bool? = nil) -> Bool {
        savedListingIds.contains(key(listingId)) || (fallback ?? false)
    }

    /// THE listing-save path. Optimistically flips the id-set and inserts/
    /// removes the row in the Saved list, rolls back on failure. Returns the
    /// settled state, nil if nothing changed.
    @discardableResult
    func setSaved(_ save: Bool, listing: ApiListing) async -> Bool? {
        let id = key(listing.listingId)
        guard !savingIds.contains(id) else { return nil }
        savingIds.insert(id)
        defer { savingIds.remove(id) }

        let removedIndex = savedListings.firstIndex { key($0.listingId) == id }
        let removedRow = removedIndex.map { savedListings[$0] }
        if save {
            savedListingIds.insert(id)
            if removedIndex == nil { savedListings.insert(listing, at: 0) }
        } else {
            savedListingIds.remove(id)
            if let removedIndex { savedListings.remove(at: removedIndex) }
        }

        do {
            if save { try await service.saveListing(listingId: listing.listingId) }
            else { try await service.unsaveListing(listingId: listing.listingId) }
            adjustCount(listing.listingId) { $0.saveCount = max(0, ($0.saveCount ?? 0) + (save ? 1 : -1)) }
            return save
        } catch {
            if save {
                savedListingIds.remove(id)
                savedListings.removeAll { key($0.listingId) == id }
            } else {
                savedListingIds.insert(id)
                if let removedRow {
                    savedListings.insert(removedRow, at: min(removedIndex ?? 0, savedListings.count))
                }
            }
            debugLog("[ListingsStore] setSaved failed: \(error)")
            return nil
        }
    }

    // MARK: - Detail → board propagation

    /// A fresh detail fetch landed — sync its (possibly newer) status/counts
    /// into any board/saved copies of the same listing.
    func applyFresh(_ listing: ApiListing) {
        replaceRow(listing, in: &listings)
        replaceRow(listing, in: &savedListings)
    }

    func setStatus(listingId: String, status: String) {
        adjustRow(listingId) { $0.status = status }
    }

    func listingDeleted(_ listingId: String) {
        let id = key(listingId)
        listings.removeAll { key($0.listingId) == id }
        savedListings.removeAll { key($0.listingId) == id }
        savedListingIds.remove(id)
    }

    func listingResponded(_ listingId: String) {
        adjustCount(listingId) { $0.responseCount = ($0.responseCount ?? 0) + 1 }
    }

    func commentDelta(_ listingId: String, _ delta: Int) {
        adjustCount(listingId) { $0.commentCount = max(0, ($0.commentCount ?? 0) + delta) }
    }

    // MARK: - Helpers

    private func adjustRow(_ listingId: String, _ mutate: (inout ApiListing) -> Void) {
        let id = key(listingId)
        if let i = listings.firstIndex(where: { key($0.listingId) == id }) { mutate(&listings[i]) }
        if let i = savedListings.firstIndex(where: { key($0.listingId) == id }) { mutate(&savedListings[i]) }
    }

    private func adjustCount(_ listingId: String, _ mutate: (inout ApiListing) -> Void) {
        adjustRow(listingId, mutate)
    }

    private func replaceRow(_ listing: ApiListing, in rows: inout [ApiListing]) {
        guard let i = rows.firstIndex(where: { key($0.listingId) == key(listing.listingId) }) else { return }
        rows[i] = listing
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
