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
    @Environment(Dependencies.self) private var dependencies
    @Environment(InboxStore.self) private var inboxStore

    @State var folderQuery = ""
    /// The folder search field is open (from the header's search icon).
    @State private var showFolderSearch = false
    @FocusState private var folderSearchFocused: Bool
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
    /// The folder sheet's in-place Delete confirm.
    @State private var folderConfirm: DestructiveConfirm?
    /// The folder whose Members sheet is open (the same sheet as its page).
    @State private var membersModel: FolderContentsViewModel?

    var pad: CGFloat { ViewConst.screenPaddings }
    /// The page has scrolled under the header (shows its hairline).
    @State private var scrolled = false

    var body: some View {
        VStack(spacing: 0) {
            // First-visit explainer (IntroModal.swift) — a zero-height anchor.
            Color.clear.frame(height: 0).introModal(.workspace, ready: workspaceStore.foldersLoaded)
            ScreenHeader("Workspace", scrolled: scrolled) {
                // Search opens the folder filter under the header (the field
                // used to sit there permanently).
                if !workspaceStore.folders.isEmpty {
                    HeaderIconButton(icon: .search) {
                        withAnimation(.smooth(duration: 0.22)) { showFolderSearch = true }
                        folderSearchFocused = true
                    }
                    .accessibilityLabel("Search folders")
                }
                HeaderIconButton(icon: .plus, size: 36) { showCreateFolder = true }
                    .accessibilityLabel("New folder")
            }
            .zIndex(1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 0).id("top")
                        workspaceContent
                            .loadingCrossfade(workspaceStore.foldersLoaded)
                    }
                    // Tight under the 44pt header bar (Settings' spacing).
                    .padding(.top, 4)
                    .padding(.bottom, playerController.contentBottomInset + 24)
                    // Activity overview open: a tap anywhere outside closes it
                    // (buttons inside still win; inactive when closed).
                    .contentShape(.rect)
                    .gesture(TapGesture().onEnded { activityExpanded = nil },
                             including: activityExpanded != nil ? .all : .subviews)
                }
                .scrollIndicators(.hidden)
                .trackScrolledPastTop($scrolled)
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
        .sheet(item: $folderForOptions, onDismiss: {
            folderConfirm = nil
            runPendingFolderAction()
        }) { folderOptionsSheet($0) }
        // Full screen, like the other edit pages.
        .fullScreenCover(item: $editingFolder) { folder in
            EditDetailsScreen(
                title: "Edit Folder",
                subtitle: "Update its name and description",
                nameLabel: "Folder name",
                namePrompt: "e.g. Album Sessions, Client Work…",
                name: $editName,
                descriptionPrompt: "What's this folder for?",
                description: $editDescription,
                hasChanges: folderEditChanged(folder),
                busy: isSavingEdit,
                onSave: { await saveEdit(folder) }
            )
        }
        .sheet(isPresented: Binding(get: { membersModel != nil }, set: { if !$0 { membersModel = nil } })) {
            if let membersModel {
                ManageMembersSheet(viewModel: membersModel)
            }
        }
    }

    // MARK: Folder "…" options

    enum FolderRowAction { case open, edit, members }

    /// The press-and-hold sheet for a folder: folder art + name, then Open,
    /// and — for your own folders — Edit, Manage members and Delete (the same
    /// options as the folder's own page).
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
                    OptionSheetRow(icon: .userPlus, title: "Manage members") {
                        pendingFolderAction = (.members, folder); folderForOptions = nil
                    }
                    OptionSheetRow(icon: .trash2, title: "Delete folder", tint: .vError) {
                        folderConfirm = DestructiveConfirm(
                            title: "Delete \"\(folder.name)\"?",
                            message: "Its files will be removed for everyone in it.",
                            actionLabel: "Delete folder"
                        ) { dependencies.contentActions.deleteFolder(id: folder.folderId) }
                    }
                }
            }
            .padding(.top, 6)
            .confirmModal($folderConfirm)
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
        case .members:
            // The folder page's own model, pointed at this folder; its role
            // comes from the shared folder list (owner = can manage).
            let model = FolderContentsViewModel(folderId: folder.folderId, folderName: folder.name)
            model.workspace = workspaceStore
            membersModel = model
            Task { await model.loadFolderMeta() }
        }
    }

    private func folderEditChanged(_ folder: ApiUserFolder) -> Bool {
        editName.trimmingCharacters(in: .whitespacesAndNewlines)
            != folder.name.trimmingCharacters(in: .whitespacesAndNewlines)
            || editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            != (folder.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Two square-art columns (the grid experiment), like Marketplace.
    private var folderColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: 2)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if !workspaceStore.foldersLoaded, workspaceStore.foldersFailed {
            // Offline / load failure with nothing to show — never "empty".
            LoadErrorView(icon: .folder, title: "Couldn't load your folders") {
                Task { await workspaceStore.refreshFolders() }
            }
            .padding(.horizontal, pad)
            .padding(.top, 40)
        } else if !workspaceStore.foldersLoaded {
            pageSkeleton
        } else if workspaceStore.folders.isEmpty {
            // The animated ghost-rows empty state (My Network / Messages / Library).
            HomeEmpty(
                title: "Your workspace is empty",
                message: "Folders hold what you share with collaborators: stems, bounces, references."
            ) {
                GhostListRows(coverRadius: Radius.tile)
            } action: {
                PrimaryButton("New folder", size: .inline, expands: false) { showCreateFolder = true }
            }
            .padding(.horizontal, pad)
        } else {
            let shown = matchingFolders
            let mine = shown.filter { $0.role.lowercased() == "owner" }
            let shared = shown.filter { $0.role.lowercased() != "owner" }
            VStack(alignment: .leading, spacing: 0) {
                // Shown from the header's search icon; × closes it and clears.
                if showFolderSearch {
                    HStack(spacing: 8) {
                        LucideIcon(.search, .sm).foregroundStyle(Color.vText3)
                        TextField("", text: $folderQuery, prompt: Text("Search folders…").foregroundColor(Color.vText3))
                            .font(.appCalloutRegular)
                            .foregroundStyle(Color.vText)
                            .autocorrectionDisabled()
                            .focused($folderSearchFocused)
                            .submitLabel(.search)
                        Button {
                            folderSearchFocused = false
                            withAnimation(.smooth(duration: 0.22)) {
                                showFolderSearch = false
                                folderQuery = ""
                            }
                        } label: {
                            LucideIcon(.x, .md)
                                .foregroundStyle(Color.vText3)
                                .frame(width: 28, height: 28)
                                .minimumHitArea(for: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close search")
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .padding(.vertical, 6)
                    .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .padding(.horizontal, pad)
                    .padding(.bottom, 24)
                    .transition(.opacity)
                }

                WorkspaceActivityRail(expanded: $activityExpanded)

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

    /// The whole page in its loaded shape — Activity rail, a folder-group
    /// heading, then the grid (or rows) — bones only, no text, so the real
    /// content lands where the skeleton was.
    private var pageSkeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            WorkspaceActivityRail.Skeleton()
            VStack(alignment: .leading, spacing: 0) {
                // "Your folders" heading.
                Capsule().fill(Color.vSkeleton).frame(width: 104, height: 14)
                    .padding(.vertical, 3)
                    .padding(.horizontal, pad)
                    .padding(.bottom, FeatureFlags.workspaceFolderGrid ? 6 : 4)
                if FeatureFlags.workspaceFolderGrid {
                    LazyVGrid(columns: folderColumns, alignment: .leading, spacing: 20) {
                        ForEach(0 ..< 4, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 10) {
                                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Color.vSkeleton)
                                    .aspectRatio(1, contentMode: .fit)
                                Capsule().fill(Color.vSkeleton).frame(width: 110, height: 10)
                                Capsule().fill(Color.vSkeleton).frame(width: 70, height: 8)
                            }
                        }
                    }
                    .padding(.horizontal, pad)
                    .padding(.top, 6)
                } else {
                    // WorkspaceFolderRow geometry: 44pt art, 14 gap, 10pt vertical.
                    ForEach(0 ..< 6, id: \.self) { _ in
                        HStack(spacing: 14) {
                            RoundedRectangle(cornerRadius: Radius.tile).fill(Color.vSkeleton).frame(width: 44, height: 44)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule().fill(Color.vSkeleton).frame(width: 150, height: 12)
                                Capsule().fill(Color.vSkeleton).frame(width: 90, height: 10)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, pad)
                        .padding(.vertical, 10)
                    }
                }
            }
            .padding(.top, 28)
            .shimmering()
        }
        .accessibilityHidden(true)
    }

    /// A group heading in the profile's section-title type.
    private func folderGroupHeader(_ title: String) -> some View {
        Text(title)
            .font(.appFont.sectionTitle)
            .foregroundStyle(Color.vText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, pad)
        .padding(.bottom, FeatureFlags.workspaceFolderGrid ? 6 : 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func folderGroup(_ title: String, _ folders: [ApiUserFolder]) -> some View {
        if !folders.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                folderGroupHeader(title)
                if FeatureFlags.workspaceFolderGrid {
                    LazyVGrid(columns: folderColumns, alignment: .leading, spacing: 20) {
                        ForEach(Array(folders.enumerated()), id: \.element.id) { i, f in
                            WorkspaceFolderCard(folder: f, onLongPress: { folderForOptions = f }) {
                                router.navigateToFolder(folderId: f.folderId, folderName: f.name)
                            }
                            .staggeredAppear(i, in: "workspace.\(title)")
                        }
                    }
                    .padding(.horizontal, pad)
                    .padding(.top, 6)
                } else {
                    ForEach(Array(folders.enumerated()), id: \.element.id) { i, f in
                        WorkspaceFolderRow(folder: f, onMore: { folderForOptions = f }) {
                            router.navigateToFolder(folderId: f.folderId, folderName: f.name)
                        }
                        .staggeredAppear(i, in: "workspace.\(title)")
                    }
                }
            }
            .padding(.top, 28)
        }
    }
}
