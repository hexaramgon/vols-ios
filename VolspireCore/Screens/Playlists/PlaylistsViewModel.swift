//
//  PlaylistsViewModel.swift
//  Volspire
//
//  The "New Playlist" form state (shared by the Library rail and the Playlists
//  grid). The playlists themselves live in `LibraryStore`; creation routes
//  through it so every rail/picker sees the new playlist immediately.
//

import Foundation
import Observation
import SharedUtilities

@Observable @MainActor
final class PlaylistsViewModel {
    var showCreate = false
    var newTitle = ""
    var newDescription = ""
    var newCoverData: Data?
    var isCreating = false

    /// The shared library store — assigned by the presenting screen's `.task`.
    weak var library: LibraryStore?

    func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreating, let library else { return }
        isCreating = true
        do {
            let desc = newDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            try await library.createPlaylist(
                title: title,
                description: desc.isEmpty ? nil : desc,
                coverData: newCoverData
            )
            newTitle = ""
            newDescription = ""
            newCoverData = nil
            showCreate = false
        } catch {
            debugLog("[PlaylistsVM] create: \(error)")
        }
        isCreating = false
    }
}
