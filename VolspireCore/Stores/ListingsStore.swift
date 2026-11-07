//
//  ListingsStore.swift
//  Volspire
//
//

import DesignSystem
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

    /// One paged slice of the board (`get_listings_feed`, hottest first).
    struct ListingsPage {
        /// Server-side category filter; empty = every category.
        var categories: Set<String> = []
        var rows: [ApiListing] = []
        /// Defensive: flips on the first confirmed response (skeleton until then).
        var loaded = false
        var hasMore = false
        var isLoading = false
        /// The last next-page fetch failed — the footer offers a retry.
        var pageFailed = false
        /// The first page failed with nothing on screen — the tab shows
        /// "Couldn't load" + Try again instead of skeletons forever.
        var failed = false
        /// Bumped on every reset, so a reply to an older request is dropped.
        var generation = 0
    }

    /// The unfiltered board — the Listings tab, and the Collab tab's preview.
    private(set) var board = ListingsPage()
    /// The Listings tab with categories picked (kept apart so a filter never
    /// changes the Collab preview).
    private(set) var filtered = ListingsPage()

    var listings: [ApiListing] { board.rows }
    var listingsLoaded: Bool { board.loaded }
    static let pageSize = 20
    /// The user's saved listings (lazy — first open of the Saved toggle).
    private(set) var savedListings: [ApiListing] = []
    private(set) var savedListingsLoaded = false
    /// The saved load failed with none on screen (offline) — Try again.
    private(set) var savedListingsFailed = false
    /// Lowercased ids of saved listings — the viewer truth for rows
    /// (`viewerHasSaved` only comes back on the detail RPC).
    private(set) var savedListingIds: Set<String> = []

    // MARK: Dependencies

    private let service: SupabaseService

    // MARK: In-flight guards

    private var savingIds: Set<String> = []
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
        savedTask?.cancel()
        savedTask = nil
        savingIds = []
        board = ListingsPage(generation: board.generation + 1)
        filtered = ListingsPage(generation: filtered.generation + 1)
        savedListings = []
        savedListingsLoaded = false
        savedListingsFailed = false
        savedListingIds = []
    }

    // MARK: - Loads (both RPCs are uncached — always fresh)

    func loadListingsIfNeeded() async {
        guard !board.loaded, !board.isLoading else { return }
        await fetch(\.board, reset: true)
    }

    /// A user was blocked — drop their listings from the board + saved now.
    func removeContent(byUser userId: String) {
        let id = key(userId)
        mutateBoardRows { $0.removeAll { key($0.author.userId) == id } }
        savedListings.removeAll { key($0.author.userId) == id }
    }

    /// Pull-to-refresh / new content: the first page again (and the filtered
    /// slice's, when one is showing).
    func refreshListings() async {
        await fetch(\.board, reset: true)
        if !filtered.categories.isEmpty { await fetch(\.filtered, reset: true) }
    }

    /// The slice for a category selection (the board itself when none).
    func page(for categories: Set<String>) -> ListingsPage {
        if categories.isEmpty { return board }
        return filtered.categories == categories ? filtered : ListingsPage(categories: categories)
    }

    /// The Listings tab's filter changed — fetch that selection's first page.
    func setFilter(_ categories: Set<String>) async {
        guard !categories.isEmpty, filtered.categories != categories else { return }
        filtered = ListingsPage(categories: categories, generation: filtered.generation + 1)
        await fetch(\.filtered, reset: true)
    }

    /// The next page for a selection (the list footer calls this on scroll).
    func loadMore(categories: Set<String>) async {
        await fetch(categories.isEmpty ? \.board : \.filtered, reset: false)
    }

    /// One fetch path for both slices. A reset reloads the first page (rows
    /// stay up until it lands); otherwise the next page follows the last
    /// row's cursor, deduped by id.
    private func fetch(_ slice: ReferenceWritableKeyPath<ListingsStore, ListingsPage>, reset: Bool) async {
        let page = self[keyPath: slice]
        let cursor = reset ? nil : page.rows.last?.cursor
        guard reset || (!page.isLoading && page.hasMore && cursor != nil) else { return }
        let generation = reset ? page.generation + 1 : page.generation
        self[keyPath: slice].generation = generation
        self[keyPath: slice].isLoading = true
        self[keyPath: slice].pageFailed = false
        do {
            let rows = try await service.getListingsFeed(categories: page.categories, limit: Self.pageSize, cursor: cursor)
            guard self[keyPath: slice].generation == generation else { return }
            var next = self[keyPath: slice]
            if reset {
                next.rows = rows
            } else {
                let shown = Set(next.rows.map { key($0.listingId) })
                next.rows += rows.filter { !shown.contains(key($0.listingId)) }
            }
            next.hasMore = rows.count == Self.pageSize
            next.loaded = true
            next.failed = false
            next.isLoading = false
            self[keyPath: slice] = next
        } catch {
            debugLog("[ListingsStore] feed page: \(error)")
            guard self[keyPath: slice].generation == generation else { return }
            self[keyPath: slice].isLoading = false
            if !reset { self[keyPath: slice].pageFailed = true }
            else if self[keyPath: slice].rows.isEmpty { self[keyPath: slice].failed = true }
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
            savedListingsFailed = false
        } catch {
            debugLog("[ListingsStore] saved load: \(error)")
            savedListingsFailed = savedListings.isEmpty
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
        // Saving's own subtle signature (tick-tick); a faint tap to unsave.
        if save { Haptics.save() } else { Haptics.unsave() }
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
        mutateBoardRows { replaceRow(listing, in: &$0) }
        replaceRow(listing, in: &savedListings)
    }

    func setStatus(listingId: String, status: String) {
        adjustRow(listingId) { $0.status = status }
    }

    func listingDeleted(_ listingId: String) {
        let id = key(listingId)
        mutateBoardRows { $0.removeAll { key($0.listingId) == id } }
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
        mutateBoardRows { rows in
            if let i = rows.firstIndex(where: { key($0.listingId) == id }) { mutate(&rows[i]) }
        }
        if let i = savedListings.firstIndex(where: { key($0.listingId) == id }) { mutate(&savedListings[i]) }
    }

    /// Applies an edit to both board slices' rows.
    private func mutateBoardRows(_ body: (inout [ApiListing]) -> Void) {
        body(&board.rows)
        body(&filtered.rows)
    }

    private func adjustCount(_ listingId: String, _ mutate: (inout ApiListing) -> Void) {
        adjustRow(listingId, mutate)
    }

    private func replaceRow(_ listing: ApiListing, in rows: inout [ApiListing]) {
        guard let i = rows.firstIndex(where: { key($0.listingId) == key(listing.listingId) }) else { return }
        // A detail fetch has no feed-only fields — keep the row's paging
        // cursor (losing it on the last row would end the scroll) and views.
        var merged = listing
        merged.cursor = listing.cursor ?? rows[i].cursor
        merged.viewCount = listing.viewCount ?? rows[i].viewCount
        rows[i] = merged
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
