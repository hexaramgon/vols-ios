//
//  MediaListScreenViewModel.swift
//  Volspire
//
//

import Combine
import DesignSystem
import MediaLibrary
import Observation
import Player
import Services
import SharedUtilities
import SwiftUI

@Observable @MainActor
class MediaListScreenViewModel {
    weak var mediaState: MediaState?
    let items: [Media]
    let listMeta: MediaList.Meta?
    var playerState: MediaPlayerState = .paused(media: .none)
    var cancellables = Set<AnyCancellable>()

    /// Per-track save state for the row bookmark buttons.
    private let supabaseService = SupabaseService()
    private let storageService = StorageService()
    var savedTrackIDs: Set<String> = []
    private var savingTrackIDs: Set<String> = []

    /// The signed-in user's playlists, for the track 3-dot "Add to playlist" picker.
    var playlists: [ApiPlaylist] = []

    weak var player: MediaPlayer? {
        didSet {
            observeMediaPlayerState()
        }
    }

    /// Cover-derived palette for the hero mesh (empty → neutral fallback).
    var heroColors: [Color] = []

    /// The cover used for the hero + palette: explicit list cover, else first track's.
    var artwork: URL? { listMeta?.artwork ?? items.first?.meta.artwork }

    init(items: [Media], listMeta: MediaList.Meta?) {
        self.items = items
        self.listMeta = listMeta
    }

    /// Extracts the cover's dominant palette for the hero mesh. Runs on the VM's
    /// MainActor so the result lands on-main (a View's async `@State` write can
    /// resume off-main and get dropped). Retries briefly while the artwork view
    /// warms Kingfisher's cache — important for a just-uploaded cover.
    func loadHeroColors() async {
        guard let url = artwork else { return }
        for _ in 0 ..< 5 {
            if let colors = await url.image?
                .dominantColorFrequencies(with: .fair)?
                .map({ Color(uiColor: $0.color) }), !colors.isEmpty {
                withAnimation(.easeInOut(duration: 0.6)) { heroColors = colors }
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    func onSelect(media: MediaID) {
        guard let player else { return }
        player.play(media, of: items.map(\.id))
    }

    func onPlay() {
        guard let player, let item = items.first else { return }
        player.play(item.id, of: items.map(\.id))
    }

    func onShuffle() {
        guard let player, !items.isEmpty else { return }
        // Random starting track + player-level shuffle: the queue keeps its real
        // order underneath, so toggling shuffle off in the player restores it.
        let ids = items.map(\.id)
        guard let start = ids.randomElement() else { return }
        player.setShuffle(true)
        player.play(start, of: ids)
    }

    /// Register every row's media in the shared MediaState so playback can resolve
    /// its audio URL. The caller builds `items` with full meta, but nothing else
    /// guarantees they're registered — e.g. the Home "See all", where a track is
    /// only added to MediaState on a direct tap, so tapping it here would no-op.
    func registerItems() async {
        guard let mediaState else { return }
        for item in items { await mediaState.addTrack(item) }
    }

    func isSaved(_ id: MediaID) -> Bool { savedTrackIDs.contains(id.value) }

    /// Saves (or unsaves) a single track. Optimistically flips the bookmark so
    /// the tap feels instant, rolling back on failure.
    func toggleSave(_ id: MediaID) async {
        let key = id.value
        guard !savingTrackIDs.contains(key) else { return }
        savingTrackIDs.insert(key)
        let willSave = !savedTrackIDs.contains(key)
        if willSave { Haptics.success() } else { Haptics.impact(.light) }
        if willSave { savedTrackIDs.insert(key) } else { savedTrackIDs.remove(key) }
        do {
            if willSave { try await supabaseService.saveTrack(trackId: key) }
            else { try await supabaseService.unsaveTrack(trackId: key) }
        } catch {
            if willSave { savedTrackIDs.remove(key) } else { savedTrackIDs.insert(key) }
            debugLog("[MediaListVM] toggleSave failed: \(error)")
        }
        savingTrackIDs.remove(key)
    }

    // MARK: - Track 3-dot actions

    /// Loads the signed-in user's playlists for the "Add to playlist" picker.
    func loadPlaylists() async {
        playlists = (try? await supabaseService.getUserPlaylists()) ?? []
    }

    /// Adds a track to a playlist. Returns true on success.
    func addToPlaylist(playlistId: String, trackId: String) async -> Bool {
        do {
            try await supabaseService.addTrackToPlaylist(playlistId: playlistId, trackId: trackId)
            return true
        } catch {
            debugLog("[MediaListVM] addToPlaylist: \(error)")
            return false
        }
    }

    /// Resolves a track's artist user id (for "Go to artist") via track metadata.
    func artistUserId(for trackId: String) async -> String? {
        do {
            return try await supabaseService.getTrackMetadata(trackId: trackId).artist?.userId
        } catch {
            debugLog("[MediaListVM] artistUserId: \(error)")
            return nil
        }
    }

    /// Resolves a playlist's bare cover path to a public URL (for the picker rows).
    func playlistCover(_ path: String?) -> URL? {
        storageService.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }

    var footer: LocalizedStringKey {
        "^[\(items.count) track](inflect: true)"
    }
}

extension MediaListScreenViewModel: PlayerStateObserving {}
