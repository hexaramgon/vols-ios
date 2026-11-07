//
//  AddTracksSheet.swift
//  Volspire
//
//  The playlist page's "Add tracks" picker (the web's "Add from your
//  library"): your saved tracks that aren't in the playlist yet, each with a
//  + that adds it in place. The sheet stays open so you can add several;
//  `onChanged` lets the playlist page reload behind it.
//

import DesignSystem
import Services
import SharedUtilities
import SwiftUI

struct AddTracksSheet: View {
    let playlistId: String
    /// Track ids already in the playlist — hidden from the list.
    let existingIds: Set<String>
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryStore.self) private var libraryStore

    @State private var addingId: String?
    @State private var addedIds: Set<String> = []

    private var candidates: [ApiUserLike] {
        libraryStore.savedTracks.filter { !existingIds.contains($0.trackId) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .listMusic,
                title: "Add tracks",
                subtitle: "Add from your saved tracks"
            ) { dismiss() }

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .sheetBackground()
        .task { await libraryStore.loadIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if candidates.isEmpty {
            switch libraryStore.loadState {
            case .idle, .loading:
                ProgressView().tint(Color.vText2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error:
                LoadErrorView(icon: .bookmark, title: "Couldn't load your saved tracks") {
                    Task { await libraryStore.refresh() }
                }
                .padding(.top, 36)
                .frame(maxWidth: .infinity)
            case .loaded:
                EmptyStateView(
                    icon: .bookmark,
                    title: libraryStore.savedTracks.isEmpty ? "No saved tracks yet" : "Everything's already here",
                    message: libraryStore.savedTracks.isEmpty ? "Save tracks to add them to a playlist." : nil
                )
                .padding(.top, 36)
                .frame(maxWidth: .infinity)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(candidates) { row($0) }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }

    private func row(_ track: ApiUserLike) -> some View {
        let added = addedIds.contains(track.trackId)
        return Button {
            Task { await add(track) }
        } label: {
            HStack(spacing: 12) {
                ArtworkView(libraryStore.coverURL(for: track).map { .webImage($0) } ?? .album, cornerRadius: Radius.tile)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.appFont.trackTitle).foregroundStyle(Color.vText).lineLimit(1)
                    if let artist = track.artist?.username, !artist.isEmpty {
                        Text("@\(artist)").font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if addingId == track.trackId {
                    ProgressView().tint(Color.vText).controlSize(.small)
                } else {
                    // The pickers' add / added control (pop + drawn check).
                    AddedCheck(isOn: added)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        .disabled(added || addingId != nil)
    }

    private func add(_ track: ApiUserLike) async {
        guard addingId == nil, !addedIds.contains(track.trackId) else { return }
        addingId = track.trackId
        if await libraryStore.addTrack(toPlaylist: playlistId, trackId: track.trackId) {
            addedIds.insert(track.trackId)
            Haptics.impact(.soft)
            onChanged()
        }
        addingId = nil
    }
}
