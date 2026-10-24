//
//  PlayerTrackOptions.swift
//  Volspire
//
//  The expanded player's track "…" sheet — Add to playlist, Save, Share, Add
//  to Workspace, Report track, then View / Report / Block artist (App Store
//  1.2) — and the sheets and dialog each row hands off to. A modifier so
//  PlayerControls only owns the "is it open" flag.
//

import DesignSystem
import Services
import SwiftUI

extension View {
    func playerTrackOptions(isPresented: Binding<Bool>) -> some View {
        modifier(PlayerTrackOptions(isPresented: isPresented))
    }
}

private struct PlayerTrackOptions: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(PlayerController.self) private var model
    @Environment(Dependencies.self) private var dependencies

    @State private var pendingAction: Action?
    @State private var showReportSong = false
    @State private var showReportArtist = false
    @State private var showBlockArtist = false
    @State private var showAddToPlaylist = false
    @State private var showFolderPicker = false

    private enum Action { case addToPlaylist, share, addToWorkspace, viewArtist, reportSong, reportArtist, block }

    private var trackId: String? { model.state.currentMediaID?.value }
    private var artistId: String? { model.trackDetail?.artist?.userId }
    private var artistName: String {
        model.trackDetail?.artist?.username ?? (model.display.subtitle.isEmpty ? "artist" : model.display.subtitle)
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: runPendingAction) { optionsSheet }
            .sheet(isPresented: $showReportSong) {
                if let trackId {
                    ReportSheet(targetType: .track, targetId: trackId, subject: model.display.title)
                }
            }
            .sheet(isPresented: $showReportArtist) {
                if let artistId {
                    ReportSheet(targetType: .user, targetId: artistId, subject: "@\(artistName)")
                }
            }
            .sheet(isPresented: $showAddToPlaylist) {
                if let trackId { AddToPlaylistSheet(trackId: trackId, alwaysDark: true) }
            }
            .sheet(isPresented: $showFolderPicker) {
                if let trackId { WorkspaceFolderPicker(trackId: trackId) }
            }
            .blockUserDialog(username: artistName, isPresented: $showBlockArtist) {
                blockCurrentArtist()
            }
    }

    /// Slide-up options sheet — matches the folder / listing / track sheets.
    private var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .music, title: model.display.title, subtitle: "@\(artistName)") {
                isPresented = false
            }
            // The web phone "⋯" order — Add to playlist, Save, Share,
            // Add to Workspace, Report track — then View artist and the
            // artist-level moderation rows (App Store 1.2). Download is
            // web-only (no iOS file export).
            VStack(spacing: 0) {
                OptionSheetRow(icon: .listMusic, title: "Add to playlist") { choose(.addToPlaylist) }
                OptionSheetRow(icon: model.isSaved ? .bookmarkFill : .bookmark, title: model.isSaved ? "Saved" : "Save") {
                    Task { await model.toggleSave() }
                }
                OptionSheetRow(icon: .share2, title: "Share") { choose(.share) }
                OptionSheetRow(icon: .folderPlus, title: "Add to Workspace") { choose(.addToWorkspace) }
                OptionSheetRow(icon: .flag, title: "Report track") { choose(.reportSong) }
                if artistId != nil {
                    OptionSheetRow(icon: .user, title: "View artist") { choose(.viewArtist) }
                    OptionSheetRow(icon: .flag, title: "Report artist") { choose(.reportArtist) }
                    OptionSheetRow(icon: .ban, title: "Block artist", tint: .vDestructive) { choose(.block) }
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground(alwaysDark: true)
    }

    /// Rows close the sheet first; the follow-up runs from `onDismiss`, once
    /// it's gone (presenting from a dismissing sheet is dropped).
    private func choose(_ action: Action) {
        pendingAction = action
        isPresented = false
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .addToPlaylist: showAddToPlaylist = true
        case .addToWorkspace: showFolderPicker = true
        case .viewArtist: if let artistId { model.pendingProfileNavigation = artistId }
        case .share: ShareActions.shareTrack(title: model.display.title, trackId: trackId)
        case .reportSong: showReportSong = true
        case .reportArtist: showReportArtist = true
        case .block: showBlockArtist = true
        }
    }

    private func blockCurrentArtist() {
        guard let artistId else { return }
        Task {
            try? await dependencies.supabaseService.blockUser(artistId)
            // The playing track belongs to the artist just blocked — stop and
            // clear the player entirely (same teardown as sign-out; the player
            // overlay unmounts once the display empties).
            dependencies.mediaPlayer.reset()
            model.resetForSignOut()
        }
    }
}
