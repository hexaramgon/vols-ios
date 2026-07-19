//
//  MarketplaceViewModel.swift
//  Volspire
//
//  Loads the marketplace browse catalog (`get_explore_data`) — public sound
//  packs + services — mirroring the web app's marketplace view.
//

import Foundation
import Kingfisher
import Observation
import Services
import SharedUtilities

@Observable @MainActor
final class MarketplaceViewModel {
    enum Category: String, CaseIterable, Hashable { case all = "All", packs = "Packs", services = "Services" }

    enum Listing: Identifiable {
        case pack(ApiMarketplacePack)
        case service(ApiMarketplaceService)
        case collab(ApiListing)
        var id: String {
            switch self {
            case let .pack(p): "pack-\(p.id)"
            case let .service(s): "svc-\(s.id)"
            case let .collab(l): "collab-\(l.id)"
            }
        }
    }

    var packs: [ApiMarketplacePack] = []
    var services: [ApiMarketplaceService] = []
    /// Collab-board listings, also surfaced in the "All Listings" browse grid
    /// (greyed, like the web). Loaded once with no category filter.
    var collabListings: [ApiListing] = []
    var loadingState: LoadState = .idle
    var searchText = ""
    var category: Category = .all
    /// Active browse sub-filter — a pack/service type, or "free" / "budget".
    var activeFilter: String?

    /// Collab board ("listings" section). When `showBoard` is true the content
    /// area swaps from the browse grid to the collab-board feed.
    var showBoard = false
    /// Server-side sub-filter for the board; nil = all categories.
    var boardCategory: String?
    var boardListings: [ApiListing] = []
    var boardState: LoadState = .idle

    private let service: SupabaseService
    private let storage: StorageService

    init(service: SupabaseService = SupabaseService(), storage: StorageService = StorageService()) {
        self.service = service
        self.storage = storage
    }

    var isEmpty: Bool { packs.isEmpty && services.isEmpty }

    func load() async {
        if isEmpty { loadingState = .loading }
        // Fetch collab listings alongside packs/services; best-effort, so a
        // failure here never blocks the browse grid.
        async let collabTask = service.getListings(category: nil)
        do {
            let data = try await service.getExploreData()
            packs = data.packs ?? []
            services = data.services ?? []
            loadingState = .loaded
        } catch {
            debugLog("[MarketplaceVM] load: \(error)")
            if isEmpty { loadingState = .error(error.localizedDescription) }
        }
        collabListings = (try? await collabTask) ?? collabListings
        prefetchCovers()
    }

    func refresh() async { await load() }

    /// Warms the cache for the grid's pack/service covers so they don't
    /// fetch+decode on-demand mid-scroll.
    private func prefetchCovers() {
        let urls = (packs.map { cover($0.coverUrl) } + services.map { cover($0.coverUrl) }).compactMap { $0 }
        guard !urls.isEmpty else { return }
        ImagePrefetcher(urls: Array(Set(urls))).start()
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var filteredPacks: [ApiMarketplacePack] {
        guard category != .services else { return [] }
        return packs.filter { pack in
            if !query.isEmpty {
                let hit = pack.name.lowercased().contains(query) || (pack.creator?.username?.lowercased().contains(query) ?? false)
                if !hit { return false }
            }
            return matchesFilter(price: pack.price, type: pack.packType)
        }
    }

    var filteredServices: [ApiMarketplaceService] {
        guard category != .packs else { return [] }
        return services.filter { service in
            if !query.isEmpty {
                let hit = service.title.lowercased().contains(query) || (service.artist?.username?.lowercased().contains(query) ?? false)
                if !hit { return false }
            }
            return matchesFilter(price: service.price, type: service.serviceType)
        }
    }

    /// Applies the active sub-filter to one item's price/type.
    private func matchesFilter(price: Double?, type: String?) -> Bool {
        guard let f = activeFilter else { return true }
        switch f {
        case "free": return (price ?? 0) <= 0
        case "budget": return (price ?? 0) <= 50
        default: return type == f
        }
    }

    /// Sub-filter chips for the active browse category (mirrors the web).
    var filterChips: [(label: String, value: String)] {
        var chips: [(label: String, value: String)] = []
        if category == .all || category == .packs {
            chips.append((label: "Free", value: "free"))
            for t in ["Drum Kit", "Sample Pack", "Preset Pack", "MIDI Pack", "Plugin"] {
                chips.append((label: t, value: t))
            }
        }
        if category == .all || category == .services {
            chips.append((label: "Under $50", value: "budget"))
            for t in ["Mixing", "Mastering", "Production", "Vocal Tuning", "Songwriting", "Sound Design"]
            where !chips.contains(where: { $0.value == t }) {
                chips.append((label: t, value: t))
            }
        }
        return chips
    }

    /// "All" interleaves packs + services + collab listings; a single kind otherwise.
    var listings: [Listing] {
        switch category {
        case .packs: return filteredPacks.map(Listing.pack)
        case .services: return filteredServices.map(Listing.service)
        case .all:
            return interleave(
                filteredPacks.map(Listing.pack),
                filteredServices.map(Listing.service),
                filteredCollab.map(Listing.collab)
            )
        }
    }

    /// Collab listings for the "All" browse grid: search-filtered, and hidden
    /// when a price/type sub-filter is active (collab posts have neither).
    var filteredCollab: [ApiListing] {
        guard category == .all, activeFilter == nil else { return [] }
        guard !query.isEmpty else { return collabListings }
        return collabListings.filter(collabMatchesQuery)
    }

    /// Round-robin merge so the grid shows a balanced mix of each kind.
    private func interleave(_ groups: [Listing]...) -> [Listing] {
        var out: [Listing] = []
        let maxCount = groups.map(\.count).max() ?? 0
        for i in 0 ..< maxCount {
            for g in groups where i < g.count { out.append(g[i]) }
        }
        return out
    }

    /// Resolves a bare `post-uploads` cover path to a public URL.
    func cover(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    // MARK: - Collab board

    /// Loads the collab-board feed for the current `boardCategory` (server-side).
    func loadBoard() async {
        if boardListings.isEmpty { boardState = .loading }
        do {
            boardListings = try await service.getListings(category: boardCategory)
            boardState = .loaded
        } catch {
            debugLog("[MarketplaceVM] loadBoard: \(error)")
            if boardListings.isEmpty { boardState = .error(error.localizedDescription) }
        }
    }

    /// Switches the board sub-filter and refetches.
    func selectBoardCategory(_ id: String?) async {
        guard boardCategory != id else { return }
        boardCategory = id
        boardListings = []
        boardState = .loading
        await loadBoard()
    }

    /// Board listings after the shared search bar's client-side text filter.
    var filteredBoardListings: [ApiListing] {
        guard !query.isEmpty else { return boardListings }
        return boardListings.filter(collabMatchesQuery)
    }

    /// Matches a collab listing against the shared search query (title, body,
    /// author, tags). Shared by the board feed and the "All Listings" grid.
    private func collabMatchesQuery(_ l: ApiListing) -> Bool {
        l.title.lowercased().contains(query)
            || (l.description?.lowercased().contains(query) ?? false)
            || l.author.username.lowercased().contains(query)
            || (l.tags?.contains { $0.lowercased().contains(query) } ?? false)
    }
}
