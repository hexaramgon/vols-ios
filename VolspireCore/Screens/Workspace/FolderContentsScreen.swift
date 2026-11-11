//
//  FolderContentsScreen.swift
//  Volspire
//
//  A folder (web `folder-view`): a "‹ Workspace" band, the hero (the folder's
//  colour wash, its art, role line, name, meta, Upload / Invite), filter
//  chips, then flat "Tracks", "Packs" (linked marketplace packs) and "Files"
//  sections.
//

import DesignSystem
import MediaLibrary
import Services
import SwiftUI
import UniformTypeIdentifiers
import SharedUtilities

private enum FolderAction { case edit, members, shareLink, publishPack }

struct FolderContentsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(Dependencies.self) private var dependencies
    @State private var viewModel: FolderContentsViewModel
    @State private var pendingAction: FolderAction?
    @State private var fileForOptions: ApiFolderFile?
    @State private var packForOptions: ApiFolderPack?
    /// Staged by the pack sheet's Remove row; confirmed once it has closed.
    @State private var pendingPackRemoval: ApiFolderPack?
    /// Staged by the options sheet's Delete / Remove row; the confirmation
    /// dialog presents once that sheet has finished dismissing.
    /// The in-place confirms in this page's "…" sheets (one sheet at a time).
    @State private var sheetConfirm: DestructiveConfirm?
    /// Downloaded and waiting for the options sheet to close, then handed to
    /// the track upload flow.
    @State private var pendingTrackPrefill: TrackFilePrefill?
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
        .backTitleBand(
            "Workspace",
            title: viewModel.folderName,
            // The hero's name (under the cover + role line) is under the band
            // by about here — the band takes it over, as on playlists.
            titleRevealAt: 180,
            overlaysContent: true
        ) {
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
        // Failures surface as the app's error toast, not a system alert.
        .onChange(of: viewModel.uploadError) { _, error in
            guard let error else { return }
            ToastCenter.shared.show(error, style: .error)
            viewModel.uploadError = nil
        }
        .sheet(item: $fileForOptions, onDismiss: {
            sheetConfirm = nil
            viewModel.cancelTrackPrefill()
            if let prefill = pendingTrackPrefill {
                pendingTrackPrefill = nil
                NotificationCenter.default.post(name: .openNewPost, object: "track",
                                                userInfo: ["trackPrefill": prefill])
            }
        }) { file in fileOptionsSheet(file) }
        .sheet(item: $packForOptions, onDismiss: confirmPackRemoval) { pack in packOptionsSheet(pack) }
        .sheet(isPresented: $viewModel.showOptions, onDismiss: {
            sheetConfirm = nil
            runFolderAction()
        }) { optionsSheet }
        // Full screen, like the other edit pages.
        .fullScreenCover(isPresented: $viewModel.showEdit) { editSheet }
        // "Publish as pack" downloading the folder.
        .refreshChip(viewModel.isPreparingPack, topInset: ViewConst.safeAreaInsets.top + 52)
        .sheet(isPresented: $viewModel.showMembers) { ManageMembersSheet(viewModel: viewModel) }
        .sheet(isPresented: $viewModel.showShareLink) {
            FolderShareLinkSheet(folderId: viewModel.folderId, folderName: viewModel.folderName,
                                 initialLink: viewModel.shareLink) { viewModel.shareLink = $0 }
        }
        .task {
            viewModel.workspace = workspaceStore
            async let files: Void = viewModel.loadFiles()
            async let meta: Void = viewModel.loadFolderMeta()
            _ = await (files, meta)
            // Needs the role from the meta load.
            await viewModel.loadShareLink()
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
                // Its own line under the meta row. The line's space is ALWAYS
                // kept, so the hero is laid out the same with or without a
                // link (none / expired): the pill just fades in or out in it.
                publicLinkPill
                    .padding(.top, 12)
                    .opacity(hasLiveShareLink ? 1 : 0)
                    .allowsHitTesting(hasLiveShareLink)
                    .accessibilityHidden(!hasLiveShareLink)
            }
            .animation(.smooth(duration: 0.25), value: hasLiveShareLink)

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

    /// "Public link" — visible while the folder has a live share link, so it's
    /// never shared silently; opens the link's sheet. Its line's space is kept
    /// either way (see `hero`).
    var publicLinkPill: some View {
        Button { viewModel.showShareLink = true } label: {
            HStack(spacing: 5) {
                LucideIcon(.link, .xs)
                Text("Public link").font(.appCaptionMedium)
            }
            .foregroundStyle(Color.vText2)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.vControl, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Manage the folder's public link")
    }

    /// Up to 5 overlapping member avatars + "N members", "N items", "Created …".
    var metaRow: some View {
        HStack(spacing: 12) {
            if !viewModel.members.isEmpty {
                // Opens the members sheet (managing for the owner, a read-only
                // list for everyone else).
                Button { viewModel.showMembers = true } label: {
                    HStack(spacing: 8) {
                        HStack(spacing: -6) {
                            ForEach(viewModel.members.prefix(5)) { member in
                                AvatarView(url: viewModel.avatarURL(member.profileImageUrl), name: member.username, size: 20)
                            }
                        }
                        Text("\(viewModel.members.count) \(viewModel.members.count == 1 ? "member" : "members")")
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint(viewModel.isOwner ? "Manage members" : "See who's in this folder")
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

    /// Whether the hero shows the "Public link" line (a live link).
    var hasLiveShareLink: Bool {
        guard let link = viewModel.shareLink else { return false }
        return !link.expired
    }

    func coverRow(_ size: FolderArt.Size) -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            FolderArt(id: viewModel.folderId, name: viewModel.folderName, size: size, showsLetter: true)
            Spacer(minLength: 0)
            if viewModel.canUpload || viewModel.isOwner {
                HStack(spacing: 8) {
                    if viewModel.isOwner {
                        HeroCapsuleButton("Invite", icon: .userPlus) { viewModel.showMembers = true }
                    }
                    if viewModel.canUpload {
                        HeroCapsuleButton("Upload", icon: .upload, primary: true) { viewModel.showFilePicker = true }
                    }
                }
                .fixedSize()
            }
        }
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
        case .loaded where viewModel.files.isEmpty && viewModel.packs.isEmpty && viewModel.pendingUploads.isEmpty:
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
                if !viewModel.files.isEmpty || !viewModel.packs.isEmpty { filterChips }

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
                    if viewModel.showsPacks {
                        section("Packs") {
                            ForEach(viewModel.packs) { packRow($0) }
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
                .font(.appFont.fileTitle)
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
                    .font(.appFont.fileTitle)
                    .foregroundStyle(isCurrent ? Color.vText : Color.vTextRow)
                    .lineLimit(1)
                let caption = viewModel.fileCaption(file)
                if !caption.isEmpty {
                    Text(caption).font(.appFont.fileSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
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

    /// A linked pack: its art (cover, else name mesh), name over
    /// "@creator · Drum Kit"; opens the pack page. An unavailable pack keeps a
    /// muted row so it can still be removed.
    func packRow(_ pack: ApiFolderPack) -> some View {
        let coverURL = pack.coverUrl.flatMap { StorageService().resolveTrackUrl($0) }.flatMap { URL(string: $0) }
        return HStack(spacing: 14) {
            Group {
                if let coverURL {
                    ArtworkView(.webImage(coverURL), cornerRadius: 8)
                } else if pack.available, let name = pack.name {
                    PlaylistCoverFallback(name: name, icon: nil)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.vSurface)
                }
            }
            .frame(width: 44, height: 44)
            .coverShadow()

            VStack(alignment: .leading, spacing: 2) {
                Text(pack.available ? (pack.name ?? "Pack") : "Pack unavailable")
                    .font(.appSubheadlineMedium)
                    .foregroundStyle(pack.available ? Color.vTextRow : Color.vText3)
                    .lineLimit(1)
                if pack.available {
                    Text([pack.creator?.username.map { "@\($0)" }, pack.packType].compactMap { $0 }.joined(separator: " · "))
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if viewModel.canUpload {
                Button { packForOptions = pack } label: {
                    LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 32, height: 32)
                        .minimumHitArea(for: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pack options")
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 10)
        .contentShape(.rect)
        .onTapGesture {
            if let api = pack.asMarketplacePack { router.navigateToMarketplacePack(api) }
        }
    }

    func packOptionsSheet(_ pack: ApiFolderPack) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .package, title: pack.name ?? "Pack",
                        subtitle: pack.creator?.username.map { "@\($0)" }) { packForOptions = nil }
            VStack(spacing: 0) {
                if let api = pack.asMarketplacePack {
                    OptionSheetRow(icon: .externalLink, title: "Open pack") {
                        packForOptions = nil
                        router.navigateToMarketplacePack(api)
                    }
                }
                OptionSheetRow(icon: .trash2, title: "Remove from folder", tint: .vDestructive) {
                    pendingPackRemoval = pack
                    packForOptions = nil
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// The pack sheet has closed: confirm, then unlink (optimistic).
    func confirmPackRemoval() {
        guard let pack = pendingPackRemoval else { return }
        pendingPackRemoval = nil
        ConfirmCenter.shared.present(DestructiveConfirm(
            title: "Remove this pack from the folder?",
            message: "The pack itself isn't affected — it just won't be linked here.",
            actionLabel: "Remove"
        ) {
            do {
                try await workspaceStore.removePack(packId: pack.packId, folderId: viewModel.folderId)
                ToastCenter.shared.show("Removed from folder")
            } catch {
                debugLog("[FolderContents] remove pack failed: \(error)")
                ToastCenter.shared.show("Only the folder owner or whoever added it can remove it.", style: .error)
            }
        })
    }

    /// Always-visible ⋯ (touch has no hover).
    func rowMenuButton(_ file: ApiFolderFile) -> some View {
        Button { fileForOptions = file } label: {
            LucideIcon(.ellipsis, size: ViewConst.heroOverlayIconSize)
                .foregroundStyle(Color.vText3)
                .frame(width: 32, height: 32)
                .minimumHitArea(for: 32)
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
                OptionSheetRow(icon: .link, title: viewModel.shareLink == nil ? "Share public link" : "Public link") {
                    pendingAction = .shareLink; viewModel.showOptions = false
                }
                // Packs are built on a computer; this is the phone's way in —
                // the folder's files, already uploaded, straight into New Pack.
                if (FeatureFlags.freePacks || FeatureFlags.marketplaceSurfaces), !viewModel.packableFiles.isEmpty {
                    OptionSheetRow(icon: .package, title: "Publish as pack",
                                   subtitle: "Open these \(viewModel.packableFiles.count) files in New Pack") {
                        pendingAction = .publishPack; viewModel.showOptions = false
                    }
                }
                OptionSheetRow(icon: .trash2, title: "Delete folder", tint: .vError) {
                    sheetConfirm = DestructiveConfirm(
                        title: "Delete this folder?",
                        message: "Every file in it is deleted for everyone it's shared with. This can't be undone.",
                        actionLabel: "Delete folder"
                    ) { deleteFolder() }
                }
            }
            .padding(.top, 6)
            .confirmModal($sheetConfirm)
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
                if viewModel.canPostAsTrack(file) {
                    OptionSheetRow(icon: .upload, title: "Post as track",
                                   subtitle: "Open it in Upload Track") {
                        Task {
                            let prefill = await viewModel.prepareTrackPrefill(file)
                            // Swiped away mid-download (that cancels it): only a
                            // still-open sheet hands the file on.
                            guard fileForOptions?.id == file.id else {
                                if let prefill { try? FileManager.default.removeItem(at: prefill.localURL) }
                                return
                            }
                            // Failure closes the sheet too, so the page's error banner shows.
                            pendingTrackPrefill = prefill
                            fileForOptions = nil
                        }
                    } trailing: {
                        if viewModel.preparingTrackFileId == file.id {
                            ProgressView().tint(Color.vText2)
                        }
                    }
                    .disabled(viewModel.preparingTrackFileId != nil)
                }
                if file.type == "track" {
                    if viewModel.canUpload {
                        OptionSheetRow(icon: .trash2, title: "Remove from folder", tint: .vError) {
                            sheetConfirm = DestructiveConfirm(
                                icon: .circleMinus,
                                title: "Remove from this folder?",
                                message: "The original track isn't affected.",
                                actionLabel: "Remove"
                            ) {
                                if let trackId = file.trackId {
                                    dependencies.contentActions.removeTrackFromFolder(trackId: trackId, folderId: viewModel.folderId)
                                }
                            }
                        }
                    }
                } else if viewModel.canDelete(file) {
                    OptionSheetRow(icon: .trash2, title: "Delete", tint: .vError) {
                        sheetConfirm = DestructiveConfirm(
                            title: "Delete this file?",
                            message: "It's deleted for everyone in this folder. This can't be undone."
                        ) {
                            dependencies.contentActions.deleteFile(
                                id: file.fileId, folderId: viewModel.folderId,
                                describe: viewModel.friendlyDeleteError
                            )
                        }
                    }
                }
            }
            .padding(.top, 6)
            .confirmModal($sheetConfirm)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// Hands the file's URL to the system share sheet, which carries "Save to
    /// Files" — the phone's download. Files are already signed; a track
    /// reference holds a track-media placeholder, signed here.
    func shareFile(_ file: ApiFolderFile) {
        AnalyticsService.shared?.log(.shareClicked, metadata: ["kind": "file", "method": "share_sheet"])
        Task {
            let raw = (file.fileUrl ?? file.trackAudioUrl).flatMap { URL(string: $0) }
            let url: URL? = if let raw { await StorageService().playableURL(raw) } else { nil }
            UIApplication.presentActivitySheet(url.map { [$0] } ?? [file.name])
        }
    }

    /// Runs the chosen action once the options sheet finishes dismissing.
    func runFolderAction() {
        let action = pendingAction
        pendingAction = nil
        switch action {
        case .edit: viewModel.startEditing()
        case .members: viewModel.showMembers = true
        case .shareLink: viewModel.showShareLink = true
        case .publishPack:
            Task {
                // The spinner chip shows while it downloads (isPreparingPack).
                guard let prefill = await viewModel.preparePackPrefill() else { return }
                NotificationCenter.default.post(name: .openNewPost, object: "sample_pack",
                                                userInfo: ["packPrefill": prefill])
            }
        case .none: break
        }
    }

    /// Optimistic folder delete (ContentActions), then leave the page —
    /// confirmed in the modal, so its sheet is already gone.
    func deleteFolder() {
        dependencies.contentActions.deleteFolder(id: viewModel.folderId)
        dismiss()
    }

    var editSheet: some View {
        EditDetailsScreen(
            title: "Edit Folder",
            subtitle: "Update its name and description",
            nameLabel: "Folder name",
            namePrompt: "e.g. Album Sessions, Client Work…",
            name: $viewModel.editName,
            descriptionPrompt: "What's this folder for?",
            description: $viewModel.editDescription,
            hasChanges: viewModel.editName.trimmingCharacters(in: .whitespacesAndNewlines)
                != viewModel.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                || viewModel.editDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                != viewModel.folderDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            busy: viewModel.isSaving,
            onSave: { await viewModel.saveEdit() }
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

struct ManageMembersSheet: View {
    @Bindable var viewModel: FolderContentsViewModel
    @Environment(\.dismiss) private var dismiss
    /// The member whose role sheet is open.
    @State private var roleTarget: ApiFolderMember?
    /// Both lists have landed — until then a skeleton holds the sheet's shape.
    @State private var loaded = false

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
                title: "Members",
                subtitle: viewModel.folderName
            ) { dismiss() }
            ScrollView {
                // Skeleton and real content are separate layers that
                // cross-fade in place once both lists have loaded, so nothing
                // glides into position as the data arrives.
                ZStack(alignment: .top) {
                    if loaded {
                        content.transition(.opacity)
                    } else {
                        skeleton.transition(.opacity)
                    }
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.25), value: loaded)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.large])
        .sheetBackground()
        .sheet(item: $roleTarget) { roleSheet($0) }
        .task {
            // The role decides the invite section; opened from the Workspace
            // hold sheet it may not be known yet (cached folder list — cheap).
            await viewModel.loadFolderMeta()
            if viewModel.isOwner { await viewModel.loadCollaborators() }
            await viewModel.loadMembers()
            loaded = true
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Only the owner invites / changes roles; members see the list.
            if viewModel.isOwner { inviteSection }
            // No "In this folder · 0" — the section appears with its first member.
            if !viewModel.members.isEmpty {
                membersSection
                    .transition(.opacity)
            }
        }
        // Every list edit (add, remove, filter, role change) glides instead
        // of popping — keyed on derived ids. Mounted after loading, so the
        // first data doesn't animate in.
        .animation(.smooth(duration: 0.28), value: resultKeys)
        .animation(.smooth(duration: 0.28), value: memberKeys)
    }

    /// The sheet's shape while loading: a still search field + rows (owner),
    /// then "In this folder" + rows.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 22) {
            if viewModel.isOwner {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        LucideIcon(.search, .sm).foregroundStyle(Color.vText3)
                        Text("Search your collaborators…").font(.appBody).foregroundStyle(Color.vText3)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color.vField, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    memberBones(count: 2)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                SheetFieldLabel("In this folder")
                memberBones(count: 3)
            }
        }
    }

    /// Rows in the person-row geometry (38pt avatar, name over role, pill).
    private func memberBones(count: Int) -> some View {
        SkeletonRows(
            count: count,
            thumb: .circle(size: 38),
            line1: CGSize(width: 120, height: 12),
            line2: CGSize(width: 90, height: 10),
            trailing: CGSize(width: Self.pillWidth, height: 32),
            thumbSpacing: 11,
            horizontalPadding: 0,
            verticalPadding: 8
        )
    }

    // MARK: Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The search field IS the top of the sheet's body — no heading.
            searchField

            if viewModel.searchResults.isEmpty {
                emptyResultsHint
                    .transition(.opacity)
            } else {
                VStack(spacing: 2) {
                    ForEach(viewModel.searchResults) { inviteRow($0) }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            LucideIcon(.search, .sm).foregroundStyle(Color.vText3)
            TextField("", text: $viewModel.memberSearch, prompt: Text("Search your collaborators…").foregroundColor(Color.vText3))
                .font(.appBody).foregroundStyle(Color.vText).tint(Color.vText)
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
        .padding(.horizontal, 12).padding(.vertical, 10)
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
            "No collaborators yet. Connect with people from their profile, then invite them here."
        } else {
            "All of your collaborators are already in this folder."
        }
        return Text(message)
            .font(.appFootnote).foregroundStyle(Color.vText3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    /// Every trailing pill here (Invite, Owner, a role ▾) — and its spinner —
    /// takes this one width, so they line up whatever the label / chevron.
    private static let pillWidth: CGFloat = 96

    private func inviteRow(_ user: ApiUserSummary) -> some View {
        personRow(url: user.profileImageUrl, name: user.username, subtitle: "Collaborator") {
            if viewModel.memberActionId == user.userId {
                ProgressView().controlSize(.small).tint(Color.vText)
                    .frame(width: Self.pillWidth)
            } else {
                // Only the pill is tappable — the row itself is inert, so a
                // stray tap can't add someone by accident.
                Button { Task { await viewModel.addMember(user) } } label: {
                    CapsuleButtonLabel(icon: .plus, title: "Invite", expands: true)
                        .frame(width: Self.pillWidth)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.memberActionId != nil)
            }
        }
    }

    // MARK: Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SheetFieldLabel("In this folder")
            VStack(spacing: 2) {
                ForEach(viewModel.members) { memberRow($0) }
            }
        }
    }

    private func memberRow(_ member: ApiFolderMember) -> some View {
        let isOwnerMember = member.role == "owner"
        return personRow(url: member.profileImageUrl, name: member.username, subtitle: Self.roleBlurb(member.role)) {
            if isOwnerMember {
                // Same capsule as a role, just not tappable.
                CapsuleButtonLabel(title: "Owner", style: .secondary, expands: true)
                    .frame(width: Self.pillWidth)
            } else if !viewModel.isOwner {
                // Read-only for members: the role, not a menu.
                CapsuleButtonLabel(title: member.role.capitalized, style: .secondary, expands: true)
                    .frame(width: Self.pillWidth)
            } else if viewModel.memberActionId == member.userId {
                ProgressView().controlSize(.small).tint(Color.vText)
                    .frame(width: Self.pillWidth)
            } else {
                roleMenu(member)
            }
        }
    }

    /// The role as the app's secondary capsule + chevron; it opens the role
    /// sheet (Editor / Viewer, Remove).
    private func roleMenu(_ member: ApiFolderMember) -> some View {
        Button { roleTarget = member } label: {
            CapsuleButtonLabel(title: member.role.capitalized, style: .secondary, expands: true, trailingIcon: .chevronDown)
                .frame(width: Self.pillWidth)
                .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.memberActionId != nil)
    }

    private func roleSheet(_ member: ApiFolderMember) -> some View {
        let name = member.username ?? "user"
        return ChoiceSheet(
            title: "@\(name)",
            subtitle: "Role in \(viewModel.folderName)",
            icon: .userCheck,
            choices: ["editor", "viewer"].map { role in
                SheetChoice(
                    icon: role == "editor" ? .pencil : .eye,
                    title: role.capitalized,
                    subtitle: Self.roleBlurb(role),
                    selected: member.role == role
                ) {
                    guard member.role != role else { return }
                    Task { await viewModel.updateMemberRole(member, role: role) }
                }
            },
            destructive: (
                title: "Remove from folder",
                icon: .userX,
                confirm: DestructiveConfirm(
                    icon: .userX,
                    title: "Remove @\(name)?",
                    message: "They'll lose access to this folder's files.",
                    actionLabel: "Remove"
                ) { await viewModel.removeMember(member) }
            )
        )
    }

    private static func roleBlurb(_ role: String) -> String {
        switch role {
        case "owner": "Manages members and files"
        case "editor": "Can add and edit files"
        default: "Can view and download"
        }
    }

    // MARK: Row

    /// One person: avatar, name / subtitle in the shared row fonts, and a
    /// trailing control — the same flat row as the collab request's tracks.
    private func personRow(
        url: String?, name: String?, subtitle: String,
        @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 11) {
            AvatarView(url: viewModel.avatarURL(url), name: name, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(name ?? "user").font(.appFont.trackTitle).foregroundStyle(Color.vTextRow).lineLimit(1)
                Text(subtitle).font(.appFont.trackSubtitle).foregroundStyle(Color.vText3).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
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
