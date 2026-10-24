//
//  FolderContentsScreen.swift
//  Volspire
//
//  A folder (web `folder-view`): a "‹ Workspace" band, the hero (the folder's
//  colour wash, its art, role line, name, meta, Upload / Invite), filter
//  chips, then flat "Tracks" and "Files" sections.
//

import DesignSystem
import MediaLibrary
import Services
import SwiftUI
import UniformTypeIdentifiers
import SharedUtilities

private enum FolderAction { case edit, members, delete }

struct FolderContentsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(WorkspaceStore.self) private var workspaceStore
    @State private var viewModel: FolderContentsViewModel
    @State private var pendingAction: FolderAction?
    @State private var fileForOptions: ApiFolderFile?
    /// Staged by the options sheet's Delete / Remove row; the confirmation
    /// dialog presents once that sheet has finished dismissing.
    @State private var fileToDelete: ApiFolderFile?
    @State private var showFileDeleteConfirm = false
    @State private var trackToRemove: ApiFolderFile?
    @State private var showTrackRemoveConfirm = false
    /// From Activity: the item to scroll to + highlight once the files load.
    private let highlight: FolderHighlight?
    /// The row currently lit (fades out after a moment, like a comment).
    @State private var highlightedRowId: String?
    @State private var highlightResolved = false

    init(folderId: String, folderName: String, highlight: FolderHighlight? = nil) {
        _viewModel = State(
            wrappedValue: FolderContentsViewModel(folderId: folderId, folderName: folderName)
        )
        self.highlight = highlight
    }

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    content
                        .loadingCrossfade(viewModel.loadingState)
                }
            }
            .task(id: viewModel.files.count) { await revealHighlight(proxy) }
        }
        .scrollIndicators(.hidden)
        // The hero's colour wash runs up behind a see-through band (its
        // canvas fades in once you scroll); the "…" rides in the band.
        // The back label names where it goes ("‹ Workspace"); the folder's
        // own name is the hero title right below.
        .backTitleBand("Workspace", overlaysContent: true) {
            if viewModel.isOwner {
                HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize) { viewModel.showOptions = true }
            }
        }
        .refreshable { await viewModel.refresh() }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.audio, .image, .movie, .pdf, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case let .success(urls):
                viewModel.enqueueUploads(urls: urls)
            case let .failure(error):
                debugLog("[FolderContents] File picker error: \(error)")
            }
        }
        .alert("Something went wrong", isPresented: .init(
            get: { viewModel.uploadError != nil },
            set: { if !$0 { viewModel.uploadError = nil } }
        )) {
            Button("OK") { viewModel.uploadError = nil }
        } message: {
            Text(viewModel.uploadError ?? "")
        }
        .sheet(item: $fileForOptions, onDismiss: {
            if fileToDelete != nil { showFileDeleteConfirm = true }
            if trackToRemove != nil { showTrackRemoveConfirm = true }
        }) { file in fileOptionsSheet(file) }
        .confirmationDialog("Delete file", isPresented: $showFileDeleteConfirm, titleVisibility: .visible, presenting: fileToDelete) { file in
            Button("Delete", role: .destructive) {
                fileToDelete = nil
                Task { await viewModel.deleteFile(file) }
            }
            Button("Cancel", role: .cancel) { fileToDelete = nil }
        } message: { _ in
            Text("It will be permanently deleted for everyone in this folder. This cannot be undone.")
        }
        .confirmationDialog("Remove track", isPresented: $showTrackRemoveConfirm, titleVisibility: .visible, presenting: trackToRemove) { file in
            Button("Remove", role: .destructive) {
                trackToRemove = nil
                Task { await viewModel.removeTrack(file) }
            }
            Button("Cancel", role: .cancel) { trackToRemove = nil }
        } message: { _ in
            Text("It will be removed from this folder. The original track is not affected.")
        }
        .sheet(isPresented: $viewModel.showOptions, onDismiss: runFolderAction) { optionsSheet }
        .sheet(isPresented: $viewModel.showEdit) { editSheet }
        .sheet(isPresented: $viewModel.showMembers) { ManageMembersSheet(viewModel: viewModel) }
        .destructiveConfirm(
            "Delete folder",
            isPresented: $viewModel.showDeleteConfirm,
            message: "This permanently deletes the folder and every file in it, for everyone it's shared with."
        ) {
            Task { if await viewModel.deleteFolder() { dismiss() } }
        }
        .task {
            viewModel.workspace = workspaceStore
            async let files: Void = viewModel.loadFiles()
            async let meta: Void = viewModel.loadFolderMeta()
            _ = await (files, meta)
        }
    }
}

// MARK: - Hero

private extension FolderContentsScreen {
    /// The folder's colour washes down from the top, its art sits like an
    /// album cover, and the name is display type over it.
    var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            // The cover, with the actions in a row in the far-right corner,
            // on the cover's bottom edge. Narrow phones (where the full-size
            // cover + both buttons don't fit) get the smaller cover instead.
            ViewThatFits(in: .horizontal) {
                coverRow(.lg)
                coverRow(.lgCompact)
            }

            VStack(alignment: .leading, spacing: 0) {
                if let roleLine = viewModel.roleLine {
                    Text(roleLine)
                        .font(.appCaptionMedium)
                        .foregroundStyle(Color.vText2)
                }
                Text(viewModel.folderName)
                    .font(.appTitleXXL.weight(.black))
                    .tracking(-0.6)
                    .foregroundStyle(Color.vText)
                    .lineLimit(1)
                    .padding(.top, 4)
                if !viewModel.folderDescription.isEmpty {
                    Text(viewModel.folderDescription)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText2)
                        .lineLimit(2)
                        .padding(.top, 8)
                }
                metaRow.padding(.top, 12)
            }

        }
        .padding(.horizontal, 20)
        // Clear the band the page now runs up under.
        .padding(.top, Self.backTitleBandHeight + 20)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .top) {
            // The wash from the top of the screen (behind the status bar and
            // band) down past the hero, stretching on overscroll.
            GeometryReader { geo in
                let stretch = max(0, geo.frame(in: .scrollView).minY)
                FolderPalette.wash(name: viewModel.folderName)
                    .frame(height: 320 + Self.backTitleBandHeight + stretch)
                    .offset(y: -stretch)
            }
            .allowsHitTesting(false)
        }
    }

    /// Up to 5 overlapping member avatars + "N members", "N items", "Created …".
    var metaRow: some View {
        HStack(spacing: 12) {
            if !viewModel.members.isEmpty {
                HStack(spacing: 8) {
                    HStack(spacing: -6) {
                        ForEach(viewModel.members.prefix(5)) { member in
                            AvatarView(url: viewModel.avatarURL(member.profileImageUrl), name: member.username, size: 20)
                        }
                    }
                    Text("\(viewModel.members.count) \(viewModel.members.count == 1 ? "member" : "members")")
                }
            }
            if case .loaded = viewModel.loadingState {
                Text("\(viewModel.files.count) \(viewModel.files.count == 1 ? "item" : "items")")
            }
            if let created = viewModel.folderCreatedAt {
                Text("Created \(MessageTime.agoLong(iso: created))")
            }
        }
        .font(.appCaption)
        .foregroundStyle(Color.vText2)
        .lineLimit(1)
    }

    func coverRow(_ size: FolderArt.Size) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            FolderArt(id: viewModel.folderId, name: viewModel.folderName, size: size)
            Spacer(minLength: 0)
            if viewModel.canUpload || viewModel.isOwner {
                HStack(spacing: 8) {
                    if viewModel.isOwner {
                        heroButton("Invite", icon: .userPlus, primary: false) { viewModel.showMembers = true }
                    }
                    if viewModel.canUpload {
                        heroButton("Upload", icon: .upload, primary: true) { viewModel.showFilePicker = true }
                    }
                }
                .fixedSize()
            }
        }
    }

    func heroButton(_ title: String, icon: LucideIcon.Name, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LucideIcon(icon, .md)
                Text(title).font(.appSubheadlineSemibold)
            }
            .foregroundStyle(primary ? Color.vOnInverse : Color.vControlLabel)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(primary ? Color.vInverse : Color.vControl, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Content

private extension FolderContentsScreen {
    @ViewBuilder
    var content: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            filesSkeleton
        case .error:
            LoadErrorView { Task { await viewModel.refresh() } }
                .frame(maxWidth: .infinity, minHeight: 320)
        case .loaded where viewModel.files.isEmpty && viewModel.pendingUploads.isEmpty:
            FolderEmptyState(
                artId: viewModel.folderId,
                artName: viewModel.folderName,
                title: viewModel.canUpload ? "Drop in your first file" : "Nothing here yet",
                message: viewModel.canUpload
                    ? "Stems, bounces, references. Upload audio from your files."
                    : "Files added to this folder will show up here.",
                actionTitle: viewModel.canUpload ? "Upload" : nil,
                actionIcon: .upload
            ) { viewModel.showFilePicker = true }
            .padding(.bottom, bottomInset)
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                if !viewModel.files.isEmpty { filterChips }

                // Transient file-action errors — the shared inline banner.
                if let message = viewModel.actionError {
                    ErrorBanner(message)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                }

                VStack(alignment: .leading, spacing: 32) {
                    // In-flight / failed uploads sit above the real rows.
                    if !viewModel.pendingUploads.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(viewModel.pendingUploads) { pendingUploadRow($0) }
                        }
                    }
                    if viewModel.showsTracks {
                        section("Tracks") {
                            ForEach(Array(viewModel.trackFiles.enumerated()), id: \.element.id) { i, file in
                                trackRow(file).staggeredAppear(i, in: "folder-\(ObjectIdentifier(viewModel).hashValue)")
                            }
                        }
                    }
                    if !viewModel.shownFiles.isEmpty {
                        section("Files") {
                            ForEach(Array(viewModel.shownFiles.enumerated()), id: \.element.id) { i, file in
                                fileRow(file).staggeredAppear(i + viewModel.trackFiles.count, in: "folder-\(ObjectIdentifier(viewModel).hashValue)")
                            }
                        }
                    }
                }
            }
            .padding(.bottom, bottomInset + 40)
            .animation(.easeInOut(duration: 0.2), value: viewModel.pendingUploads)
            .animation(.easeInOut(duration: 0.2), value: viewModel.actionError)
            .animation(.easeInOut(duration: 0.2), value: viewModel.filter)
        }
    }

    var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(viewModel.visibleFilters, id: \.self) { filter in
                    FilterChip(filter.rawValue.capitalized, isOn: viewModel.filter == filter) {
                        viewModel.filter = filter
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 16)
    }

    func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.appTitle3)
                .foregroundStyle(Color.vText)
                .padding(.horizontal, 20)
            // Profile-tab row spacing: 4pt apart, inset 14pt so each row's
            // own 6pt lead lands the content on the 20pt page column.
            VStack(spacing: 4) { rows() }
                .padding(.horizontal, 14)
        }
    }

    /// Optimistic row for a file that's uploading (or failed) — same anatomy
    /// as `fileRow` so the flip to the real row is seamless.
    func pendingUploadRow(_ item: PendingUpload) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.vSurface)
                if item.isFailed {
                    LucideIcon(.triangleAlert, .md).foregroundStyle(Color.vError)
                } else {
                    ProgressView().controlSize(.small).tint(Color.vText2)
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).font(.appSubheadlineMedium).foregroundStyle(Color.vTextRow).lineLimit(1)
                switch item.phase {
                case .uploading:
                    Text("Uploading…").font(.appCaption).foregroundStyle(Color.vText3)
                case let .failed(message):
                    Text(message).font(.appCaption).foregroundStyle(Color.vError).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if item.isFailed {
                Button { viewModel.retryUpload(item.id) } label: {
                    LucideIcon(.refreshCw, .md)
                        .foregroundStyle(Color.vText)
                        .frame(width: 36, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Button { viewModel.dismissUpload(item.id) } label: {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 36, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .opacity(item.isFailed ? 1 : 0.75)
    }

    /// 6 rows of a 40 tile and two bars.
    var filesSkeleton: some View {
        // The profile-row geometry, so real rows land on their bones.
        SkeletonRows(
            count: 6,
            thumb: .rounded(size: 44, radius: 8),
            line1: CGSize(width: 170, height: 12),
            line2: CGSize(width: 110, height: 10),
            thumbSpacing: 14,
            rowSpacing: 4,
            horizontalPadding: 6,
            verticalPadding: 10
        )
        .padding(.horizontal, 14)
    }

    /// Track row: the cover is the play/pause button; title only; plays in place.
    func trackRow(_ file: ApiFolderFile) -> some View {
        let mediaId = file.trackId ?? file.fileId
        let isCurrent = playerController.state.currentMediaID == MediaID(mediaId)
        let isPlaying = isCurrent && playerController.state.isPlaying
        return HStack(spacing: 14) {
            ZStack {
                if let cover = file.trackCoverUrl.flatMap({ URL(string: $0) }) {
                    ArtworkView(.webImage(cover), cornerRadius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.vSurface)
                    LucideIcon(.music, .md).foregroundStyle(Color.vText2)
                }
                if isCurrent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.5))
                    LucideIcon(isPlaying ? .pauseFill : .playFill, .md).foregroundStyle(Color.vOnColor)
                }
            }
            .frame(width: 44, height: 44)
            .coverShadow()

            Text(displayName(file))
                .font(.appSubheadlineMedium)
                .foregroundStyle(isCurrent ? Color.vText : Color.vTextRow)
                .lineLimit(1)

            Spacer(minLength: 8)

            rowMenuButton(file)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(isCurrent || highlightedRowId == file.id ? Color.vRowActive : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { play(file) }
        .id(file.id)
    }

    /// File row: audio = a round play puck, others = a type-glyph tile; name
    /// over "MP3 · 3:12 · 4.2 MB".
    func fileRow(_ file: ApiFolderFile) -> some View {
        let audio = viewModel.isAudio(file)
        let isCurrent = playerController.state.currentMediaID == MediaID(file.fileId)
        let isPlaying = isCurrent && playerController.state.isPlaying
        return HStack(spacing: 14) {
            Group {
                if audio {
                    LucideIcon(isPlaying ? .pauseFill : .playFill, .md)
                        .foregroundStyle(Color.vText)
                        .frame(width: 44, height: 44)
                        .background(Color.vSurface, in: Circle())
                } else {
                    LucideIcon(viewModel.icon(for: file), .lg)
                        .foregroundStyle(Color.vText2)
                        .frame(width: 44, height: 44)
                        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(file))
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(isCurrent ? Color.vText : Color.vTextRow)
                    .lineLimit(1)
                let caption = viewModel.fileCaption(file)
                if !caption.isEmpty {
                    Text(caption).font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            rowMenuButton(file)
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .background(isCurrent || highlightedRowId == file.id ? Color.vRowActive : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(.rect)
        .onTapGesture { play(file) }
        .id(file.id)
    }

    /// Opened from Activity: find the row the activity is about (a file, a
    /// track, or the file a comment is on), scroll to it and light it up
    /// for a moment — the same treatment as a tapped comment in the player.
    func revealHighlight(_ proxy: ScrollViewProxy) async {
        guard let highlight, !highlightResolved, !viewModel.files.isEmpty else { return }
        highlightResolved = true
        let files = viewModel.files
        var rowId: String?
        switch highlight {
        case let .file(id):
            rowId = files.first { $0.fileId.caseInsensitiveCompare(id) == .orderedSame }?.id
        case let .track(id):
            rowId = files.first { $0.trackId?.caseInsensitiveCompare(id) == .orderedSame }?.id
        case let .fileNamed(name):
            // Newest match first, in case two files share a name.
            rowId = files.sorted { $0.createdAt > $1.createdAt }
                .first { $0.name == name || displayName($0) == name }?.id
        case let .fileComment(commentId):
            // One lookup: which file the comment is on (`get_file_for_comment`).
            if let fileId = try? await SupabaseService().getFileForComment(commentId: commentId) {
                rowId = files.first { $0.fileId.caseInsensitiveCompare(fileId) == .orderedSame }?.id
            }
        }
        guard let rowId else { return }
        // Make sure it isn't filtered out of view.
        if !viewModel.shownFiles.contains(where: { $0.id == rowId }), !viewModel.trackFiles.contains(where: { $0.id == rowId }) {
            viewModel.filter = .all
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.smooth(duration: 0.35)) { proxy.scrollTo(rowId, anchor: .center) }
        withAnimation(.easeOut(duration: 0.2)) { highlightedRowId = rowId }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation(.easeOut(duration: 0.6)) { highlightedRowId = nil }
    }

    /// Always-visible ⋯ (touch has no hover).
    func rowMenuButton(_ file: ApiFolderFile) -> some View {
        Button { fileForOptions = file } label: {
            LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                .foregroundStyle(Color.vText3)
                .frame(width: 32, height: 32)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Tap an audio file (or track-reference) to play it in the player — or
    /// toggle pause when it's already the current item. The queue is every
    /// playable file in the folder, in order.
    private func play(_ tapped: ApiFolderFile) {
        guard let start = playItem(for: tapped) else { return } // non-audio → no-op
        if playerController.state.currentMediaID == MediaID(start.mediaId) {
            playerController.onPlayPause()
            return
        }
        let queue = viewModel.files.compactMap(playItem(for:))
        playerController.playWorkspace(queue, startAt: start.mediaId)
    }

    /// Maps a folder file to a play-queue item, or nil if it isn't playable audio.
    private func playItem(for file: ApiFolderFile) -> PlayerController.WorkspacePlayItem? {
        if file.type == "track", let audio = file.trackAudioUrl.flatMap({ URL(string: $0) }) {
            return .init(
                mediaId: file.trackId ?? file.fileId, fileId: nil,   // real track → track comments
                title: file.trackTitle ?? file.name, artist: file.trackArtist ?? "",
                audioURL: audio, coverURL: file.trackCoverUrl.flatMap { URL(string: $0) }
            )
        }
        if viewModel.isAudio(file), let audio = file.fileUrl.flatMap({ URL(string: $0) }) {
            return .init(
                mediaId: file.fileId, fileId: file.fileId,           // workspace file → file comments
                title: file.name, artist: file.uploaderUsername ?? "",
                audioURL: audio, coverURL: nil,
                // A file has no track detail, so its uploader has to travel with
                // the queue item for the player's artist line to be tappable.
                artistUserId: file.ownerId
            )
        }
        return nil
    }

    /// Title to show in the list — track references prefer the track title.
    func displayName(_ file: ApiFolderFile) -> String {
        if file.type == "track" { return file.trackTitle ?? file.name }
        return file.name
    }
}

// MARK: - Folder options (… menu) + edit sheet

private extension FolderContentsScreen {
    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                title: viewModel.folderName,
                subtitle: "\(viewModel.files.count) \(viewModel.files.count == 1 ? "item" : "items")",
                onClose: { viewModel.showOptions = false }
            ) {
                FolderArt(id: viewModel.folderId, name: viewModel.folderName, size: .sm)
                    .frame(width: 36, height: 36)
                    .scaleEffect(0.9)
            }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .pencil, title: "Edit folder") {
                    pendingAction = .edit; viewModel.showOptions = false
                }
                OptionSheetRow(icon: .userPlus, title: "Manage members") {
                    pendingAction = .members; viewModel.showOptions = false
                }
                OptionSheetRow(icon: .trash2, title: "Delete folder", tint: .vError) {
                    pendingAction = .delete; viewModel.showOptions = false
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// Slide-up options for a single track / file.
    func fileOptionsSheet(_ file: ApiFolderFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: file.type == "track" ? .music : viewModel.icon(for: file),
                        title: displayName(file),
                        subtitle: file.type == "track" ? file.trackArtist.map { "@\($0)" } : viewModel.fileCaption(file)) {
                fileForOptions = nil
            }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .download, title: "Download") {
                    shareFile(file)
                }
                if file.type == "track" {
                    if viewModel.canUpload {
                        OptionSheetRow(icon: .trash2, title: "Remove from folder", tint: .vError) {
                            trackToRemove = file
                            fileForOptions = nil
                        }
                    }
                } else if viewModel.canDelete(file) {
                    OptionSheetRow(icon: .trash2, title: "Delete", tint: .vError) {
                        // Stage + close the sheet; the confirmation dialog presents
                        // from the screen once the sheet is gone (see onDismiss).
                        fileToDelete = file
                        fileForOptions = nil
                    }
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// Hands the file's (already-resolved) URL to the system share sheet,
    /// which carries "Save to Files" — the phone's download.
    func shareFile(_ file: ApiFolderFile) {
        AnalyticsService.shared?.log(.shareClicked, metadata: ["kind": "file", "method": "share_sheet"])
        let items: [Any] = (file.fileUrl ?? file.trackAudioUrl).flatMap { URL(string: $0) }.map { [$0] }
            ?? [file.name]
        UIApplication.presentActivitySheet(items)
    }

    /// Runs the chosen action once the options sheet finishes dismissing.
    func runFolderAction() {
        let action = pendingAction
        pendingAction = nil
        switch action {
        case .edit: viewModel.startEditing()
        case .members: viewModel.showMembers = true
        case .delete: viewModel.showDeleteConfirm = true
        case .none: break
        }
    }

    var editSheet: some View {
        FolderFormSheet(
            icon: .pencil,
            title: "Edit Folder",
            subtitle: nil,
            name: $viewModel.editName,
            description: $viewModel.editDescription,
            actionTitle: "Save changes",
            busy: viewModel.isSaving,
            isEdit: true,
            originalName: viewModel.folderName,
            originalDescription: viewModel.folderDescription,
            onDelete: {
                viewModel.showEdit = false
                // Present the confirm after the sheet is gone.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { viewModel.showDeleteConfirm = true }
            },
            onSubmit: { await viewModel.saveEdit() }
        )
    }
}

// MARK: - Empty state (folder / workspace)

/// The empty folder / workspace: the folder's own art, a title + message,
/// and an optional CTA. Static — no bobbing art or shimmering ghost rows,
/// which read as content still loading.
struct FolderEmptyState: View {
    let artId: String
    let artName: String
    let title: String
    let message: String
    var actionTitle: String?
    var actionIcon: LucideIcon.Name = .plus
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: 20) {
            FolderArt(id: artId, name: artName, size: .md)

            VStack(spacing: 4) {
                Text(title).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                Text(message)
                    .font(.appSubheadline).foregroundStyle(Color.vText3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }

            if let actionTitle {
                Button(action: action) {
                    HStack(spacing: 8) {
                        LucideIcon(actionIcon, .md)
                        Text(actionTitle).font(.appSubheadlineSemibold)
                    }
                    .foregroundStyle(Color.vOnInverse)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(Color.vInverse, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 48)
    }
}

// MARK: - Manage Members (folder collaboration)

private struct ManageMembersSheet: View {
    @Bindable var viewModel: FolderContentsViewModel
    @Environment(\.dismiss) private var dismiss

    /// Animation keys as plain strings, so the API structs need no Equatable.
    private var resultKeys: [String] { viewModel.searchResults.map(\.userId) }
    private var memberKeys: [String] { viewModel.members.map { "\($0.userId)-\($0.role)" } }
    private var isFiltering: Bool {
        !viewModel.memberSearch.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                icon: .users,
                title: "Manage Members",
                subtitle: viewModel.folderName
            ) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    addSection
                    membersSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
                // Every list edit (add, remove, filter, role change) glides
                // instead of popping — keyed on derived ids, not the structs.
                .animation(.smooth(duration: 0.28), value: resultKeys)
                .animation(.smooth(duration: 0.28), value: memberKeys)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .sheetBackground()
        .task {
            await viewModel.loadCollaborators()
            await viewModel.loadMembers()
        }
    }

    private var addSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField

            // The list under the field is self-explaining: your remaining
            // collaborators by default, live results while typing.
            Text(isFiltering ? "Results" : "Your collaborators")
                .font(.appLabel).foregroundStyle(Color.vText3)
                .padding(.top, 4)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.2), value: isFiltering)

            if viewModel.isLoadingCollaborators && viewModel.searchResults.isEmpty {
                ProgressView().tint(Color.vText2)
                    .frame(maxWidth: .infinity).padding(.vertical, 18)
            } else if viewModel.searchResults.isEmpty {
                emptyResultsHint
                    .transition(.opacity)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.searchResults) { searchResultRow($0) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            LucideIcon(.search, .sm).foregroundStyle(Color.vText3)
            TextField("", text: $viewModel.memberSearch, prompt: Text("Search your collaborators…").foregroundColor(Color.vText3))
                .font(.appCalloutRegular).foregroundStyle(Color.vText).tint(Color.vText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if isFiltering {
                Button {
                    viewModel.memberSearch = ""
                } label: {
                    LucideIcon(.circleX, .sm)
                        .foregroundStyle(Color.vText3)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .animation(.smooth(duration: 0.2), value: isFiltering)
        .onChange(of: viewModel.memberSearch) { _, _ in Task { await viewModel.searchUsers() } }
    }

    /// Explains WHY the list is empty — no matches vs. no collaborators vs.
    /// everyone's already in — instead of silently showing nothing.
    private var emptyResultsHint: some View {
        let message: String = if isFiltering {
            "No collaborators match “\(viewModel.memberSearch.trimmingCharacters(in: .whitespaces))”."
        } else if viewModel.allCollaborators.isEmpty {
            "No collaborators yet. Connect with people from their profile, then add them here."
        } else {
            "All of your collaborators are already in this folder."
        }
        return Text(message)
            .font(.appFootnote)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func searchResultRow(_ user: ApiUserSummary) -> some View {
        HStack(spacing: 12) {
            avatar(viewModel.avatarURL(user.profileImageUrl))
            Text(user.username ?? "user").font(.appCalloutSemibold).foregroundStyle(Color.vText).lineLimit(1)
            Spacer(minLength: 8)
            if viewModel.memberActionId == user.userId {
                ProgressView().controlSize(.small).tint(Color.vText)
            } else {
                // Only the pill is tappable — the row itself is inert, so a
                // stray tap on the card can't add someone by accident.
                Button { Task { await viewModel.addMember(user) } } label: {
                    HStack(spacing: 4) {
                        LucideIcon(.plus, .xs)
                        Text("Add").font(.appCaptionMedium)
                    }
                    .foregroundStyle(Color.vOnInverse)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.vInverse, in: Capsule())
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.memberActionId != nil)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("In this folder (\(viewModel.members.count))")
                .font(.appLabel).foregroundStyle(Color.vText3)
            if viewModel.isLoadingMembers && viewModel.members.isEmpty {
                ProgressView().tint(Color.vText2).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.members) { memberCard($0) }
                }
            }
        }
    }

    private func memberCard(_ member: ApiFolderMember) -> some View {
        let isOwnerMember = member.role == "owner"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                avatar(viewModel.avatarURL(member.profileImageUrl))
                Text(member.username ?? "user").font(.appCalloutSemibold).foregroundStyle(Color.vText).lineLimit(1)
                Spacer(minLength: 8)
                if isOwnerMember {
                    HStack(spacing: 4) {
                        Text("Owner").font(.appLabel).foregroundStyle(Color.vOwnerGold)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.vOwnerGold.opacity(0.12), in: Capsule())
                } else if viewModel.memberActionId == member.userId {
                    ProgressView().controlSize(.small).tint(Color.vText)
                } else {
                    Button { Task { await viewModel.removeMember(member) } } label: {
                        Text("Remove").font(.appCaptionMedium)
                            .foregroundStyle(Color.vError)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.vDangerSoft, in: Capsule())
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !isOwnerMember {
                MemberRolePicker(member: member) { role in
                    Task { await viewModel.updateMemberRole(member, role: role) }
                }
            }
        }
        .padding(12)
        .background(Color.vCardSolid, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private func avatar(_ url: URL?) -> some View {
        AvatarView(url: url, name: nil, size: 38)
    }

}

/// The viewer/editor segmented picker on a member card. One ink
/// highlight SLIDES between segments (matched geometry) — with the role
/// updated optimistically in the view model, the slide is instant.
private struct MemberRolePicker: View {
    let member: ApiFolderMember
    let onPick: (String) -> Void

    private static let roles = ["viewer", "editor"]
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Self.roles, id: \.self) { role in
                let selected = member.role == role
                Button { onPick(role) } label: {
                    Text(role.capitalized)
                        .font(selected ? .appLabel : .appCaptionMedium)
                        .foregroundStyle(selected ? Color.vOnInverse : Color.vControlLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                                    .fill(Color.vInverse)
                                    .matchedGeometryEffect(id: "role", in: highlight)
                            } else {
                                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                                    .fill(Color.vControl)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.smooth(duration: 0.28), value: member.role)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    FolderContentsScreen(folderId: "test", folderName: "My Beats")
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
        .environment(dependencies.workspaceStore)
}
