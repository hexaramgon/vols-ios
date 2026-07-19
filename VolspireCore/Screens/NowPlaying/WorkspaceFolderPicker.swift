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
//  Styled like the rest of the player: frosted panel, Geist type, soft cards.
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

// MARK: - The shared sheet

private struct FolderPickerSheet: View {
    enum Mode {
        /// Tap to add, tap again to remove; rows stay enabled after toggling.
        case trackMembership(trackId: String)
        /// One-shot copy: added rows disable, and the sheet closes after the
        /// check has been visible for a beat. Only writable folders are listed.
        case attachmentCopy(url: URL, fileName: String?, fileType: String?)
    }

    let mode: Mode

    @Environment(\.dismiss) private var dismiss

    @State private var folders: [ApiUserFolder] = []
    @State private var isLoading = true
    @State private var busyFolderId: String?
    @State private var addedFolderIds: Set<String> = []
    @State private var errorText: String?

    private let service = SupabaseService()

    private var isToggle: Bool {
        if case .trackMembership = mode { return true } else { return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: isToggle ? .folder : .folderPlus,
                title: "Add to Workspace",
                subtitle: isToggle ? "Pick a folder for this track" : "Pick a folder for this file"
            ) { dismiss() }
            content
            if let errorText {
                ErrorBanner(errorText)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        // Darker frosted panel to match the web's modal background.
        .sheetBackground()
        .presentationDetents([.medium, .large])
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
                        Text(isToggle ? "No folders yet" : "No editable folders")
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
        return Button { tap(folder) } label: {
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
        // Disable ONLY the row being acted on — not the whole list — so the sheet
        // doesn't dim on every tap. (Concurrent taps are still blocked by the
        // `guard busyFolderId == nil` in `tap`.) Copy mode also freezes rows
        // already added — a one-shot copy can't be undone from here.
        .disabled(busyFolderId == folder.folderId || (!isToggle && added))
        .animation(.smooth(duration: 0.2), value: added)
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        switch mode {
        case let .trackMembership(trackId):
            // Load the folders and which ones already contain this track in
            // parallel, so each row's check is accurate on open.
            async let foldersResult = service.getUserFolders()
            async let memberResult = service.getFoldersForTrack(trackId: trackId)
            folders = (try? await foldersResult) ?? []
            addedFolderIds = Set((try? await memberResult) ?? [])
        case .attachmentCopy:
            // File uploads need write access — viewers can't add files (same
            // filter as the web modal).
            folders = await writableFolders()
        }
    }

    private func writableFolders() async -> [ApiUserFolder] {
        ((try? await service.getUserFolders()) ?? [])
            .filter { ["owner", "editor"].contains($0.role.lowercased()) }
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
        Task {
            defer { busyFolderId = nil }
            do {
                if isToggle, added {
                    try await remove(from: id)
                    withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.remove(id) }
                } else {
                    try await add(into: id)
                    withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(id) }
                    if !isToggle {
                        Haptics.impact(.soft)
                        // Leave the check visible for a beat, then close.
                        try? await Task.sleep(for: .milliseconds(600))
                        dismiss()
                    }
                }
            } catch {
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
            let folderId = try await service.createFolder(name: name, description: nil)
            try await add(into: folderId)
            folders = isToggle ? ((try? await service.getUserFolders()) ?? folders) : await writableFolders()
            withAnimation(.smooth(duration: 0.2)) { _ = addedFolderIds.insert(folderId) }
            Haptics.impact(.soft)
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
            try await service.addTrackToFolder(trackId: trackId, folderId: folderId)
        case let .attachmentCopy(url, fileName, fileType):
            let (data, _) = try await URLSession.shared.data(from: url)
            try await service.uploadFile(
                folderId: folderId,
                fileName: fileName ?? "audio",
                fileData: data,
                fileType: fileType ?? "application/octet-stream"
            )
        }
    }

    private func remove(from folderId: String) async throws {
        guard case let .trackMembership(trackId) = mode else { return }
        try await service.removeTrackFromFolder(trackId: trackId, folderId: folderId)
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
        case .attachmentCopy:
            return "Couldn't add to workspace. Please try again."
        }
    }
}
