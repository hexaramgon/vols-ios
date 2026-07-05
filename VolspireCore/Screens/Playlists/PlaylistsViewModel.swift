//
//  PlaylistsViewModel.swift
//  Volspire
//
//  Loads the signed-in user's playlists (`get_user_playlists`) for the Library
//  rail, and creates new ones (`create_playlist`).
//

import Foundation
import Observation
import Services

@Observable @MainActor
final class PlaylistsViewModel {
    var playlists: [ApiPlaylist] = []
    var isLoading = false
    /// The last load got no response (used as an offline indicator).
    var loadFailed = false
    var showCreate = false
    var newTitle = ""
    var newDescription = ""
    var newCoverData: Data?
    var isCreating = false

    private let service: SupabaseService
    private let storage: StorageService

    init(service: SupabaseService = SupabaseService(), storage: StorageService = StorageService()) {
        self.service = service
        self.storage = storage
    }

    func load() async {
        if playlists.isEmpty { isLoading = true }
        do {
            playlists = try await service.getUserPlaylists()
            loadFailed = false
        } catch {
            print("[PlaylistsVM] load: \(error)")
            loadFailed = true
        }
        isLoading = false
    }

    func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating else { return }
        isCreating = true
        do {
            let desc = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let playlistId = try await service.createPlaylist(title: title, description: desc.isEmpty ? nil : desc)
            // Cover is best-effort: the playlist is already created, so a failed
            // upload shouldn't fail the whole create.
            if let data = newCoverData, let me = service.currentUserId,
               let coverUrl = try? await service.uploadPlaylistCover(playlistId: playlistId, userId: me, imageData: data) {
                try? await service.updatePlaylist(playlistId: playlistId, coverUrl: coverUrl)
            }
            newTitle = ""
            newDescription = ""
            newCoverData = nil
            showCreate = false
            playlists = (try? await service.getUserPlaylists()) ?? playlists
        } catch {
            print("[PlaylistsVM] create: \(error)")
        }
        isCreating = false
    }

    /// Resolves a bare cover path to a public URL.
    func cover(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }
}
