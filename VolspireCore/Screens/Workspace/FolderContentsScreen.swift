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

private enum FolderAction { case edit, members, delete }

struct FolderContentsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @State private var viewModel: FolderContentsViewModel
    @State private var pendingAction: FolderAction?
    @State private var fileForOptions: ApiFolderFile?

    init(folderId: String, folderName: String) {
        _viewModel = State(
            wrappedValue: FolderContentsViewModel(folderId: folderId, folderName: folderName)
        )
    }

    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: viewModel.folderName, collapsing: true) { dismiss() }
        .toolbar {
            if viewModel.isOwner {
                ToolbarItem(placement: .topBarTrailing) { optionsButton }
            }
        }
        .floatingAction(owner: "folderContents", systemImage: "plus", isBusy: viewModel.isUploading) {
            viewModel.showFilePicker = true
        }
        .refreshable { await viewModel.refresh() }
        .fileImporter(
            isPresented: $viewModel.showFilePicker,
            allowedContentTypes: [.audio, .image, .movie, .pdf, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first { Task { await viewModel.uploadFile(url: url) } }
            case let .failure(error):
                print("[FolderContents] File picker error: \(error)")
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
        .sheet(item: $fileForOptions) { file in fileOptionsSheet(file) }
        .sheet(isPresented: $viewModel.showOptions, onDismiss: runFolderAction) { optionsSheet }
        .sheet(isPresented: $viewModel.showEdit) { editSheet }
        .sheet(isPresented: $viewModel.showMembers) { ManageMembersSheet(viewModel: viewModel) }
        .confirmationDialog("Delete this folder?", isPresented: $viewModel.showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { if await viewModel.deleteFolder() { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the folder and its files.")
        }
        .task {
            await viewModel.loadFiles()
            await viewModel.loadFolderMeta()
        }
    }

    /// Top-right "…" — folder options (owner only).
    private var optionsButton: some View {
        Button { viewModel.showOptions = true } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
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
        case .loaded where viewModel.files.isEmpty:
            stateView(icon: .folder, title: "No files yet", message: "Upload files to share them in this folder.")
        case .loaded:
            LazyVStack(spacing: 0) {
                ForEach(Array(viewModel.files.enumerated()), id: \.element.id) { idx, file in
                    fileRow(file, isLast: idx == viewModel.files.count - 1)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, bottomInset)
        }
    }

    /// Shimmering placeholder rows shown while the folder's files load —
    /// mirrors `fileRow`'s 46pt thumbnail + two text lines.
    var filesSkeleton: some View {
        let bone = Color.white.opacity(0.06)
        return LazyVStack(spacing: 0) {
            ForEach(0 ..< 8, id: \.self) { _ in
                HStack(spacing: 13) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(bone)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(bone).frame(width: 170, height: 13)
                        Capsule().fill(bone).frame(width: 110, height: 11)
                    }
                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .padding(.top, 4)
        .shimmering()
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

    func stateView(icon: LucideIcon.Name, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            LucideIcon(icon, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            Text(message).font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.55)
        .padding(.horizontal, 40)
    }
}

// MARK: - Folder options (… menu) + rename sheet

private extension FolderContentsScreen {
    var optionsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.08))
                    LucideIcon(.folder, .lg).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.folderName).font(.appTitle3Bold).foregroundStyle(.white).lineLimit(1)
                    Text("\(viewModel.files.count) file\(viewModel.files.count == 1 ? "" : "s")")
                        .font(.appFootnote).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            VStack(spacing: 2) {
                folderRow(icon: .squarePen, title: "Edit folder") {
                    pendingAction = .edit; viewModel.showOptions = false
                }
                folderRow(icon: .users, title: "Manage members") {
                    pendingAction = .members; viewModel.showOptions = false
                }
                folderRow(icon: .trash2, title: "Delete folder", tint: Color(red: 1, green: 0.37, blue: 0.37)) {
                    pendingAction = .delete; viewModel.showOptions = false
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(316)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
    }

    func folderRow(icon: LucideIcon.Name, title: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                LucideIcon(icon, .lg)
                    .foregroundStyle(tint)
                    .frame(width: 26, alignment: .center)
                Text(title)
                    .font(.appBodyLargeMedium)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(FolderRowStyle())
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
                folderRow(icon: .share2, title: "Share") {
                    shareFile(file)
                }
                folderRow(icon: .trash2, title: "Delete", tint: Color(red: 1, green: 0.37, blue: 0.37)) {
                    fileForOptions = nil
                    Task { await viewModel.deleteFile(file) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.visible)
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
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        var presenter = root
        while let presented = presenter.presentedViewController { presenter = presented }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
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

/// Subtle press highlight for the flat folder-menu rows.
private struct FolderRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0))
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
        .environment(\.colorScheme, .dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private func searchResultRow(_ user: ApiUserSearchResult) -> some View {
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
                        Image(systemName: "crown.fill").font(.system(size: 10)).foregroundStyle(Color(red: 1, green: 0.84, blue: 0))
                        Text("Owner").font(.appLabel).foregroundStyle(Color(red: 1, green: 0.84, blue: 0))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color(red: 1, green: 0.84, blue: 0).opacity(0.12), in: Capsule())
                } else if viewModel.memberActionId == member.userId {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Button { Task { await viewModel.removeMember(member) } } label: {
                        LucideIcon(.circleX, .lg).foregroundStyle(Color(red: 1, green: 0.37, blue: 0.37))
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
                .background(selected ? Color.brand : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func avatar(_ url: URL?) -> some View {
        Group {
            if let url {
                ArtworkView(.webImage(url), cornerRadius: 19)
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    LucideIcon(.user, .md).foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
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
