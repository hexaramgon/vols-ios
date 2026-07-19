//
//  FolderContentsScreen.swift
//  Volspire
//
//  A folder's files — themed list with the shared nav header and an upload
//  action in the top-right corner.
//

import DesignSystem
import Services
import SwiftUI
import UniformTypeIdentifiers
import SharedUtilities

private enum FolderAction { case edit, members, delete }

struct FolderContentsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @State private var viewModel: FolderContentsViewModel
    @State private var pendingAction: FolderAction?
    @State private var fileForOptions: ApiFolderFile?
    /// Staged by the options sheet's Delete row; the confirmation dialog
    /// presents once that sheet has finished dismissing.
    @State private var fileToDelete: ApiFolderFile?
    @State private var showFileDeleteConfirm = false

    init(folderId: String, folderName: String) {
        _viewModel = State(
            wrappedValue: FolderContentsViewModel(folderId: folderId, folderName: folderName)
        )
    }

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: viewModel.folderName, collapsing: true, onBack: { dismiss() }) {
            if viewModel.isOwner { optionsButton }
        }
        // The + never turns into a spinner: uploads show as optimistic rows in
        // the list itself, so the button stays available for adding more.
        .floatingAction(owner: "folderContents", systemImage: "plus") {
            viewModel.showFilePicker = true
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
        }) { file in fileOptionsSheet(file) }
        .confirmationDialog("Delete this file?", isPresented: $showFileDeleteConfirm, titleVisibility: .visible, presenting: fileToDelete) { file in
            Button("Delete", role: .destructive) {
                fileToDelete = nil
                Task { await viewModel.deleteFile(file) }
            }
            Button("Cancel", role: .cancel) { fileToDelete = nil }
        } message: { file in
            Text("“\(displayName(file))” will be removed for everyone in this folder.")
        }
        .sheet(isPresented: $viewModel.showOptions, onDismiss: runFolderAction) { optionsSheet }
        .sheet(isPresented: $viewModel.showEdit) { editSheet }
        .sheet(isPresented: $viewModel.showMembers) { ManageMembersSheet(viewModel: viewModel) }
        .destructiveConfirm(
            "Delete this folder?",
            isPresented: $viewModel.showDeleteConfirm,
            message: "This permanently deletes the folder and its files."
        ) {
            Task { if await viewModel.deleteFolder() { dismiss() } }
        }
        .task {
            await viewModel.loadFiles()
            await viewModel.loadFolderMeta()
        }
    }

    /// Top-right "…" — folder options (owner only).
    private var optionsButton: some View {
        Button { viewModel.showOptions = true } label: {
            LucideIcon(.ellipsis, size: ViewConst.headerIconSize)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
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
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        case .loaded where viewModel.files.isEmpty && viewModel.pendingUploads.isEmpty:
            // minHeight (not `centered:`) — inside a ScrollView a max-height fill
            // collapses, so the empty state centers via a fixed minimum instead.
            EmptyStateView(icon: .folder, title: "No files yet", message: "Upload files to share them in this folder.")
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.55)
        case .loaded:
            LazyVStack(spacing: 0) {
                // Transient file-action errors (e.g. deleting someone else's
                // file) — the shared inline banner, auto-dismissing.
                if let message = viewModel.actionError {
                    ErrorBanner(message)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                        .transition(.opacity)
                }
                // In-flight / failed uploads sit above the real rows and animate
                // out once the server row replaces them.
                ForEach(viewModel.pendingUploads) { pendingUploadRow($0) }
                ForEach(Array(viewModel.files.enumerated()), id: \.element.id) { idx, file in
                    fileRow(file, isLast: idx == viewModel.files.count - 1)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, bottomInset)
            .animation(.easeInOut(duration: 0.25), value: viewModel.pendingUploads)
            .animation(.easeInOut(duration: 0.25), value: viewModel.actionError)
        }
    }

    /// Optimistic row for a file that's uploading (or failed) — same anatomy
    /// as `fileRow` so the flip to the real row is seamless.
    func pendingUploadRow(_ item: PendingUpload) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                if item.isFailed {
                    LucideIcon(.triangleAlert, .md).foregroundStyle(Color.vError)
                } else {
                    ProgressView().controlSize(.small).tint(.white.opacity(0.7))
                }
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.fileName).font(.appCallout).foregroundStyle(.white).lineLimit(1)
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
                        .foregroundStyle(.white)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .opacity(item.isFailed ? 1 : 0.75)
    }

    /// Shimmering placeholder rows shown while the folder's files load —
    /// mirrors `fileRow`'s 46pt thumbnail + two text lines.
    var filesSkeleton: some View {
        SkeletonRows(
            count: 8,
            thumb: .rounded(size: 46, radius: 11),
            line1: CGSize(width: 170, height: 13),
            line2: CGSize(width: 110, height: 11),
            horizontalPadding: 14
        )
        .padding(.top, 4)
    }

    func fileRow(_ file: ApiFolderFile, isLast: Bool) -> some View {
        HStack(spacing: 13) {
            fileThumbnail(file)
                .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(file)).font(.appCallout).foregroundStyle(.white).lineLimit(1)
                metadataRow(file)
            }

            Spacer(minLength: 8)

            Button { fileForOptions = file } label: {
                LucideIcon(.ellipsis, .xl)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle().fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, 73) // under the name (14 + icon 46 + spacing 13)
            }
        }
        .contentShape(.rect)
        .onTapGesture { play(file) }
    }

    /// Tap an audio file (or track-reference) to play it in the player. The queue
    /// is every playable file in the folder, in order, so Next/Previous move
    /// through the folder; file items open straight to comments.
    private func play(_ tapped: ApiFolderFile) {
        guard let start = playItem(for: tapped) else { return } // non-audio → no-op
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
        if (file.fileType?.contains("audio") ?? false), let audio = file.fileUrl.flatMap({ URL(string: $0) }) {
            return .init(
                mediaId: file.fileId, fileId: file.fileId,           // workspace file → file comments
                title: file.name, artist: file.uploaderUsername ?? "",
                audioURL: audio, coverURL: nil
            )
        }
        return nil
    }

    /// Track references show their real album cover (so public tracks are visually
    /// distinct from plain uploads); everything else gets a neutral, on-theme icon.
    @ViewBuilder
    func fileThumbnail(_ file: ApiFolderFile, cornerRadius: CGFloat = 11, iconSize: CGFloat = 18) -> some View {
        if file.type == "track", let cover = file.trackCoverUrl.flatMap({ URL(string: $0) }) {
            ArtworkView(.webImage(cover), cornerRadius: cornerRadius)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(viewModel.iconColor(for: file).opacity(0.16))
                Image(systemName: file.type == "track" ? "music.note" : viewModel.icon(for: file))
                    .font(.system(size: iconSize))
                    .foregroundStyle(viewModel.iconColor(for: file))
            }
        }
    }

    /// Title to show in the list — track references prefer the track title.
    func displayName(_ file: ApiFolderFile) -> String {
        if file.type == "track" { return file.trackTitle ?? file.name }
        return file.name
    }

    /// Subtitle line: tracks show "@artist · Track · time" (no meaningless "Zero KB");
    /// plain files show size · duration · time.
    @ViewBuilder
    func metadataRow(_ file: ApiFolderFile) -> some View {
        HStack(spacing: 6) {
            if file.type == "track" {
                if let artist = file.trackArtist, !artist.isEmpty {
                    Text("@\(artist)").font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                    Text("·").foregroundStyle(Color.vText3)
                }
                Text("TRACK").font(.appCaption2Semibold).tracking(0.4).foregroundStyle(Color.brand)
                Text("·").foregroundStyle(Color.vText3)
                Text(viewModel.relativeTime(from: file.createdAt)).font(.appCaption).foregroundStyle(Color.vText3)
            } else {
                if let size = viewModel.formattedSize(for: file) {
                    Text(size).font(.appCaption).foregroundStyle(Color.vText3)
                    Text("·").foregroundStyle(Color.vText3)
                }
                if let duration = viewModel.formattedDuration(for: file) {
                    Text(duration).font(.appCaption).foregroundStyle(Color.vText3)
                    Text("·").foregroundStyle(Color.vText3)
                }
                Text(viewModel.relativeTime(from: file.createdAt)).font(.appCaption).foregroundStyle(Color.vText3)
            }
        }
        .lineLimit(1)
    }

}

// MARK: - Folder options (… menu) + rename sheet

private extension FolderContentsScreen {
    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .folder,
                title: viewModel.folderName,
                subtitle: "\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s")"
            ) { viewModel.showOptions = false }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .squarePen, title: "Edit folder") {
                    pendingAction = .edit; viewModel.showOptions = false
                }
                OptionSheetRow(icon: .users, title: "Manage members") {
                    pendingAction = .members; viewModel.showOptions = false
                }
                OptionSheetRow(icon: .trash2, title: "Delete folder", tint: .vDestructive) {
                    pendingAction = .delete; viewModel.showOptions = false
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// Slide-up options for a single file/track (mirrors the track sheet pattern).
    func fileOptionsSheet(_ file: ApiFolderFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: displayName(file), subtitle: fileMeta(file)) {
                fileForOptions = nil
            } leading: {
                fileThumbnail(file, cornerRadius: 11, iconSize: 18)
                    .frame(width: 36, height: 36)
            }

            VStack(spacing: 2) {
                OptionSheetRow(icon: .share2, title: "Share") {
                    shareFile(file)
                }
                OptionSheetRow(icon: .trash2, title: "Delete", tint: .vDestructive) {
                    // Stage + close the sheet; the confirmation dialog presents
                    // from the screen once the sheet is gone (see onDismiss).
                    fileToDelete = file
                    fileForOptions = nil
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// Summary line for the options-sheet header — artist/"Track" for references,
    /// size · duration for plain files.
    func fileMeta(_ file: ApiFolderFile) -> String? {
        if file.type == "track" {
            var parts: [String] = []
            if let artist = file.trackArtist, !artist.isEmpty { parts.append("@\(artist)") }
            parts.append("Track")
            return parts.joined(separator: " · ")
        }
        var parts: [String] = []
        if let size = viewModel.formattedSize(for: file) { parts.append(size) }
        if let duration = viewModel.formattedDuration(for: file) { parts.append(duration) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Shares the file's (already-resolved) URL via the system share sheet,
    /// presented on top of the options sheet.
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
            icon: .squarePen,
            title: "Edit Folder",
            subtitle: "Update its name or description",
            name: $viewModel.editName,
            description: $viewModel.editDescription,
            actionTitle: "Save Changes",
            busy: viewModel.isSaving,
            onSubmit: { await viewModel.saveEdit() }
        )
    }
}

// MARK: - Manage Members (folder collaboration)

private struct ManageMembersSheet: View {
    @Bindable var viewModel: FolderContentsViewModel
    @Environment(\.dismiss) private var dismiss

    private let roles = ["viewer", "editor", "admin"]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                icon: .users,
                title: "Manage Members",
                subtitle: viewModel.folderName
            ) { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    addSection
                    membersSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD MEMBERS").font(.appLabel).tracking(0.6).foregroundStyle(.white.opacity(0.45))
            HStack(spacing: 8) {
                LucideIcon(.search, .sm).foregroundStyle(.white.opacity(0.4))
                TextField("", text: $viewModel.memberSearch, prompt: Text("Search collaborators…").foregroundColor(.white.opacity(0.35)))
                    .font(.appCalloutRegular).foregroundStyle(.white).tint(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if viewModel.isSearchingUsers { ProgressView().controlSize(.small).tint(.white) }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .onChange(of: viewModel.memberSearch) { _, _ in Task { await viewModel.searchUsers() } }

            if !viewModel.searchResults.isEmpty {
                VStack(spacing: 2) {
                    ForEach(viewModel.searchResults) { searchResultRow($0) }
                }
                .padding(.top, 2)
            }
        }
    }

    private func searchResultRow(_ user: ApiUserSummary) -> some View {
        Button { Task { await viewModel.addMember(user) } } label: {
            HStack(spacing: 12) {
                avatar(viewModel.avatarURL(user.profileImageUrl))
                Text(user.username ?? "user").font(.appCallout).foregroundStyle(.white).lineLimit(1)
                Spacer()
                if viewModel.memberActionId == user.userId {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    LucideIcon(.circlePlus, .lg).foregroundStyle(Color.brand)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.memberActionId != nil)
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MEMBERS (\(viewModel.members.count))").font(.appLabel).tracking(0.6).foregroundStyle(.white.opacity(0.45))
            if viewModel.isLoadingMembers && viewModel.members.isEmpty {
                ProgressView().tint(.white.opacity(0.6)).frame(maxWidth: .infinity).padding(.vertical, 30)
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.username ?? "user").font(.appCalloutSemibold).foregroundStyle(.white).lineLimit(1)
                    Text(roleDescription(member.role)).font(.appCaption).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 8)
                if isOwnerMember {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(Color.vOwnerGold)
                        Text("Owner").font(.appLabel).foregroundStyle(Color.vOwnerGold)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.vOwnerGold.opacity(0.12), in: Capsule())
                } else if viewModel.memberActionId == member.userId {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Button { Task { await viewModel.removeMember(member) } } label: {
                        LucideIcon(.circleX, .lg).foregroundStyle(Color.vDestructive)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !isOwnerMember {
                HStack(spacing: 6) {
                    ForEach(roles, id: \.self) { roleChip(member: member, role: $0) }
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func roleChip(member: ApiFolderMember, role: String) -> some View {
        let selected = member.role == role
        return Button { Task { await viewModel.updateMemberRole(member, role: role) } } label: {
            Text(role.capitalized)
                .font(selected ? .appLabel : .appCaptionMedium)
                .foregroundStyle(selected ? .white : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(selected ? AnyShapeStyle(LinearGradient.sendAccent) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func avatar(_ url: URL?) -> some View {
        AvatarView(url: url, name: nil, size: 38)
    }

    private func roleDescription(_ role: String) -> String {
        switch role {
        case "owner": "Full control over the folder"
        case "admin": "Can manage folder and members"
        case "editor": "Can view, upload, and edit files"
        default: "Can only view files"
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    FolderContentsScreen(folderId: "test", folderName: "My Beats")
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
