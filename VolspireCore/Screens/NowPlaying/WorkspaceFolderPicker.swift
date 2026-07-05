//
//  WorkspaceFolderPicker.swift
//  Volspire
//
//  "Add to Workspace" — pick a folder to toggle the current track in (tap to add,
//  tap again to remove). Folders the track is already in are pre-checked via
//  `get_folders_for_track`. Styled like the rest of the player: frosted panel,
//  Geist type, soft white cards.
//

import DesignSystem
import Services
import SwiftUI

struct WorkspaceFolderPicker: View {
    let trackId: String

    @Environment(\.dismiss) private var dismiss

    @State private var folders: [ApiUserFolder] = []
    @State private var isLoading = true
    @State private var busyFolderId: String?
    @State private var addedFolderIds: Set<String> = []
    @State private var errorText: String?

    private let service = SupabaseService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .folder,
                title: "Add to Workspace",
                subtitle: "Pick a folder for this track"
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
        .foregroundStyle(.white)
        // Darker frosted panel to match the web's modal background.
        .sheetBackground()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if folders.isEmpty {
            VStack(spacing: 10) {
                LucideIcon(.folder, .xxl)
                    .foregroundStyle(.white.opacity(0.25))
                Text("No folders yet")
                    .font(.appCallout)
                    .foregroundStyle(.white.opacity(0.7))
                Text("Create one in your Workspace first.")
                    .font(.appFootnote)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 60)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(folders, id: \.folderId) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
    }

    private func folderRow(_ folder: ApiUserFolder) -> some View {
        let added = addedFolderIds.contains(folder.folderId)
        return Button { toggle(folder) } label: {
            HStack(spacing: 12) {
                LucideIcon(.folder, .lg)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.appCalloutSemibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let desc = folder.description, !desc.isEmpty {
                        Text(desc)
                            .font(.appCaption)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                trailingState(folder: folder, added: added)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        // Disable ONLY the row being toggled — not the whole list — so the sheet
        // doesn't dim on every tap. (Concurrent taps are still blocked by the
        // `guard busyFolderId == nil` in `toggle`.)
        .disabled(busyFolderId == folder.folderId)
        .animation(.smooth(duration: 0.2), value: added)
    }

    @ViewBuilder
    private func trailingState(folder: ApiUserFolder, added: Bool) -> some View {
        if busyFolderId == folder.folderId {
            ProgressView().tint(.white).controlSize(.small)
        } else {
            LucideIcon(added ? .circleCheck : .plus, .lg)
                .foregroundStyle(added ? Color.green : Color.vText3)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // Load the folders and which ones already contain this track in parallel,
        // so each row's check is accurate on open.
        async let foldersResult = service.getUserFolders()
        async let memberResult = service.getFoldersForTrack(trackId: trackId)
        folders = (try? await foldersResult) ?? []
        addedFolderIds = Set((try? await memberResult) ?? [])
    }

    /// A human-readable reason for a failed add/remove.
    private func message(for error: Error) -> String {
        let raw = "\(error)".lowercased()
        if raw.contains("not authorized") {
            // Editors can add, but only the owner (or whoever added it) can remove.
            return "Only the folder owner or whoever added this track can remove it."
        }
        return "Couldn't update the folder. Please try again."
    }

    /// Tap a folder to add the track; tap one it's already in to remove it.
    private func toggle(_ folder: ApiUserFolder) {
        guard busyFolderId == nil else { return }
        let id = folder.folderId
        busyFolderId = id
        errorText = nil
        Task {
            defer { busyFolderId = nil }
            do {
                if addedFolderIds.contains(id) {
                    try await service.removeTrackFromFolder(trackId: trackId, folderId: id)
                    withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.remove(id) }
                } else {
                    try await service.addTrackToFolder(trackId: trackId, folderId: id)
                    withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(id) }
                }
            } catch {
                errorText = message(for: error)
                print("[WorkspaceFolderPicker] toggle failed: \(error)")
            }
        }
    }
}
