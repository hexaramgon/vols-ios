//
//  LibraryStore.swift
//  Volspire
//
//

import Foundation
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

    private(set) var loadState: LoadState = .idle
    private(set) var playlistsLoadState: LoadState = .idle
    /// The last load got no response (used as an offline indicator).
    private(set) var loadFailed = false

    // MARK: Dependencies

    private let service: SupabaseService
    private let auth: AuthManager

    init(service: SupabaseService, auth: AuthManager) {
        self.service = service
        self.auth = auth
    }

    /// Auth-boundary teardown: drop all per-user state so the next session starts clean.
    func resetForSignOut() {
        savedTracks = []
        savedTrackIds = []
        uploadedTracks = []
        playlists = []
        loadState = .idle
        playlistsLoadState = .idle
        loadFailed = false
    }
}
