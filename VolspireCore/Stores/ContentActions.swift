//
//  ContentActions.swift
//  Volspire
//
//  THE path for destructive actions (delete a track / listing, block someone,
//  …). Every one is optimistic and the same shape:
//
//    1. strip it locally from every store at once (the UI updates instantly),
//    2. run the RPC in the background,
//    3. success → a toast; failure → put it back (silent refetch) + an error
//       toast.
//
//  Views confirm with the modal (`confirmModal`) and call one method here; they
//  never fan out to the stores themselves or wait on the server. Owned by
//  `Dependencies` (`dependencies.contentActions`).
//

import Foundation
import MediaLibrary
import Observation
import Player
import Services
import SharedUtilities

@MainActor @Observable
final class ContentActions {
    private let service: SupabaseService
    private let feed: FeedStore
    private let library: LibraryStore
    private let listings: ListingsStore
    private let inbox: InboxStore
    private let social: SocialStore
    private let workspace: WorkspaceStore
    private let mediaState: MediaState
    private let mediaPlayer: MediaPlayer
    private let playerController: PlayerController
    private let toast = ToastCenter.shared

    init(
        service: SupabaseService,
        feed: FeedStore,
        library: LibraryStore,
        listings: ListingsStore,
        inbox: InboxStore,
        social: SocialStore,
        workspace: WorkspaceStore,
        mediaState: MediaState,
        mediaPlayer: MediaPlayer,
        playerController: PlayerController
    ) {
        self.service = service
        self.feed = feed
        self.library = library
        self.listings = listings
        self.inbox = inbox
        self.social = social
        self.workspace = workspace
        self.mediaState = mediaState
        self.mediaPlayer = mediaPlayer
        self.playerController = playerController
    }

    // MARK: - Tracks

    /// Deletes one of the viewer's tracks. `onRollback` lets a surface with
    /// its own copy (the profile) reload if the server refuses.
    func deleteTrack(id: String, onRollback: (() -> Void)? = nil) {
        feed.removeTrack(id)
        library.trackDeleted(id)
        if playerController.state.currentMediaID?.value.caseInsensitiveCompare(id) == .orderedSame {
            mediaPlayer.reset()
        }
        Task { await mediaState.removeTrack(MediaID(id)) }

        Task {
            do {
                guard let me = service.currentUserId else { throw URLError(.userAuthenticationRequired) }
                try await service.deleteTrack(trackId: id, userId: me)
                toast.show("Track deleted")
            } catch {
                debugLog("[ContentActions] deleteTrack: \(error)")
                async let feedBack: Void = feed.trackEdited(id)
                async let libraryBack: Void = library.trackEdited(id)
                _ = await (feedBack, libraryBack)
                onRollback?()
                toast.show("Couldn't delete the track — it's back.", style: .error)
            }
        }
    }

    // MARK: - Listings

    /// Deletes one of the viewer's listings (the board, saved, and any open
    /// page drop it now).
    func deleteListing(_ listing: ApiListing) {
        listings.listingDeleted(listing.listingId)
        Task {
            do {
                try await service.deleteListing(listingId: listing.listingId)
                toast.show("Listing deleted")
            } catch {
                debugLog("[ContentActions] deleteListing: \(error)")
                async let board: Void = listings.refreshListings()
                async let saved: Void = listings.refreshSaved()
                _ = await (board, saved)
                toast.show("Couldn't delete the listing — it's back.", style: .error)
            }
        }
    }

    // MARK: - Playlists & releases

    func deletePlaylist(id: String) {
        Task {
            if await library.deletePlaylist(playlistId: id) {
                toast.show("Playlist deleted")
            } else {
                toast.show("Couldn't delete the playlist — it's back.", style: .error)
            }
        }
    }

    func deleteRelease(id: String) {
        Task {
            do {
                try await library.deleteRelease(releaseId: id)
                toast.show("Release deleted")
            } catch {
                debugLog("[ContentActions] deleteRelease: \(error)")
                toast.show("Couldn't delete the release — it's back.", style: .error)
            }
        }
    }

    // MARK: - Workspace

    func deleteFolder(id: String) {
        Task {
            do {
                try await workspace.deleteFolder(folderId: id)
                toast.show("Folder deleted")
            } catch {
                debugLog("[ContentActions] deleteFolder: \(error)")
                toast.show("Couldn't delete the folder — it's back.", style: .error)
            }
        }
    }

    /// `describe` turns a refusal into the folder screen's wording (order
    /// folders, permissions).
    func deleteFile(id: String, folderId: String, describe: @escaping (Error) -> String) {
        Task {
            do {
                try await workspace.deleteFile(fileId: id, folderId: folderId)
                toast.show("File deleted")
            } catch {
                debugLog("[ContentActions] deleteFile: \(error)")
                toast.show(describe(error), style: .error)
            }
        }
    }

    func removeTrackFromFolder(trackId: String, folderId: String) {
        Task {
            do {
                try await workspace.removeTrack(trackId: trackId, folderId: folderId)
                toast.show("Removed from folder")
            } catch {
                debugLog("[ContentActions] removeTrackFromFolder: \(error)")
                toast.show("Couldn't remove the track — it's back.", style: .error)
            }
        }
    }

    // MARK: - People

    /// Blocks a user: their tracks, artists, listings and threads leave every
    /// surface at once; the RPC + a silent refresh follow (no skeletons).
    func block(userId: String, username: String) {
        feed.removeContent(byUser: userId)
        listings.removeContent(byUser: userId)
        inbox.removeConversations(with: userId)
        // Their track is playing — stop and clear the player, from wherever
        // the block came (player, profile, DM, listing).
        if playerController.currentArtistUserId?.caseInsensitiveCompare(userId) == .orderedSame {
            mediaPlayer.reset()
            playerController.resetForSignOut()
        }
        Task {
            do {
                // Posts `.userBlockStateChanged` → the stores' silent refreshes.
                try await service.blockUser(userId)
                toast.show("Blocked @\(username)")
            } catch {
                debugLog("[ContentActions] block: \(error)")
                async let feedBack: Void = feed.refreshAfterBlockChange()
                async let listingsBack: Void = listings.refreshListings()
                async let inboxBack: Void = inbox.refreshConversations()
                _ = await (feedBack, listingsBack, inboxBack)
                toast.show("Couldn't block @\(username). Try again.", style: .error)
            }
        }
    }

    /// Ends an accepted collaboration: the badge / Message button flip now;
    /// the RPC archives the pair's DM, so the inbox regroups after it.
    func removeCollaborator(userId: String, username: String) {
        social.setCollabStatus("none", userId: userId)
        Task {
            do {
                try await service.removeCollaborator(userId: userId)
                await inbox.refreshConversations()
                toast.show("Removed @\(username) as a collaborator")
            } catch {
                debugLog("[ContentActions] removeCollaborator: \(error)")
                social.setCollabStatus("accepted", userId: userId)
                toast.show("Couldn't remove @\(username). Try again.", style: .error)
            }
        }
    }

    /// Unblocks a user (Settings / an unavailable profile). Not optimistic —
    /// their content has to come back from the server — but it reports.
    @discardableResult
    func unblock(userId: String, username: String?) async -> Bool {
        do {
            try await service.unblockUser(userId)
            toast.show(username.map { "Unblocked @\($0)" } ?? "Unblocked")
            return true
        } catch {
            debugLog("[ContentActions] unblock: \(error)")
            toast.show("Couldn't unblock. Try again.", style: .error)
            return false
        }
    }
}
