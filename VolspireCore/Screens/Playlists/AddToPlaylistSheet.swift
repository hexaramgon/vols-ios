//
//  AddToPlaylistSheet.swift
//  Volspire
//
//  Shared "Add to playlist" picker — lists the user's playlists and toggles the
//  given track in the tapped one (tap to add, tap again to remove). Self-contained
//  (owns its services) so it can be presented from anywhere: the collection "…"
//  menu, the player, etc.
//

import DesignSystem
import Services
import SwiftUI

struct AddToPlaylistSheet: View {
    let trackId: String
    /// The playlist currently being viewed (if any) — shown as already containing
    /// the track, since you got here from inside it.
    var currentPlaylistId: String? = nil

    @Environment(\.dismiss) private var dismiss
    private let service = SupabaseService()
    private let storage = StorageService()

    @State private var playlists: [ApiPlaylist] = []
    @State private var loaded = false
    @State private var addingId: String?
    @State private var addedIds: Set<String> = []
    /// Optimistic ±1 tweak to each playlist's track count as you toggle, so the
    /// count reacts without re-fetching.
    @State private var countAdjust: [String: Int] = [:]
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .listMusic,
                title: "Add to playlist",
                subtitle: "Save this track to a playlist"
            ) { dismiss() }

            content

            if let errorText {
                ErrorBanner(errorText)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheetBackground()
        .task {
            // Load the playlists and which ones already contain this track in
            // parallel, so every row's check is accurate on open (matches the web
            // app's `get_playlists_for_track`), not just the one we arrived from.
            async let playlistsResult = service.getUserPlaylists()
            async let memberResult = service.getPlaylistsForTrack(trackId: trackId)
            playlists = (try? await playlistsResult) ?? []
            var seed = Set((try? await memberResult) ?? [])
            if let currentPlaylistId { seed.insert(currentPlaylistId) }
            addedIds = seed
            loaded = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if !loaded {
            ProgressView().tint(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    InlineCreateRow(label: "New playlist", placeholder: "Playlist name") { title in
                        await createAndAdd(title: title)
                    }
                    ForEach(playlists) { row($0) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)

                if playlists.isEmpty {
                    VStack(spacing: 8) {
                        LucideIcon(.listMusic, .hero).foregroundStyle(Color.vText3)
                        Text("No playlists yet").font(.appCalloutSemibold).foregroundStyle(.white)
                        Text("Create one right here to get started.")
                            .font(.appFootnote)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                }
            }
        }
    }

    /// Inline "New playlist": creates it, adds the track, and re-fetches the
    /// list so the new playlist shows with an accurate count and a check.
    private func createAndAdd(title: String) async -> Bool {
        errorText = nil
        do {
            let playlistId = try await service.createPlaylist(title: title)
            try await service.addTrackToPlaylist(playlistId: playlistId, trackId: trackId)
            playlists = (try? await service.getUserPlaylists()) ?? playlists
            addedIds.insert(playlistId)
            Haptics.impact(.soft)
            return true
        } catch {
            errorText = "Couldn't create the playlist. Please try again."
            print("[AddToPlaylistSheet] create failed: \(error)")
            return false
        }
    }

    private func row(_ playlist: ApiPlaylist) -> some View {
        let added = addedIds.contains(playlist.playlistId)
        return Button {
            Task { await toggle(playlist) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(cover(playlist.coverUrl).map { .webImage($0) } ?? .placeholder(name: playlist.title), cornerRadius: 9)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text("\(trackCount(playlist)) tracks").font(.appCaption).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if addingId == playlist.playlistId {
                    ProgressView().tint(.white).controlSize(.small)
                } else {
                    LucideIcon(added ? .circleCheck : .plus, .lg)
                        .foregroundStyle(added ? Color.green : Color.vText3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        .disabled(addingId == playlist.playlistId)
    }

    /// Tap a playlist to add the track; tap one it's already in to remove it.
    private func toggle(_ playlist: ApiPlaylist) async {
        let id = playlist.playlistId
        guard addingId == nil else { return }
        addingId = id
        do {
            if addedIds.contains(id) {
                try await service.removeTrackFromPlaylist(playlistId: id, trackId: trackId)
                addedIds.remove(id)
                countAdjust[id, default: 0] -= 1
            } else {
                try await service.addTrackToPlaylist(playlistId: id, trackId: trackId)
                addedIds.insert(id)
                countAdjust[id, default: 0] += 1
            }
        } catch {
            print("[AddToPlaylistSheet] toggle failed: \(error)")
        }
        addingId = nil
    }

    /// Base track count plus this session's optimistic add/remove tweaks.
    private func trackCount(_ playlist: ApiPlaylist) -> Int {
        max(0, (playlist.trackCount ?? 0) + (countAdjust[playlist.playlistId] ?? 0))
    }

    private func cover(_ path: String?) -> URL? {
        storage.resolveTrackUrl(path).flatMap { URL(string: $0) }
    }
}
