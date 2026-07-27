//
//  AddToPlaylistSheet.swift
//  Volspire
//
//  Shared "Add to playlist" picker — lists the user's playlists (from the
//  shared LibraryStore) and toggles the given track in the tapped one (tap to
//  add, tap again to remove). Presentable from anywhere: the collection "…"
//  menu, the player, etc.
//

import DesignSystem
import Services
import SwiftUI
import SharedUtilities

struct AddToPlaylistSheet: View {
    let trackId: String
    /// The playlist currently being viewed (if any) — shown as already containing
    /// the track, since you got here from inside it.
    var currentPlaylistId: String? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var libraryStore
    /// Per-track membership pre-check only — playlist content routes through the store.
    private let service = SupabaseService()

    @State private var loaded = false
    @State private var addingId: String?
    @State private var addedIds: Set<String> = []
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
        .presentationDetents([.medium, .large])
        .sheetBackground()
        .task {
            // Load the playlists and which ones already contain this track in
            // parallel, so every row's check is accurate on open (matches the web
            // app's `get_playlists_for_track`), not just the one we arrived from.
            async let playlistsLoad: () = libraryStore.loadPlaylistsIfNeeded()
            async let memberResult = service.getPlaylistsForTrack(trackId: trackId)
            _ = await playlistsLoad
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
                    ForEach(libraryStore.playlists) { row($0) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)

                if libraryStore.playlists.isEmpty {
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

    /// Inline "New playlist": creates it (the store refreshes its list, so the
    /// new playlist shows everywhere) and adds the track.
    private func createAndAdd(title: String) async -> Bool {
        errorText = nil
        do {
            let playlistId = try await libraryStore.createPlaylist(title: title)
            _ = await libraryStore.addTrack(toPlaylist: playlistId, trackId: trackId)
            addedIds.insert(playlistId)
            Haptics.impact(.soft)
            return true
        } catch {
            errorText = "Couldn't create the playlist. Please try again."
            debugLog("[AddToPlaylistSheet] create failed: \(error)")
            return false
        }
    }

    private func row(_ playlist: ApiPlaylist) -> some View {
        let added = addedIds.contains(playlist.playlistId)
        return Button {
            Task { await toggle(playlist) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(.placeholder(libraryStore.playlistCover(playlist.coverUrl), name: playlist.title), cornerRadius: 9)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title).font(.appFont.trackTitle).foregroundStyle(.white).lineLimit(1)
                    Text("\(max(0, playlist.trackCount ?? 0)) tracks").font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
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
    /// The store patches the playlist's count in place, so the row reacts live.
    private func toggle(_ playlist: ApiPlaylist) async {
        let id = playlist.playlistId
        guard addingId == nil else { return }
        addingId = id
        if addedIds.contains(id) {
            if await libraryStore.removeTrack(fromPlaylist: id, trackId: trackId) {
                addedIds.remove(id)
            }
        } else {
            if await libraryStore.addTrack(toPlaylist: id, trackId: trackId) {
                addedIds.insert(id)
            }
        }
        addingId = nil
    }
}
