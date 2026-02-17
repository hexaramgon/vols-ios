//
//  SearchScreenViewModel.swift
//  Volspire
//
//

import Combine
import DesignSystem
import Foundation
import MediaLibrary
import Player
import SwiftUI

@Observable @MainActor
final class SearchScreenViewModel {
    var playerState: MediaPlayerState = .paused(media: .none)
    var playIndicatorSpectrum: [Float] = .init(repeating: 0, count: MediaPlayer.Const.frequencyBands)
    var isLoading: Bool = false
    var errorMessage: String?
    var searchResults: [Media] = []

    weak var mediaState: MediaState?
    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    private var searchTask: Task<Void, Never>?
    var cancellables = Set<AnyCancellable>()

    var searchText: String = "" {
        didSet {
            if searchText != oldValue {
                performSearch()
            }
        }
    }

    func play(_ track: Media) {
        guard let player else { return }
        player.play(track.id, of: searchResults.map(\.id))
    }
}

private extension SearchScreenViewModel {
    func performSearch() {
        searchTask?.cancel()

        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            errorMessage = nil
            isLoading = false
            return
        }

        errorMessage = nil
        searchTask = Task { @MainActor in
            do {
                isLoading = true
                try await Task.sleep(for: .milliseconds(500))

                guard !Task.isCancelled else { return }

                // Filter local tracks by search text
                let query = searchText.lowercased()
                let allTracks = mediaState?.allTracks() ?? []
                searchResults = allTracks.filter { track in
                    track.meta.title.lowercased().contains(query) ||
                        (track.meta.artist?.lowercased().contains(query) ?? false) ||
                        (track.meta.subtitle?.lowercased().contains(query) ?? false)
                }

                isLoading = false
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    searchResults = []
                    isLoading = false
                }
            }
        }
    }
}

extension SearchScreenViewModel: PlayerStateObserving {}
