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
import SharedUtilities

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
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    InlineCreateRow(label: "New folder", placeholder: "Folder name") { name in
                        await createAndAdd(name: name)
                    }
                    ForEach(folders, id: \.folderId) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)

                if folders.isEmpty {
                    VStack(spacing: 10) {
                        LucideIcon(.folder, .xxl)
                            .foregroundStyle(.white.opacity(0.25))
                        Text("No folders yet")
                            .font(.appCallout)
                            .foregroundStyle(.white.opacity(0.7))
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

    /// Inline "New folder": creates it, adds the track to it, and refreshes the
    /// list so the new folder appears checked. Returns success for the row.
    private func createAndAdd(name: String) async -> Bool {
        errorText = nil
        do {
            let folderId = try await service.createFolder(name: name, description: nil)
            try await service.addTrackToFolder(trackId: trackId, folderId: folderId)
            folders = (try? await service.getUserFolders()) ?? folders
            withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(folderId) }
            Haptics.impact(.soft)
            return true
        } catch {
            errorText = "Couldn't create the folder. Please try again."
            debugLog("[WorkspaceFolderPicker] create failed: \(error)")
            return false
        }
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
                debugLog("[WorkspaceFolderPicker] toggle failed: \(error)")
            }
        }
    }
}

// MARK: - AttachmentFolderPicker

/// "Add to Workspace" for a chat audio attachment — pick a folder and the
/// attachment is downloaded and re-uploaded as a workspace file (mirrors the
/// web's AddToFolderModal flow in messages). Unlike the track picker above,
/// this is a one-shot copy, not a membership toggle, and only folders the
/// user can write to (owner/editor) are listed — viewers can't add files.
struct AttachmentFolderPicker: View {
    /// Signed URL of the message attachment to copy.
    let url: URL
    let fileName: String?
    /// MIME type of the attachment (e.g. "audio/mpeg").
    let fileType: String?

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
                icon: .folderPlus,
                title: "Add to Workspace",
                subtitle: "Pick a folder for this file"
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
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    InlineCreateRow(label: "New folder", placeholder: "Folder name") { name in
                        await createAndAdd(name: name)
                    }
                    ForEach(folders, id: \.folderId) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)

                if folders.isEmpty {
                    VStack(spacing: 10) {
                        LucideIcon(.folder, .xxl)
                            .foregroundStyle(.white.opacity(0.25))
                        Text("No editable folders")
                            .font(.appCallout)
                            .foregroundStyle(.white.opacity(0.7))
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

    private func folderRow(_ folder: ApiUserFolder) -> some View {
        let added = addedFolderIds.contains(folder.folderId)
        return Button { add(folder) } label: {
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

                if busyFolderId == folder.folderId {
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
        .disabled(busyFolderId == folder.folderId || added)
        .animation(.smooth(duration: 0.2), value: added)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // File uploads need write access — viewers can't add files (same
        // filter as the web modal).
        let all = (try? await service.getUserFolders()) ?? []
        folders = all.filter { ["owner", "editor"].contains($0.role.lowercased()) }
    }

    /// Downloads the attachment and copies it into `folder`, then dismisses.
    private func add(_ folder: ApiUserFolder) {
        guard busyFolderId == nil, !addedFolderIds.contains(folder.folderId) else { return }
        let id = folder.folderId
        busyFolderId = id
        errorText = nil
        Task {
            defer { busyFolderId = nil }
            do {
                try await copyAttachment(into: id)
                withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(id) }
                Haptics.impact(.soft)
                // Leave the check visible for a beat, then close.
                try? await Task.sleep(for: .milliseconds(600))
                dismiss()
            } catch {
                errorText = "Couldn't add to workspace. Please try again."
                debugLog("[AttachmentFolderPicker] add failed: \(error)")
            }
        }
    }

    /// Inline "New folder": creates it, copies the attachment into it, then
    /// closes like a normal add. Returns success for the row.
    private func createAndAdd(name: String) async -> Bool {
        errorText = nil
        do {
            let folderId = try await service.createFolder(name: name, description: nil)
            try await copyAttachment(into: folderId)
            folders = ((try? await service.getUserFolders()) ?? [])
                .filter { ["owner", "editor"].contains($0.role.lowercased()) }
            withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(folderId) }
            Haptics.impact(.soft)
            try? await Task.sleep(for: .milliseconds(600))
            dismiss()
            return true
        } catch {
            errorText = "Couldn't create the folder. Please try again."
            debugLog("[AttachmentFolderPicker] create failed: \(error)")
            return false
        }
    }

    /// Downloads the attachment bytes and registers them as a file in `folderId`.
    private func copyAttachment(into folderId: String) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        try await service.addAttachmentToFolder(
            folderId: folderId,
            fileName: fileName ?? "audio",
            fileData: data,
            fileType: fileType ?? "application/octet-stream"
        )
    }
}
