//
//  LibraryStore.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Kingfisher
import MediaLibrary
import Observation
import Services
import SharedUtilities

/// Single source of truth for the signed-in user's library: saved (bookmarked)
/// tracks, their own uploads, and playlists. Injected via `.environment` from
/// `Dependencies`; every surface that renders or mutates library state (player
/// bookmark, media-list rows, Library tab, playlist sheets) reads and writes
/// THIS object, so a change made anywhere is visible everywhere instantly.
///
/// Store contract (applies to all domain stores):
/// - The store is the rendering truth; `APICache` is only a cold-load accelerator.
/// - Loads are lazy (`loadIfNeeded`), idempotent, and coalescing.
/// - Mutations are optimistic with per-id in-flight locks and rollback.
/// - All id keys are lowercased (Postgres UUIDs are lowercase; Swift's aren't).
@MainActor @Observable
final class LibraryStore {
    // MARK: Server state

    /// Saved tracks in server (`get_user_library`) order — drives the Library list.
    private(set) var savedTracks: [ApiUserLike] = []
    /// Lowercased ids of every saved track — THE bookmark truth for glyphs app-wide.
    private(set) var savedTrackIds: Set<String> = []
    /// The user's own uploads (from their profile) — Library "Uploads" section.
    private(set) var uploadedTracks: [ApiProfileTrack] = []
    /// The user's playlists — Library rail + playlist pickers.
    private(set) var playlists: [ApiPlaylist] = []
    /// Grouped releases per profile (lowercased user id → newest first) — the
    /// profile rail for any user; the signed-in user's entry also feeds the
    /// "Add to release" pickers. Every release mutation refetches the owner's
    /// list here, so rail, pickers and pages stay in step.
    private(set) var releasesByUser: [String: [ApiRelease]] = [:]
    private var releasesLoadedUsers: Set<String> = []
    private var releaseTasks: [String: Task<Void, Never>] = [:]
    /// The newest fetch per user — only it may write (a fetch started before a
    /// mutation must not land after the post-mutation refresh).
    private var releaseFetchTokens: [String: UUID] = [:]

    private(set) var loadState: LoadState = .idle
    private(set) var playlistsLoadState: LoadState = .idle

    /// How many saved tracks the Library page shows inline before "See all".
    /// Also bounds the cover prefetch so a large library doesn't warm hundreds
    /// of images for the ~10 rows actually on screen.
    let savedLimit = 10

    /// Registered so any surface can play a library track by id (set by Dependencies).
    weak var mediaState: MediaState?

    // MARK: Dependencies

    private let service: SupabaseService
    private let storage: StorageService
    private let auth: AuthManager

    // MARK: In-flight guards

    /// Per-track mutation lock: id → the state the in-flight RPC is writing.
    /// Blocks double-taps and tells server reconciles to keep their hands off.
    private var inFlightSaves: [String: Bool] = [:]
    private var loadTask: Task<Void, Never>?
    private var playlistsTask: Task<Void, Never>?
    /// Coalesced `get_user_library` refetch that materializes rows after saves.
    private var libraryRefetchTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init(service: SupabaseService, storage: StorageService, auth: AuthManager) {
        self.service = service
        self.storage = storage
        self.auth = auth

        // A just-published track should appear in Library "Uploads" without the
        // user pulling to refresh — the upload flow already invalidated the
        // profile cache, so this refetch is fresh.
        observers.append(NotificationCenter.default.addObserver(
            forName: .ownContentPosted, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A post can land in releases (upload-time pick / bulk release).
                if let me = self.auth.currentUserId, self.releasesLoaded(for: me) {
                    Task { await self.refreshMyReleases() }
                }
                guard case .loaded = self.loadState else { return }
                Task { await self.refreshUploads() }
            }
        })
    }

    /// Auth-boundary teardown: drop all per-user state so the next session starts clean.
    func resetForSignOut() {
        loadTask?.cancel()
        playlistsTask?.cancel()
        libraryRefetchTask?.cancel()
        loadTask = nil
        playlistsTask = nil
        libraryRefetchTask = nil
        inFlightSaves = [:]
        savedTracks = []
        savedTrackIds = []
        uploadedTracks = []
        playlists = []
        releaseTasks.values.forEach { $0.cancel() }
        releaseTasks = [:]
        releaseFetchTokens = [:]
        releasesByUser = [:]
        releasesLoadedUsers = []
        loadState = .idle
        playlistsLoadState = .idle
    }

    // MARK: - Loads

    /// Idempotent, coalescing first load — keep-alive tabs and the RootTabView
    /// warm-up can all call this in the same frame and share one fetch.
    func loadIfNeeded() async {
        if let loadTask { return await loadTask.value }
        // An earlier failure (nothing on screen) retries on the next visit.
        switch loadState {
        case .idle, .error: break
        case .loading, .loaded: return
        }
        loadState = .loading
        let task = Task {
            await showLastCached()
            await fetchAll()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// User-initiated refresh: bust the TTL caches first so the refetch can't
    /// serve the entry the user is deliberately refreshing past.
    func refresh() async {
        await service.invalidateLibraryCaches()
        if let me = auth.currentUserId {
            await service.invalidateProfile(userId: me)
        }
        await fetchAll()
    }

    /// Stale-first: the last saved list + uploads (even past their TTL, from
    /// the cache's disk mirror) paint at once instead of the skeleton;
    /// `fetchAll` then swaps fresh data in place. Only when BOTH are cached —
    /// half a library would read as "empty section".
    private func showLastCached() async {
        guard let me = auth.currentUserId,
              let saved = await service.lastUserLibrary(),
              let profile = await service.lastUserProfile(userId: me),
              // A cached empty library isn't shown — that waits for a live response.
              !(saved.isEmpty && profile.tracks.isEmpty)
        else { return }
        applyLibrary(saved)
        uploadedTracks = profile.tracks
        prefetchCovers()
        loadState = .loaded
        // Rows are tappable now — register their media before the refresh lands.
        for track in saved { await mediaState?.addTrack(media(for: track)) }
        for track in profile.tracks { await mediaState?.addTrack(media(upload: track)) }
    }

    private func fetchAll() async {
        // Concurrent so first paint waits on max(RTT), not the sum.
        async let savedOk = fetchSavedTracks()
        async let uploadsOk = fetchUploads()
        let (saved, uploads) = await (savedOk, uploadsOk)
        // A failed half with nothing (not even the stale copy) on screen is
        // an error, never an empty library — `loadIfNeeded` retries it.
        if saved && uploads || loadState == .loaded {
            loadState = .loaded
        } else {
            loadState = .error("Couldn't load your library")
        }
    }

    private func fetchSavedTracks() async -> Bool {
        do {
            let tracks = try await service.getUserLibrary()
            applyLibrary(tracks)
            prefetchCovers()
            for track in tracks { await mediaState?.addTrack(media(for: track)) }
            return true
        } catch {
            debugLog("[LibraryStore] saved tracks load failed: \(error)")
            return false
        }
    }

    /// Installs a server response as the saved list, then re-applies any deltas
    /// still in flight (an optimistic save may not be in this response yet).
    private func applyLibrary(_ tracks: [ApiUserLike]) {
        savedTracks = tracks
        var ids = Set(tracks.map { key($0.trackId) })
        for (id, target) in inFlightSaves {
            if target { ids.insert(id) } else { ids.remove(id) }
        }
        savedTrackIds = ids
    }

    private func fetchUploads() async -> Bool {
        guard let me = auth.currentUserId else { return true }
        do {
            let tracks = try await service.getUserProfile(userId: me).tracks
            uploadedTracks = tracks
            for track in tracks { await mediaState?.addTrack(media(upload: track)) }
            return true
        } catch {
            debugLog("[LibraryStore] uploads load failed: \(error)")
            return false
        }
    }

    /// Refetches just the uploads section (new post, edited track).
    func refreshUploads() async {
        guard let me = auth.currentUserId else { return }
        await service.invalidateProfile(userId: me)
        _ = await fetchUploads()
    }

    // MARK: - Saved state (THE save mutation path)

    func isSaved(_ trackId: String) -> Bool {
        savedTrackIds.contains(key(trackId))
    }

    /// Toggles relative to the store's current truth. Returns the settled state,
    /// or nil if nothing changed (in-flight duplicate or failed-and-rolled-back).
    @discardableResult
    func toggleSave(trackId: String) async -> Bool? {
        await setSaved(!isSaved(trackId), trackId: trackId)
    }

    @discardableResult
    func setSaved(_ save: Bool, trackId rawId: String) async -> Bool? {
        let id = key(rawId)
        guard inFlightSaves[id] == nil else { return nil }
        guard savedTrackIds.contains(id) != save else { return save }
        inFlightSaves[id] = save
        // Saving's own subtle signature (tick-tick); a faint tap to unsave.
        if save { Haptics.save() } else { Haptics.unsave() }

        // Optimistic: the id-set flips instantly (every bookmark glyph reads it).
        // Unsave also drops the row so the Library list reacts; save can't invent
        // an `ApiUserLike` row from a foreign DTO — the coalesced refetch below
        // materializes it with real fields.
        let removedIndex = savedTracks.firstIndex { key($0.trackId) == id }
        let removedRow = removedIndex.map { savedTracks[$0] }
        if save {
            savedTrackIds.insert(id)
        } else {
            savedTrackIds.remove(id)
            if let removedIndex { savedTracks.remove(at: removedIndex) }
        }

        do {
            if save { try await service.saveTrack(trackId: rawId) }
            else { try await service.unsaveTrack(trackId: rawId) }
            inFlightSaves[id] = nil
            if save, case .loaded = loadState { scheduleLibraryRefetch() }
            return save
        } catch {
            if save {
                savedTrackIds.remove(id)
            } else {
                savedTrackIds.insert(id)
                if let removedRow {
                    let at = min(removedIndex ?? 0, savedTracks.count)
                    savedTracks.insert(removedRow, at: at)
                }
            }
            inFlightSaves[id] = nil
            debugLog("[LibraryStore] setSaved(\(save)) failed: \(error)")
            return nil
        }
    }

    /// Server truth arriving from `get_track_interaction_status` (the player's
    /// per-track fetch). Keeps hands off ids with an optimistic write in flight.
    func reconcileSaved(trackId rawId: String, isSaved serverSaved: Bool) {
        let id = key(rawId)
        guard inFlightSaves[id] == nil else { return }
        if serverSaved {
            let inserted = savedTrackIds.insert(id).inserted
            // The set learned about a save made elsewhere (web, another device) —
            // materialize its Library row too, but only once the list exists.
            if inserted, case .loaded = loadState,
               !savedTracks.contains(where: { key($0.trackId) == id }) {
                scheduleLibraryRefetch()
            }
        } else if savedTrackIds.remove(id) != nil {
            savedTracks.removeAll { key($0.trackId) == id }
        }
    }

    /// Coalesced array rebuild after saves: rapid toggles collapse to one
    /// refetch. `saveTrack` already invalidated the `get_user_library` key.
    private func scheduleLibraryRefetch() {
        libraryRefetchTask?.cancel()
        libraryRefetchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            _ = await fetchSavedTracks()
        }
    }

    // MARK: - Playlists

    func loadPlaylistsIfNeeded() async {
        if let playlistsTask { return await playlistsTask.value }
        guard case .idle = playlistsLoadState else { return }
        playlistsLoadState = .loading
        let task = Task { await fetchPlaylists() }
        playlistsTask = task
        await task.value
        playlistsTask = nil
    }

    func refreshPlaylists() async {
        await fetchPlaylists()
    }

    private func fetchPlaylists() async {
        do {
            playlists = try await service.getUserPlaylists()
            playlistsLoadState = .loaded
        } catch {
            debugLog("[LibraryStore] playlists load failed: \(error)")
            playlistsLoadState.fail(error, ifEmpty: playlists.isEmpty)
        }
    }

    /// Creates a playlist (+ optional cover) and refreshes the list so every
    /// rail/picker shows it. Returns the new playlist's id.
    @discardableResult
    func createPlaylist(title: String, description: String? = nil, coverData: Data? = nil) async throws -> String {
        let playlistId = try await service.createPlaylist(title: title, description: description)
        // Cover is best-effort: the playlist is already created, so a failed
        // upload shouldn't fail the whole create.
        if let data = coverData, let me = service.currentUserId,
           let coverUrl = try? await service.uploadPlaylistCover(playlistId: playlistId, userId: me, imageData: data) {
            try? await service.updatePlaylist(playlistId: playlistId, coverUrl: coverUrl)
        }
        await refreshPlaylists()
        // Every "new playlist" path (Library, the Add-to sheets) lands here.
        Haptics.success()
        return playlistId
    }

    /// Optimistic: the playlist leaves the rail / pickers now; a refusal puts
    /// it back in place.
    func deletePlaylist(playlistId: String) async -> Bool {
        let index = playlists.firstIndex { $0.playlistId == playlistId }
        let removed = index.map { playlists[$0] }
        if let index { playlists.remove(at: index) }
        do {
            try await service.deletePlaylist(playlistId: playlistId)
            return true
        } catch {
            debugLog("[LibraryStore] deletePlaylist: \(error)")
            if let removed { playlists.insert(removed, at: min(index ?? 0, playlists.count)) }
            return false
        }
    }

    /// Adds a track to a playlist, patching the rail/picker count in place.
    func addTrack(toPlaylist playlistId: String, trackId: String) async -> Bool {
        do {
            try await service.addTrackToPlaylist(playlistId: playlistId, trackId: trackId)
        } catch {
            debugLog("[LibraryStore] addTrack(toPlaylist:): \(error)")
            return false
        }
        adjustTrackCount(playlistId, by: 1)
        return true
    }

    func removeTrack(fromPlaylist playlistId: String, trackId: String) async -> Bool {
        do {
            try await service.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId)
        } catch {
            debugLog("[LibraryStore] removeTrack(fromPlaylist:): \(error)")
            return false
        }
        adjustTrackCount(playlistId, by: -1)
        return true
    }

    /// A playlist's meta (title/description/cover) changed — refetch the list
    /// (uncached, one cheap RPC) rather than hand-patching every field.
    func playlistEdited() async {
        await refreshPlaylists()
    }

    /// Saves a playlist's name / description and (optionally) a new cover —
    /// the Library's hold-to-edit. Uploads the cover first, then
    /// `update_playlist`, then refreshes the shared list.
    func editPlaylist(playlistId: String, title: String, description: String, coverData: Data?) async throws {
        var coverUrl: String?
        if let coverData, let me = service.currentUserId {
            coverUrl = try await service.uploadPlaylistCover(playlistId: playlistId, userId: me, imageData: coverData)
        }
        try await service.updatePlaylist(playlistId: playlistId, title: title, description: description, coverUrl: coverUrl)
        await refreshPlaylists()
    }

    private func adjustTrackCount(_ playlistId: String, by delta: Int) {
        guard let i = playlists.firstIndex(where: { $0.playlistId == playlistId }) else { return }
        playlists[i].trackCount = max(0, (playlists[i].trackCount ?? 0) + delta)
    }

    // MARK: - Cross-domain events

    /// A track was deleted anywhere in the app — drop every copy we hold.
    func trackDeleted(_ rawId: String) {
        let id = key(rawId)
        savedTrackIds.remove(id)
        savedTracks.removeAll { key($0.trackId) == id }
        uploadedTracks.removeAll { key($0.id) == id }
    }

    /// A track's metadata changed — refetch uploads (the editor invalidated the
    /// profile cache), so title/cover edits show in Library.
    func trackEdited(_ rawId: String) async {
        await refreshUploads()
    }

    // MARK: - Media mapping (playback + covers)

    /// All saved tracks as `Media` (for the "See all" collection screen and
    /// play-with-queue).
    func savedMediaList() -> [Media] {
        savedTracks.map { media(for: $0) }
    }

    /// Resolved (full public URL) cover art for a saved track.
    /// `cover_url` / `audio_url` come back as bare `post-uploads` paths.
    func coverURL(for track: ApiUserLike) -> URL? {
        storage.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }
    }

    func coverURL(forUpload track: ApiProfileTrack) -> URL? {
        storage.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) }
    }

    /// Resolves a playlist's bare cover path to a public URL.
    func playlistCover(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    private func media(for track: ApiUserLike) -> Media {
        Media(
            id: MediaID(track.trackId),
            meta: MediaMeta(
                artwork: coverURL(for: track),
                title: track.title,
                artist: track.artist?.username,
                artistId: track.artist?.userId,
                audioURL: storage.trackMediaURL(track.audioUrl)
            )
        )
    }

    /// Uploads as `Media` — registered in MediaState so an upload's ID resolves
    /// if another surface plays it.
    private func media(upload track: ApiProfileTrack) -> Media {
        Media(
            id: MediaID(track.id),
            meta: MediaMeta(
                artwork: coverURL(forUpload: track),
                title: track.title,
                artist: nil,
                audioURL: storage.trackMediaURL(track.audioUrl)
            )
        )
    }

    /// Warm the image cache for the saved-track covers so they're already decoded
    /// when the rows reveal — otherwise each cover loads + fades in mid-entrance,
    /// out of sync with the section's slide.
    private func prefetchCovers() {
        let urls = savedTracks.prefix(savedLimit).compactMap { coverURL(for: $0) }
        // TrackListRow's default 50pt cover — the exact copy the rows ask for.
        ArtworkView.prefetch(Array(Set(urls)), side: 50)
    }

    // MARK: - Releases

    func releases(for userId: String) -> [ApiRelease] { releasesByUser[key(userId)] ?? [] }

    /// True once `get_user_releases` has answered for this profile (gates the
    /// rail's skeleton → content / hidden-when-empty).
    func releasesLoaded(for userId: String) -> Bool { releasesLoadedUsers.contains(key(userId)) }

    /// The signed-in user's releases (pickers, the upload flow).
    var myReleases: [ApiRelease] { auth.currentUserId.map { releases(for: $0) } ?? [] }

    func loadReleasesIfNeeded(userId: String) async {
        guard !releasesLoaded(for: userId) else { return }
        await loadReleases(userId: userId)
    }

    /// Fetches a profile's releases. Concurrent loads share one request,
    /// unless `fresh` (after a mutation): that starts a new fetch, and only the
    /// newest fetch writes. A failure keeps what's shown (skeleton until a
    /// first answer, per the defensive-empty-state rule); the next load retries.
    func loadReleases(userId: String, fresh: Bool = false) async {
        let k = key(userId)
        if !fresh, let task = releaseTasks[k] { return await task.value }
        let token = UUID()
        releaseFetchTokens[k] = token
        let task = Task { [service] in
            do {
                let rows = try await service.getUserReleases(userId: k)
                guard releaseFetchTokens[k] == token else { return }
                releasesByUser[k] = rows
                releasesLoadedUsers.insert(k)
            } catch {
                debugLog("[LibraryStore] releases(\(k)): \(error)")
            }
        }
        releaseTasks[k] = task
        await task.value
        if releaseFetchTokens[k] == token { releaseTasks[k] = nil }
    }

    func refreshMyReleases() async {
        guard let me = auth.currentUserId else { return }
        await loadReleases(userId: me, fresh: true)
    }

    /// Creates a release (+ optional cover, best-effort like playlists) with
    /// the given tracks in order. Returns the new release's id.
    @discardableResult
    func createRelease(
        title: String,
        description: String?,
        visibility: String,
        releaseDate: String?,
        trackIds: [String] = [],
        coverData: Data? = nil
    ) async throws -> String {
        let releaseId = try await service.createRelease(
            title: title, description: description, visibility: visibility,
            releaseDate: releaseDate, trackIds: trackIds
        )
        if let data = coverData, let me = service.currentUserId,
           let path = try? await service.uploadReleaseCover(releaseId: releaseId, userId: me, imageData: data) {
            try? await service.updateRelease(releaseId: releaseId, coverUrl: path)
        }
        await refreshMyReleases()
        return releaseId
    }

    func updateRelease(
        releaseId: String,
        title: String?,
        description: String?,
        visibility: String?,
        releaseDate: String?,
        clearReleaseDate: Bool,
        coverData: Data?
    ) async throws {
        var coverPath: String?
        if let data = coverData, let me = service.currentUserId {
            coverPath = try await service.uploadReleaseCover(releaseId: releaseId, userId: me, imageData: data)
        }
        try await service.updateRelease(
            releaseId: releaseId, title: title, description: description, visibility: visibility,
            coverUrl: coverPath, releaseDate: releaseDate, clearReleaseDate: clearReleaseDate
        )
        await refreshMyReleases()
    }

    /// Optimistic: the release leaves the rail now; a refusal refetches it.
    func deleteRelease(releaseId: String) async throws {
        if let me = auth.currentUserId {
            releasesByUser[key(me)]?.removeAll { key($0.releaseId) == key(releaseId) }
        }
        do {
            try await service.deleteRelease(releaseId: releaseId)
        } catch {
            await refreshMyReleases()
            throw error
        }
    }

    func addTracks(toRelease releaseId: String, trackIds: [String]) async throws {
        guard !trackIds.isEmpty else { return }
        try await service.addTracksToRelease(releaseId: releaseId, trackIds: trackIds)
        await refreshMyReleases()
    }

    func removeTrack(fromRelease releaseId: String, trackId: String) async throws {
        try await service.removeTrackFromRelease(releaseId: releaseId, trackId: trackId)
        await refreshMyReleases()
    }

    func reorderRelease(releaseId: String, trackIds: [String]) async throws {
        try await service.reorderRelease(releaseId: releaseId, trackIds: trackIds)
    }

    private func key(_ raw: String) -> String { raw.lowercased() }
}
