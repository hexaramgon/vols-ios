//
//  WorkspaceScreen.swift
//  Volspire
//
//  The Workspace tab — the web phone folder column: a "Search folders…"
//  field with the "+ New" capsule, the Activity avatar rail, flat
//  folder rows grouped "Your folders" / "Shared with you", then Collaborators.
//  Notifications + Messages live in the header's top-right corner (each
//  with its unread dot).
//

import DesignSystem
import Services
import SharedUtilities
import SwiftUI

struct WorkspaceScreen: View {
    @Environment(Router.self) var router
    @Environment(PlayerController.self) private var playerController
    @Environment(WorkspaceStore.self) var workspaceStore
    @Environment(InboxStore.self) private var inboxStore

    @State var folderQuery = ""
    /// The Activity rail's open avatar (nil = closed).
    @State var activityExpanded: String?
    @State var showCreateFolder = false
    @State private var newFolderName = ""
    @State private var newFolderDescription = ""
    @State private var isCreatingFolder = false
    /// The folder whose "…" is open, and what was picked from it (run once
    /// the options sheet has finished dismissing).
    @State private var folderForOptions: ApiUserFolder?
    @State private var pendingFolderAction: (action: FolderRowAction, folder: ApiUserFolder)?
    @State private var editingFolder: ApiUserFolder?
    @State private var editName = ""
    @State private var editDescription = ""
    @State private var isSavingEdit = false
    @State private var folderToDelete: ApiUserFolder?

    var pad: CGFloat { ViewConst.screenPaddings }

    var body: some View {
        VStack(spacing: 0) {
            // First-visit explainer (IntroModal.swift) — a zero-height anchor.
            Color.clear.frame(height: 0).introModal(.workspace)
            ScreenHeader("Workspace") {
                HeaderIconButton(icon: .bell, showDot: inboxStore.unreadNotifications > 0) {
                    router.navigateToNotifications()
                }
                .accessibilityLabel("Notifications")
                HeaderIconButton(icon: .messageCircle, showDot: inboxStore.inboxHasUnread) {
                    router.navigateToMessages()
                }
                .accessibilityLabel("Messages")
            }
            .zIndex(1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        workspaceContent
                            .loadingCrossfade(workspaceStore.foldersLoaded)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, playerController.contentBottomInset + 24)
                    // Activity overview open: a tap anywhere outside closes it
                    // (buttons inside still win; inactive when closed).
                    .contentShape(.rect)
                    .gesture(TapGesture().onEnded { activityExpanded = nil },
                             including: activityExpanded != nil ? .all : .subviews)
                }
                .scrollIndicators(.hidden)
                .refreshable { await workspaceStore.refreshFolders() }
                .onChange(of: router.rootResetTick) { _, _ in
                    withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo("top", anchor: .top) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.vBase.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { await workspaceStore.loadFoldersIfNeeded() }
        .sheet(isPresented: $showCreateFolder) {
            FolderFormSheet(
                icon: .folder,
                title: "New Folder",
                subtitle: "Organize your tracks and files",
                name: $newFolderName,
                description: $newFolderDescription,
                actionTitle: "Create Folder",
                busy: isCreatingFolder,
                onSubmit: { await createFolder() }
            )
        }
        .sheet(item: $folderForOptions, onDismiss: runPendingFolderAction) { folderOptionsSheet($0) }
        .sheet(item: $editingFolder) { folder in
            FolderFormSheet(
                icon: .pencil,
                title: "Edit Folder",
                name: $editName,
                description: $editDescription,
                actionTitle: "Save changes",
                busy: isSavingEdit,
                isEdit: true,
                originalName: folder.name,
                originalDescription: folder.description ?? "",
                onSubmit: { await saveEdit(folder) }
            )
        }
        .destructiveConfirm(
            "Delete \"\(folderToDelete?.name ?? "folder")\"?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            actionLabel: "Delete folder",
            message: "Its files will be removed for everyone in it."
        ) {
            guard let folder = folderToDelete else { return }
            Task { try? await workspaceStore.deleteFolder(folderId: folder.folderId) }
        }
    }

    // MARK: Folder "…" options

    enum FolderRowAction { case open, edit, delete }

    /// The "…" sheet for a folder row: folder art + name, then Open, and —
    /// for your own folders — Edit and Delete (like a track's options).
    private func folderOptionsSheet(_ folder: ApiUserFolder) -> some View {
        let owner = folder.role == "owner"
        return VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: folder.name,
                subtitle: owner ? "Your folder" : (folder.role == "editor" ? "Shared · You can edit" : "Shared · View only"),
                onClose: { folderForOptions = nil }
            ) {
                FolderArt(id: folder.folderId, name: folder.name, size: .sm)
                    .frame(width: 36, height: 36)
                    .scaleEffect(0.9)
            }
            VStack(spacing: 0) {
                OptionSheetRow(icon: .folderOpen, title: "Open folder") {
                    pendingFolderAction = (.open, folder); folderForOptions = nil
                }
                if owner {
                    OptionSheetRow(icon: .pencil, title: "Edit folder") {
                        pendingFolderAction = (.edit, folder); folderForOptions = nil
                    }
                    OptionSheetRow(icon: .trash2, title: "Delete folder", tint: .vError) {
                        pendingFolderAction = (.delete, folder); folderForOptions = nil
                    }
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    private func runPendingFolderAction() {
        guard let (action, folder) = pendingFolderAction else { return }
        pendingFolderAction = nil
        switch action {
        case .open:
            router.navigateToFolder(folderId: folder.folderId, folderName: folder.name)
        case .edit:
            editName = folder.name
            editDescription = folder.description ?? ""
            editingFolder = folder
        case .delete:
            folderToDelete = folder
        }
    }

    private func saveEdit(_ folder: ApiUserFolder) async {
        let name = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isSavingEdit = true
        defer { isSavingEdit = false }
        let desc = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await workspaceStore.updateFolder(folderId: folder.folderId, name: name, description: desc.isEmpty ? nil : desc)
            editingFolder = nil
        } catch {
            debugLog("[Workspace] updateFolder: \(error)")
        }
    }

    /// Creates a folder via the shared store (which refetches the list in place).
    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        isCreatingFolder = true
        defer { isCreatingFolder = false }
        do {
            let desc = newFolderDescription.trimmingCharacters(in: .whitespaces)
            _ = try await workspaceStore.createFolder(name: name, description: desc.isEmpty ? nil : desc)
            newFolderName = ""
            newFolderDescription = ""
            showCreateFolder = false
        } catch {
            debugLog("[Workspace] createFolder: \(error)")
        }
    }
}

extension WorkspaceScreen {
    private var matchingFolders: [ApiUserFolder] {
        let q = folderQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let all = workspaceStore.folders
        return q.isEmpty ? all : all.filter {
            $0.name.lowercased().contains(q) || ($0.description ?? "").lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if !workspaceStore.foldersLoaded {
            VStack(spacing: 0) {
                ForEach(0 ..< 6, id: \.self) { _ in
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 40, height: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 150, height: 12)
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 90, height: 10)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
            }
            .shimmering()
        } else if workspaceStore.folders.isEmpty {
            FolderEmptyState(
                artId: "workspace", artName: "W",
                title: "Your workspace is empty",
                message: "Folders hold what you share with collaborators: stems, bounces, references.",
                actionTitle: "New folder",
                action: { showCreateFolder = true }
            )
            .padding(.top, 40)
        } else {
            let shown = matchingFolders
            let mine = shown.filter { $0.role.lowercased() == "owner" }
            let shared = shown.filter { $0.role.lowercased() != "owner" }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        LucideIcon(.search, .md).foregroundStyle(Color.vText3)
                        TextField("", text: $folderQuery, prompt: Text("Search folders…").foregroundColor(Color.vText3))
                            .font(.appSubheadline)
                            .foregroundStyle(Color.vText)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    NewCapsuleButton { showCreateFolder = true }
                }
                .padding(.horizontal, pad)

                WorkspaceActivityRail(expanded: $activityExpanded)
                    .padding(.top, 24)

                if shown.isEmpty {
                    Text("No folders match \"\(folderQuery)\"")
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText3)
                        .padding(.horizontal, pad)
                        .padding(.top, 24)
                } else {
                    folderGroup("Your folders", mine)
                    folderGroup("Shared with you", shared)
                }

            }
        }
    }

    @ViewBuilder
    private func folderGroup(_ title: String, _ folders: [ApiUserFolder]) -> some View {
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.appFont.sectionLabel)
                    .foregroundStyle(Color.vText3)
                    .padding(.horizontal, pad)
                    .padding(.bottom, 4)
                ForEach(Array(folders.enumerated()), id: \.element.id) { i, f in
                    WorkspaceFolderRow(folder: f, onMore: { folderForOptions = f }) {
                        router.navigateToFolder(folderId: f.folderId, folderName: f.name)
                    }
                    .staggeredAppear(i, in: "workspace.\(title)")
                }
            }
            .padding(.top, 24)
        }
    }
}
