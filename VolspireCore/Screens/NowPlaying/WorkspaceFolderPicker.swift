//
//  WorkspaceFolderPicker.swift
//  Volspire
//
//  "Add to Workspace" — one folder-picker sheet with two modes (the previous
//  twin structs had drifted apart line by line):
//   • track membership: toggle the current track in/out of folders (tap to add,
//     tap again to remove), pre-checked via `get_folders_for_track`.
//   • attachment copy: one-shot download + re-upload of a chat attachment into
//     a writable (owner/editor) folder, closing after the copy — mirrors the
//    web's AddToFolderModal flow in messages.
//   • pack link: one-shot `add_pack_to_folder` into a writable folder (a
//     reference to the pack, not a copy of its files).
//  Themed with the app; pinned dark only for the player's track mode (it
//  opens over the always-dark Now Playing).
//

import DesignSystem
import Services
import SwiftUI
import SharedUtilities

/// Toggle the current track's folder membership (player "…" menu).
struct WorkspaceFolderPicker: View {
    let trackId: String

    var body: some View {
        FolderPickerSheet(mode: .trackMembership(trackId: trackId))
    }
}

/// Copy a chat audio attachment into a workspace folder (message long-press).
struct AttachmentFolderPicker: View {
    /// Signed URL of the message attachment to copy.
    let url: URL
    let fileName: String?
    /// MIME type of the attachment (e.g. "audio/mpeg").
    let fileType: String?

    var body: some View {
        FolderPickerSheet(mode: .attachmentCopy(url: url, fileName: fileName, fileType: fileType))
    }
}

/// Link a marketplace pack into a workspace folder (pack page "…" menu).
struct PackFolderPicker: View {
    let packId: String

    var body: some View {
        FolderPickerSheet(mode: .packLink(packId: packId))
    }
}

// MARK: - The shared sheet

private struct FolderPickerSheet: View {
    enum Mode {
        /// Tap to add, tap again to remove; rows stay enabled after toggling.
        case trackMembership(trackId: String)
        /// One-shot copy: added rows disable, and the sheet closes after the
        /// check has been visible for a beat. Only writable folders are listed.
        case attachmentCopy(url: URL, fileName: String?, fileType: String?)
        /// One-shot pack link, same behaviour as the attachment copy.
        case packLink(packId: String)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceStore.self) private var workspaceStore

    @State private var isLoading = true
    @State private var busyFolderId: String?
    @State private var addedFolderIds: Set<String> = []
    @State private var errorText: String?

    /// Membership pre-check + attachment upload only — folders live in the store.
    private let service = SupabaseService()

    private var isToggle: Bool {
        if case .trackMembership = mode { return true } else { return false }
    }

    /// Only the player's picker sits over the always-dark Now Playing; the
    /// pack page and messages open it in the app's own theme.
    private var alwaysDark: Bool { isToggle }

    /// The rows: every folder in track mode; writable folders only when copying
    /// a file in (viewers can't add files — same filter as the web modal).
    private var folders: [ApiUserFolder] {
        isToggle
            ? workspaceStore.folders
            : workspaceStore.folders.filter { ["owner", "editor"].contains($0.role.lowercased()) }
    }

    private var subtitle: String {
        switch mode {
        case .trackMembership: "Pick a folder for this track"
        case .attachmentCopy: "Pick a folder for this file"
        case .packLink: "Pick a folder for this pack"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: isToggle ? .folder : .folderPlus,
                title: "Add to Workspace",
                subtitle: subtitle,
                divider: false
            ) { dismiss() }
            content
            if let errorText {
                ErrorBanner(errorText)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(Color.vText)
        .sheetBackground(alwaysDark: alwaysDark)
        .presentationDetents([.medium, .large])
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .tint(Color.vText3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    InlineCreateRow(label: "New folder", placeholder: "Folder name", maxLength: InputLimits.folderName) { name in
                        await createAndAdd(name: name)
                    }
                    ForEach(folders, id: \.folderId) { folder in
                        folderRow(folder)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 20)

                if folders.isEmpty && workspaceStore.foldersFailed {
                    LoadErrorView(icon: .folder, title: "Couldn't load your folders") {
                        Task { await workspaceStore.refreshFolders() }
                    }
                    .padding(.top, 24)
                } else if folders.isEmpty {
                    VStack(spacing: 10) {
                        LucideIcon(.folder, .xxl)
                            .foregroundStyle(Color.vText3)
                        Text(isToggle ? "No folders yet" : "No editable folders")
                            .font(.appCallout)
                            .foregroundStyle(Color.vText2)
                        Text("Create one right here to get started.")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vText3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 36)
                }
            }
        }
    }

    private func folderRow(_ folder: ApiUserFolder) -> some View {
        let added = addedFolderIds.contains(folder.folderId)
        return Button { tap(folder) } label: {
            HStack(spacing: 12) {
                // The folder's own art (its name mesh + monogram), as in Workspace.
                FolderArt(id: folder.folderId, name: folder.name, size: .sm)
                    .scaleEffect(1.2)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    // The Add-to-playlist rows' type (the shared row pair).
                    Text(folder.name)
                        .font(.appFont.trackTitle)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    if let desc = folder.description, !desc.isEmpty {
                        Text(desc)
                            .font(.appFont.trackSubtitle)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if !isToggle, busyFolderId == folder.folderId {
                    // Copying a file in is a real upload — show it working.
                    ProgressView().tint(Color.vText).controlSize(.small)
                } else {
                    // Same animated check as Add to playlist.
                    AddedCheck(isOn: added)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(MenuRowStyle())
        // Disable ONLY the row being acted on — not the whole list — so the sheet
        // doesn't dim on every tap. (Concurrent taps are still blocked by the
        // `guard busyFolderId == nil` in `tap`.) Copy mode also freezes rows
        // already added — a one-shot copy can't be undone from here.
        // Copy mode freezes rows already added — a one-shot copy can't be
        // undone from here. (Toggle mode stays live; `tap` ignores repeats.)
        .disabled(!isToggle && (busyFolderId == folder.folderId || added))
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case let .trackMembership(trackId):
            // Load the folders and which ones already contain this track in
            // parallel, so each row's check is accurate on open.
            async let foldersLoad: () = workspaceStore.loadFoldersIfNeeded()
            async let memberResult = service.getFoldersForTrack(trackId: trackId)
            _ = await foldersLoad
            addedFolderIds = Set((try? await memberResult) ?? [])
        case .attachmentCopy, .packLink:
            await workspaceStore.loadFoldersIfNeeded()
        }
    }

    // MARK: Actions

    /// Tap a folder: toggle membership (track mode) or copy the attachment in
    /// (one-shot mode, which then closes the sheet after a beat).
    private func tap(_ folder: ApiUserFolder) {
        guard busyFolderId == nil else { return }
        let id = folder.folderId
        let added = addedFolderIds.contains(id)
        if !isToggle, added { return } // one-shot: already copied
        busyFolderId = id
        errorText = nil
        // Track membership is optimistic: the check animates on the tap and
        // rolls back if the write fails.
        if isToggle {
            if added { addedFolderIds.remove(id); Haptics.selection() } else { addedFolderIds.insert(id); Haptics.success() }
        }
        Task {
            defer { busyFolderId = nil }
            do {
                if isToggle, added {
                    try await remove(from: id)
                } else {
                    try await add(into: id)
                    if !isToggle {
                        addedFolderIds.insert(id)
                        busyFolderId = nil // swap the spinner for the check
                        Haptics.success()
                        // Leave the check visible for a beat, then close.
                        try? await Task.sleep(for: .milliseconds(600))
                        dismiss()
                    }
                }
            } catch {
                if isToggle {
                    if added { addedFolderIds.insert(id) } else { addedFolderIds.remove(id) }
                }
                errorText = failureMessage(for: error)
                debugLog("[FolderPickerSheet] \(isToggle ? "toggle" : "add") failed: \(error)")
            }
        }
    }

    /// Inline "New folder": creates it, performs the mode's add into it, and
    /// refreshes the list so the new folder appears checked. Returns success
    /// for the row; one-shot mode then closes like a normal add.
    private func createAndAdd(name: String) async -> Bool {
        errorText = nil
        do {
            // The store refetches its folder list, so the new folder appears
            // here AND on the Home Workspace grid without a revisit.
            let folderId = try await workspaceStore.createFolder(name: name, description: nil)
            try await add(into: folderId)
            withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(folderId) }
            // The store's create already buzzed (success).
            if !isToggle {
                try? await Task.sleep(for: .milliseconds(600))
                dismiss()
            }
            return true
        } catch {
            errorText = "Couldn't create the folder. Please try again."
            debugLog("[FolderPickerSheet] create failed: \(error)")
            return false
        }
    }

    /// The mode's "add" primitive: folder membership vs. download-and-upload.
    private func add(into folderId: String) async throws {
        switch mode {
        case let .trackMembership(trackId):
            try await workspaceStore.addTrack(trackId: trackId, folderId: folderId)
        case let .attachmentCopy(url, fileName, fileType):
            let (data, _) = try await URLSession.shared.data(from: url)
            try await service.uploadFile(
                folderId: folderId,
                fileName: fileName ?? "audio",
                fileData: data,
                fileType: fileType ?? "application/octet-stream"
            )
            // An open folder screen shows the copied file without a revisit.
            await workspaceStore.fileUploaded(folderId: folderId)
        case let .packLink(packId):
            try await workspaceStore.addPack(packId: packId, folderId: folderId)
        }
    }

    private func remove(from folderId: String) async throws {
        guard case let .trackMembership(trackId) = mode else { return }
        try await workspaceStore.removeTrack(trackId: trackId, folderId: folderId)
    }

    /// A human-readable reason for a failed add/remove.
    private func failureMessage(for error: Error) -> String {
        switch mode {
        case .trackMembership:
            let raw = "\(error)".lowercased()
            if raw.contains("not authorized") {
                // Editors can add, but only the owner (or whoever added it) can remove.
                return "Only the folder owner or whoever added this track can remove it."
            }
            return "Couldn't update the folder. Please try again."
        case .attachmentCopy, .packLink:
            return "Couldn't add to workspace. Please try again."
        }
    }
}
