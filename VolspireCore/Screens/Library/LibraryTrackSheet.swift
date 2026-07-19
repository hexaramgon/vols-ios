//
//  LibraryTrackSheet.swift
//  Volspire
//
//  Thin wrapper that builds the shared `TrackOptionsSheet` for a saved track.
//

import DesignSystem
import Services
import SwiftUI

struct LibraryTrackSheet: View {
    let track: ApiUserLike
    let viewModel: LibraryScreenViewModel
    let router: Router
    let onDismiss: () -> Void
    let onAddToPlaylist: () -> Void

    var body: some View {
        TrackOptionsSheet(
            artwork: .placeholder(viewModel.coverURL(for: track), name: track.title),
            title: track.title,
            artist: track.artist?.username,
            meta: track.streams.map { "\($0.formatted()) streams" },
            actions: actions,
            reportTargetId: track.trackId
        )
    }

    private var actions: [TrackOptionsSheet.Action] {
        var list: [TrackOptionsSheet.Action] = []
        if let artist = track.artist {
            list.append(.init(icon: .user, title: "Go to Artist") {
                router.navigateToProfile(userId: artist.userId)
            })
        }
        list.append(.init(icon: .share2, title: "Share Track", dismissesSheet: false) {
            ShareActions.shareTrack(title: track.title, trackId: track.trackId)
        })
        list.append(.init(icon: .circlePlus, title: "Add to Playlist") {
            onAddToPlaylist()
        })
        list.append(.init(icon: .circleMinus, title: "Remove from Library", isDestructive: true, awaitsCompletion: true) {
            await viewModel.removeFromLibrary(track)
        })
        return list
    }
}
