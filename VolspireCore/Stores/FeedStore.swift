//
//  FeedStore.swift
//  Volspire
//
//

import Foundation
import Kingfisher
import Observation
import Services
import SharedUtilities

/// Single source of truth for the Home content: the charts (popular /
/// short tracks / snippets), the paged Fresh-tracks and My Network feeds, the
/// role-filtered paged explore artists (Collab tab), the looking-for-collab
/// tracks, the More-artists card details and the Collab map's located
/// artists. Owning these here (rather than in the Home screen's view model)
/// gives mutations elsewhere in the app — upload, delete, edit, block — a
/// direct method to call, so the feed heals without notification-and-refetch
/// hops through a mounted HomeScreen. (The store still subscribes to the two
/// app-wide notifications itself, so the healing needs no view wiring.)
@MainActor @Observable
final class FeedStore {
    static let pageSize = 24

    // MARK: Server state

    private(set) var loadState: LoadState = .idle

    // Charts — the web's home buckets (`get_home_tracks`).
    private(set) var popularTracks: [HomeTrack] = []
    private(set) var demos: [HomeTrack] = []
    private(set) var samples: [HomeTrack] = []

    /// My Network releases (`get_following_feed`), endless.
    private(set) var followingTracks: [HomeTrack] = []
    private(set) var followingHasMore = true
    /// The last My Network load failed with nothing on screen.
    private(set) var followingFailed = false

    /// Collab tab artists (`get_explore_artists`), filtered by `artistRoles`.
    private(set) var artists: [ExploreArtistItem] = []
    private(set) var artistRoles: [String] = []
    private(set) var artistsHasMore = true
    /// Tracks flagged open for collab — the More-artists "Open for collab on" row.
    private(set) var collabTracks: [HomeTrack] = []
    /// Card details by lowercased user id.
    private(set) var artistDetails: [String: ArtistCardDetails] = [:]
    /// Open-to-collab artists with a mappable city, for `locationsRoles`.
    private(set) var artistLocations: [LocatedArtist] = []
    private(set) var locationsLoaded = false

    // Defensive flags: flip on a confirmed response only, so tabs show their
    // skeleton — never "Nothing here yet" — while a fetch is in flight.
    private(set) var followingLoaded = false
    private(set) var artistsLoaded = false
    /// A role change is refetching the list + map. The previous results stay
    /// on screen meanwhile (dimmed by the tab) instead of dropping to bones.
    private(set) var isRefilteringArtists = false

    // MARK: Dependencies

    private let service: SupabaseService
    private let storage: StorageService
    /// Artist rows seed the shared follow overlay (set by Dependencies).
    weak var social: SocialStore?

    // MARK: In-flight guards

    private var followingInFlight = false
    private var artistsInFlight = false
    /// Bumped on every role change / reset so a stale page can't land.
    private var artistsGeneration = 0
    private var locationsGeneration = 0
    private var locationsRolesKey: String?
    private var collabTracksLoaded = false
    private var detailsRequested: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    init(service: SupabaseService, storage: StorageService) {
        self.service = service
        self.storage = storage

        // The user published a track/listing → the charts may include it now.
        observers.append(NotificationCenter.default.addObserver(
            forName: .ownContentPosted, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, case .loaded = self.loadState else { return }
                Task { await self.refreshAfterOwnPost() }
            }
        })
        // Block/unblock changes what the server returns for every read — the
        // in-memory copies are stale until refetched.
        observers.append(NotificationCenter.default.addObserver(
            forName: .userBlockStateChanged, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.loadState != .idle else { return }
                Task { await self.refreshAfterBlockChange() }
            }
        })
    }

    func resetForSignOut() {
        loadState = .idle
        popularTracks = []
        demos = []
        samples = []
        followingTracks = []
        followingHasMore = true
        followingFailed = false
        artists = []
        artistRoles = []
        artistsHasMore = true
        collabTracks = []
        collabTracksLoaded = false
        artistDetails = [:]
        detailsRequested = []
        artistLocations = []
        locationsLoaded = false
        locationsRolesKey = nil
        followingLoaded = false
        artistsLoaded = false
        artistsGeneration += 1
        locationsGeneration += 1
    }

    // MARK: - Charts

    /// First load — the charts and the Collab tab's artists fetch concurrently.
    func loadInitial() async {
        async let home: Void = loadHomeData()
        async let artistsDone: Void = loadArtistsIfNeeded()
        async let collab: Void = loadCollabTracksIfNeeded()
        _ = await (home, artistsDone, collab)
    }

    /// Popular / Short tracks / Snippets only — the Library tab's lists —
    /// when nothing has loaded yet (Explore usually warmed them already).
    func loadHomeIfNeeded() async {
        switch loadState {
        case .idle, .error: await loadHomeData()
        case .loading, .loaded: break
        }
    }

    private func loadHomeData() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let response = try await service.getHomeTracks()
            popularTracks = mapTracks(response.popularTracks)
            demos = mapTracks(response.demos)
            samples = mapTracks(response.samples)
            loadState = .loaded
            prefetchCovers(popularTracks + demos + samples)
        } catch {
            loadState = .error(error.localizedDescription)
        }
    }

    /// Pull-to-refresh for the Collab and Library tabs: bypass the TTL cache.
    func refreshAll() async {
        await service.invalidateHomeCaches()
        loadState = .idle
        async let home: Void = loadHomeData()
        async let artistsDone: Void = reloadArtists()
        async let locations: Void = reloadLocations()
        _ = await (home, artistsDone, locations)
    }

    // MARK: - My Network (paged)

    func loadFollowingIfNeeded() async {
        guard !followingLoaded else { return }
        await reloadFollowing()
    }

    /// In-place refetch (pull / retry) — content stays up while it runs.
    func refreshFollowing() async {
        await service.invalidateHomeCaches()
        await reloadFollowing()
    }

    private func reloadFollowing() async {
        guard !followingInFlight else { return }
        followingInFlight = true
        defer { followingInFlight = false }
        do {
            let page = mapFeed(try await service.getFollowingFeedPage(limit: Self.pageSize, offset: 0))
            followingTracks = page
            followingHasMore = page.count == Self.pageSize
            followingLoaded = true
            followingFailed = false
            prefetchCovers(page)
        } catch {
            debugLog("[FeedStore] following: \(error)")
            if followingTracks.isEmpty { followingFailed = true }
        }
    }

    func loadMoreFollowing() async {
        guard followingLoaded, followingHasMore, !followingInFlight else { return }
        followingInFlight = true
        defer { followingInFlight = false }
        do {
            let page = mapFeed(try await service.getFollowingFeedPage(limit: Self.pageSize, offset: followingTracks.count))
            followingTracks = appendUnique(followingTracks, page)
            followingHasMore = page.count == Self.pageSize
            prefetchCovers(page)
        } catch { debugLog("[FeedStore] following more: \(error)") }
    }

    // MARK: - Collab artists (role-filtered, paged)

    func loadArtistsIfNeeded() async {
        guard !artistsLoaded else { return }
        await reloadArtists()
    }

    /// The role chips changed — restart the list (and the map) for the new set.
    func setArtistRoles(_ roles: [String]) async {
        let next = Array(Set(roles)).sorted()
        guard next != artistRoles else { return }
        artistRoles = next
        // Keep the current artists/pins up until the new set lands (paging is
        // blocked meanwhile by `artistsInFlight`).
        isRefilteringArtists = true
        async let list: Void = reloadArtists()
        async let map: Void = loadArtistLocations()
        _ = await (list, map)
        // A newer chip change owns the flag if the roles moved on.
        if artistRoles == next { isRefilteringArtists = false }
    }

    private func reloadArtists() async {
        artistsGeneration += 1
        let generation = artistsGeneration
        artistsInFlight = true
        defer { if generation == artistsGeneration { artistsInFlight = false } }
        do {
            let page = mapArtists(try await service.getExploreArtists(roles: artistRoles, limit: Self.pageSize, offset: 0))
            guard generation == artistsGeneration else { return }
            artists = page
            artistsHasMore = page.count == Self.pageSize
            artistsLoaded = true
            prefetch(page.compactMap(\.avatarURL))
        } catch { debugLog("[FeedStore] artists: \(error)") }
    }

    func loadMoreArtists() async {
        guard artistsLoaded, artistsHasMore, !artistsInFlight else { return }
        let generation = artistsGeneration
        artistsInFlight = true
        defer { if generation == artistsGeneration { artistsInFlight = false } }
        do {
            let page = mapArtists(try await service.getExploreArtists(roles: artistRoles, limit: Self.pageSize, offset: artists.count))
            guard generation == artistsGeneration else { return }
            var seen = Set(artists.map { $0.id.lowercased() })
            artists += page.filter { seen.insert($0.id.lowercased()).inserted }
            artistsHasMore = page.count == Self.pageSize
            prefetch(page.compactMap(\.avatarURL))
        } catch { debugLog("[FeedStore] artists more: \(error)") }
    }

    func loadCollabTracksIfNeeded() async {
        guard !collabTracksLoaded else { return }
        collabTracksLoaded = true
        do {
            collabTracks = mapFeed(try await service.getCollabTracks(limit: Self.pageSize, offset: 0))
        } catch {
            collabTracksLoaded = false
            debugLog("[FeedStore] collab tracks: \(error)")
        }
    }

    /// The looking-for-collab track of `artistId`, if they flagged one.
    func openCollabTrack(for artistId: String) -> HomeTrack? {
        let id = artistId.lowercased()
        return collabTracks.first { $0.artistId?.lowercased() == id }
    }

    /// Fetches card details for any of `ids` not yet requested, 20 at a time
    /// (web `useArtistDetails` page size).
    func loadArtistDetails(for ids: [String]) async {
        let missing = ids.map { $0.lowercased() }.filter { !detailsRequested.contains($0) }
        guard !missing.isEmpty else { return }
        missing.forEach { detailsRequested.insert($0) }
        for start in stride(from: 0, to: missing.count, by: 20) {
            let chunk = Array(missing[start ..< min(start + 20, missing.count)])
            do {
                let rows = try await service.getArtistDetails(ids: chunk)
                for (id, d) in rows {
                    artistDetails[id] = ArtistCardDetails(
                        location: Geo.resolve(d.location)?.name ?? d.location,
                        latestTrack: d.latestTrack.map(mapLatest)
                    )
                }
            } catch {
                chunk.forEach { detailsRequested.remove($0) }
                debugLog("[FeedStore] artist details: \(error)")
            }
        }
    }

    // MARK: - Collab map

    /// Open-to-collab artists (for the current roles) with a mappable city:
    /// the same `get_explore_artists` set (200), then their opt-in locations.
    func loadArtistLocations() async {
        let key = artistRoles.joined(separator: ",")
        guard locationsRolesKey != key || !locationsLoaded else { return }
        await reloadLocations()
    }

    /// The viewer's own map presence changed (open-to-collab / city saved in
    /// Edit Profile): refetch the map now if it was loaded, else just mark it
    /// stale so the next `loadArtistLocations` refetches. Keeps the current
    /// pins on screen meanwhile (no skeleton churn).
    func refreshLocationsAfterProfileChange() async {
        guard locationsLoaded else { locationsRolesKey = nil; return }
        await reloadLocations()
    }

    private func reloadLocations() async {
        let key = artistRoles.joined(separator: ",")
        locationsGeneration += 1
        let generation = locationsGeneration
        locationsRolesKey = key
        do {
            let found = mapArtists(try await service.getExploreArtists(roles: artistRoles, limit: 200, offset: 0))
            let rows = try await service.getOpenToCollabLocations(ids: found.map(\.id))
            guard generation == locationsGeneration else { return }
            let locationOf = Dictionary(rows.map { ($0.userId.lowercased(), $0.location) }, uniquingKeysWith: { a, _ in a })
            artistLocations = found.compactMap { a in
                guard let place = Geo.resolve(locationOf[a.id.lowercased()] ?? nil) else { return nil }
                return LocatedArtist(artist: a, place: place)
            }
            locationsLoaded = true
        } catch {
            if generation == locationsGeneration { locationsRolesKey = nil }
            debugLog("[FeedStore] artist locations: \(error)")
        }
    }

    // MARK: - Cross-domain events

    /// After the user posts content: refetch the charts in place, without any
    /// loading-state churn (runs off the store's own subscription).
    func refreshAfterOwnPost() async {
        await service.invalidateHomeCaches()
        if let response = try? await service.getHomeTracks() {
            popularTracks = mapTracks(response.popularTracks)
            demos = mapTracks(response.demos)
            samples = mapTracks(response.samples)
            prefetchCovers(popularTracks + demos + samples)
            loadState = .loaded
        }
    }

    /// Refetches every loaded surface after a block/unblock — only re-runs
    /// what had loaded.
    func refreshAfterBlockChange() async {
        let hadFollowing = followingLoaded
        let hadLocations = locationsLoaded
        loadState = .idle
        async let home: Void = loadHomeData()
        async let artistsDone: Void = reloadArtists()
        _ = await (home, artistsDone)
        if hadFollowing { await reloadFollowing() }
        if hadLocations { await reloadLocations() }
    }

    /// A track was deleted anywhere in the app — strip every copy so the rails
    /// can't offer a dead play.
    func removeTrack(_ trackId: String) {
        let id = trackId.lowercased()
        popularTracks.removeAll { $0.id.lowercased() == id }
        demos.removeAll { $0.id.lowercased() == id }
        samples.removeAll { $0.id.lowercased() == id }
        followingTracks.removeAll { $0.id.lowercased() == id }
        collabTracks.removeAll { $0.id.lowercased() == id }
    }

    /// A track's metadata changed — refetch the charts in place.
    func trackEdited(_ trackId: String) async {
        await refreshAfterOwnPost()
    }

    // MARK: - Mapping + prefetch

    private func url(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    private func mapTracks(_ apiTracks: [ApiHomeTrack]?) -> [HomeTrack] {
        // cover_url / audio_url come back as bare `post-uploads` paths — resolve them.
        apiTracks?.map { track in
            HomeTrack(
                id: track.id,
                title: track.title,
                artist: track.artist ?? "unknown",
                coverURL: url(track.coverUrl),
                audioURL: url(track.audioUrl),
                streams: track.streams,
                durationMs: track.durationMs
            )
        } ?? []
    }

    private func mapFeed(_ apiTracks: [ApiFeedTrack]) -> [HomeTrack] {
        apiTracks.map { t in
            HomeTrack(
                id: t.id,
                title: t.title,
                artist: t.artist ?? "unknown",
                coverURL: url(t.coverUrl),
                audioURL: url(t.audioUrl),
                streams: t.streams,
                durationMs: t.durationMs,
                artistId: t.artistId,
                artistAvatarURL: url(t.artistProfileImageUrl),
                genre: t.genre,
                hasVisual: t.hasVisual ?? false,
                lookingForCollab: t.lookingForCollab ?? false
            )
        }
    }

    private func mapLatest(_ t: ApiArtistLatestTrack) -> HomeTrack {
        HomeTrack(
            id: t.trackId,
            title: t.title,
            artist: "",
            coverURL: url(t.coverUrl),
            audioURL: url(t.audioUrl),
            streams: t.streams,
            durationMs: t.durationMs,
            artistId: t.createdBy,
            genre: t.genre,
            hasVisual: t.hasVisual ?? false,
            createdAt: t.createdAt
        )
    }

    func mapArtists(_ items: [ApiExploreArtist]) -> [ExploreArtistItem] {
        items.map {
            // Seed the shared follow overlay (gap-fill only — this RPC is
            // cached and must not clobber fresher local knowledge).
            social?.seedFollow(userId: $0.userId, isFollowing: $0.isFollowing ?? false)
            return ExploreArtistItem(
                id: $0.userId,
                username: $0.username ?? "unknown",
                avatarURL: $0.profileImageUrl.flatMap { URL(string: $0) },
                monthlyListeners: $0.monthlyListeners ?? 0,
                followersCount: $0.followersCount ?? 0,
                tags: $0.tags ?? [],
                isFollowing: $0.isFollowing ?? false
            )
        }
    }

    private func appendUnique(_ existing: [HomeTrack], _ page: [HomeTrack]) -> [HomeTrack] {
        var seen = Set(existing.map(\.id))
        return existing + page.filter { seen.insert($0.id).inserted }
    }

    /// Warms the image cache for upcoming covers so they don't fetch+decode
    /// on-demand mid-scroll. Kingfisher skips anything already cached.
    private func prefetchCovers(_ tracks: [HomeTrack]) {
        prefetch(tracks.compactMap(\.coverURL))
    }

    private func prefetch(_ urls: [URL]) {
        let unique = Array(Set(urls))
        guard !unique.isEmpty else { return }
        ImagePrefetcher(urls: unique).start()
    }
}
