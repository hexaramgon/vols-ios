//
//  PlaylistDetailViewModel.swift
//  Volspire
//
//  Loads a single playlist (`get_playlist`), plays its tracks through the shared
//  media player, and manages tracks/deletion for the owner.
//

import Combine
import Foundation
import MediaLibrary
import Observation
import Player
import Services

@Observable @MainActor
final class PlaylistDetailViewModel {
    enum LoadState: Equatable { case loading, loaded, error(String) }

    var detail: ApiPlaylistDetail?
    var state: LoadState = .loading
    var playerState: MediaPlayerState = .paused(media: .none)

    /// Edit sheet state (name, description, and an optionally picked new cover).
    var showEdit = false
    var editTitle = ""
    var editDescription = ""
    var pickedCoverData: Data?
    var isSaving = false

    let playlistId: String
    var currentUserId: String?
    weak var mediaState: MediaState?
    weak var player: MediaPlayer? {
        didSet { observeMediaPlayerState() }
    }

    var cancellables = Set<AnyCancellable>()
    private let service: SupabaseService
    private let storage: StorageService

    init(playlistId: String, service: SupabaseService = SupabaseService(), storage: StorageService = StorageService()) {
        self.playlistId = playlistId
        self.service = service
        self.storage = storage
    }

    var tracks: [ApiPlaylistTrack] { detail?.tracks ?? [] }

    /// Playlist tracks as playable media for the reused `MediaCollectionScreen`.
    var mediaItems: [Media] { tracks.map { media(for: $0) } }
    var isOwner: Bool {
        // `currentUserId` is an uppercase uuidString; the DB returns lowercase —
        // compare case-insensitively (same gotcha as NowPlayingCommentsModel.isOwn).
        guard let owner = detail?.ownerId, let me = currentUserId else { return false }
        return owner.caseInsensitiveCompare(me) == .orderedSame
    }

    func load() async {
        do {
            let detail = try await service.getPlaylist(playlistId: playlistId)
            self.detail = detail
            for track in detail.tracks ?? [] { await mediaState?.addTrack(media(for: track)) }
            state = .loaded
        } catch {
            print("[PlaylistDetailVM] load: \(error)")
            if detail == nil { state = .error(error.localizedDescription) }
        }
    }

    func play(_ track: ApiPlaylistTrack) {
        guard let player else { return }
        let media = media(for: track)
        Task { await mediaState?.addTrack(media) }
        player.play(media.id, of: tracks.map { MediaID($0.trackId) })
    }

    func playAll() {
        guard let first = tracks.first else { return }
        play(first)
    }

    func shuffle() {
        guard let player, !tracks.isEmpty else { return }
        let order = tracks.map { MediaID($0.trackId) }.shuffled()
        if let first = order.first { player.play(first, of: order) }
    }

    /// Removes a track from this playlist, then reloads so the list reflects it.
    func removeTrack(trackId: String) async {
        do {
            try await service.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId)
            await load()
        } catch {
            print("[PlaylistDetailVM] removeTrack: \(error)")
        }
    }

    /// Opens the edit sheet seeded with the playlist's current title and description.
    func startEditing() {
        editTitle = detail?.title ?? ""
        editDescription = detail?.description ?? ""
        pickedCoverData = nil
        showEdit = true
    }

    /// Uploads a newly picked cover (if any), persists title/description/cover via
    /// `update_playlist`, then reloads the detail.
    func saveEdit() async {
        let title = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isSaving else { return }
        isSaving = true
        do {
            var coverUrl: String?
            if let data = pickedCoverData, let me = currentUserId {
                coverUrl = try await service.uploadPlaylistCover(playlistId: playlistId, userId: me, imageData: data)
            }
            try await service.updatePlaylist(
                playlistId: playlistId,
                title: title,
                description: editDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                coverUrl: coverUrl
            )
            pickedCoverData = nil
            showEdit = false
            await load()
        } catch {
            print("[PlaylistDetailVM] saveEdit: \(error)")
        }
        isSaving = false
    }

    func deletePlaylist() async -> Bool {
        do {
            try await service.deletePlaylist(playlistId: playlistId)
            return true
        } catch {
            print("[PlaylistDetailVM] delete: \(error)")
            return false
        }
    }

    func cover(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    private func media(for track: ApiPlaylistTrack) -> Media {
        Media(
            id: MediaID(track.trackId),
            meta: MediaMeta(
                artwork: cover(track.coverUrl),
                title: track.title,
                artist: track.artistUsername,
                audioURL: storage.resolveTrackUrl(track.audioUrl).flatMap { URL(string: $0) }
            )
        )
    }
}

extension PlaylistDetailViewModel: PlayerStateObserving {}
