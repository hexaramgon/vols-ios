//
//  ConversationScreen.swift
//  Volspire
//
//  A single chat thread — sleek header, grouped message bubbles (accent for the
//  current user, dark surface for the other) with tails + time dividers, and a
//  modern keyboard-aware input bar with photo/file attachments.
//

import AVFoundation
import DesignSystem
import Kingfisher
import MediaLibrary
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Stable Kingfisher cache key for a signed attachment URL: drops the volatile
/// token/expiry query so a re-signed URL (a new token is minted on every load and
/// poll) reuses the cached image instead of re-downloading it every time.
private func attachmentCacheKey(_ url: URL) -> String {
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    comps?.query = nil
    return comps?.string ?? url.absoluteString
}

/// Accent fill for the current user's bubbles + send button — the shared
/// send-accent gradient, so chat and player comments match.
private let accentGradient = LinearGradient.sendAccent

struct ConversationScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(Router.self) private var router
    @Environment(ConversationState.self) private var conversationState

    let conversation: ActiveConversation
    var onBack: (() -> Void)? = nil

    @State private var viewModel: ConversationViewModel?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let viewModel {
                ChatThread(viewModel: viewModel, otherUsername: conversation.username)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vBase.ignoresSafeArea())
        .task {
            let vm = viewModel ?? ConversationViewModel(
                convoId: conversation.convoId,
                currentUserId: dependencies.authManager.currentUserId
            )
            viewModel = vm
            // Fetch runs concurrently with the push; the thread renders only
            // once the transition has settled (see load(settleDelay:)).
            await vm.load(settleDelay: .seconds(0.45))
            await vm.startPolling()
        }
        // Custom header — hide the system bar; re-enable the native edge-swipe
        // pop (a hidden bar disables it) so back behaves like every other screen.
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .onAppear { conversationState.activeConversation = conversation }
        .onDisappear {
            if conversationState.activeConversation == conversation {
                conversationState.activeConversation = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                // Drop the keyboard first so the input bar doesn't strand mid-screen
                // during the pop animation (matches the swipe-back behaviour).
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                if let onBack { onBack() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                    // Match the toolbar-rendered chevron (MessageCategoryScreen /
                    // appNavBar): nav-bar bar-button symbols get the `.large` scale
                    // by default, so a custom-drawn one needs it too to read the same.
                    .imageScale(.large)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Avatar + name open the sender's profile (slides in on the nav stack).
            Button {
                guard let otherUserId = conversation.otherUserId else { return }
                router.navigateToProfile(userId: otherUserId)
            } label: {
                HStack(spacing: 11) {
                    avatar
                    VStack(alignment: .leading, spacing: 1) {
                        Text(conversation.username)
                            .font(.appBodyLargeSemibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        // Context line for the ✕/✓ (or the grey Pending chip) next
                        // to it — only while a request is awaiting a response.
                        if pendingCollabRequest != nil {
                            Text("Wants to collaborate")
                                .font(.appCaption2Medium)
                                .foregroundStyle(Color.vText3)
                                .lineLimit(1)
                        } else if awaitingCollabRequest != nil {
                            Text("Collab request sent")
                                .font(.appCaption2Medium)
                                .foregroundStyle(Color.vText3)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(conversation.otherUserId == nil)

            Spacer(minLength: 0)

            // A pending collab request the other person sent → decline / accept
            // right here in the header (✕ / ✓), instead of buttons in the thread.
            // One I sent → a grey Pending chip in the same spot until they respond.
            if let request = pendingCollabRequest {
                collabResponseButtons(request)
            } else if awaitingCollabRequest != nil {
                pendingChip
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, ViewConst.screenPaddings)
        .padding(.top, 4)
        .padding(.bottom, 10)
        .background {
            Color.vBase
                .overlay(alignment: .bottom) { Rectangle().fill(Color.vBorder).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        }
    }

    /// The one pending collab request the other user sent me (rate-limited to one
    /// per week, so at most one), drives the header accept/decline controls.
    private var pendingCollabRequest: ChatMessage? {
        viewModel?.messages.first { $0.isCollabRequest && !$0.isFromMe && $0.isPendingRequest }
    }

    /// The mirror case — a request I sent that the other party hasn't answered.
    private var awaitingCollabRequest: ChatMessage? {
        viewModel?.messages.first { $0.isCollabRequest && $0.isFromMe && $0.isPendingRequest }
    }

    /// Sender-side counterpart of the ✕/✓ buttons: nothing to act on, so an
    /// all-grey chip holds the spot until the other party accepts or declines
    /// (the 4s poll clears it live).
    private var pendingChip: some View {
        HStack(spacing: 6) {
            LucideIcon(.clock, .sm)
            Text("Pending").font(.appFootnoteSemibold)
        }
        .foregroundStyle(Color.vText2)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.white.opacity(0.08), in: Capsule())
        .transition(.scale.combined(with: .opacity))
    }

    private func collabResponseButtons(_ request: ChatMessage) -> some View {
        HStack(spacing: 10) {
            Button { Task { await viewModel?.respondToRequest(request, accept: false) } } label: {
                LucideIcon(.x, .lg)
                    .foregroundStyle(Color.vError)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)

            Button { Task { await viewModel?.respondToRequest(request, accept: true) } } label: {
                LucideIcon(.check, .lg)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.green, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var avatar: some View {
        Group {
            if let urlString = conversation.avatarURL, let url = URL(string: urlString) {
                KFImage(url).downsampled(to: 40).resizable().scaledToFill()
            } else {
                Text(String(conversation.username.first ?? "?").uppercased())
                    .font(.appHeadline)
                    .foregroundStyle(Color.vText2)
            }
        }
        .frame(width: 40, height: 40)
        .background(Color.vSurface)
        .clipShape(Circle())
    }
}

// MARK: - Thread (messages + input)

private enum CollabMessage {
    /// The collab composer historically appended "🎵 Title — …/track/{id}" lines to
    /// the pitch. The cards now come from structured metadata (`SharedTrack`), so we
    /// only strip those lines out to recover a clean caption (older messages still
    /// carry them; new ones may not).
    static func strippedCaption(_ text: String) -> String {
        guard text.contains("volspire.com/track/") else { return text }
        let pattern = "\\s*🎵\\s*[^\\n]*?—\\s*https?://\\S*?volspire\\.com/track/[0-9a-fA-F-]{36}"
        let stripped = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A photo/file picked but not yet sent — staged in the input bar with a preview
/// so the user can add a caption and send it deliberately (not on pick).
private struct PendingAttachment {
    let data: Data
    let fileName: String
    let fileType: String
    let previewImage: UIImage?
}

/// An audio attachment staged for "Add to Workspace" (sheet item).
private struct WorkspaceAttachmentTarget: Identifiable {
    let id = UUID()
    let url: URL
    let name: String?
    let type: String?
}

private struct ChatThread: View {
    @Bindable var viewModel: ConversationViewModel
    /// The other participant's handle — used by the collab status messages.
    let otherUsername: String
    @Environment(\.openURL) private var openURL
    @Environment(AvatarPreviewState.self) private var avatarPreview
    @Environment(PlayerController.self) private var playerController
    @Environment(Router.self) private var router

    @FocusState private var inputFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    /// Custom "Photo / File" attachment popup, anchored above the + button.
    @State private var showAttachMenu = false
    /// A picked photo/file staged in the input bar — sent only when send is tapped.
    @State private var pendingAttachment: PendingAttachment?
    /// On-screen frame of each image bubble, so tapping one zooms it from its spot.
    @State private var imageFrames: [String: CGRect] = [:]
    /// Audio attachment staged for "Add to Workspace" (drives the folder picker).
    @State private var workspaceTarget: WorkspaceAttachmentTarget?
    /// Audio attachment whose long-press options sheet is open.
    @State private var optionsTarget: WorkspaceAttachmentTarget?

    private let bottomAnchor = "thread-bottom"

    private var canSend: Bool {
        let hasText = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || pendingAttachment != nil) && !viewModel.isSending
    }

    var body: some View {
        Group {
            if !viewModel.messages.isEmpty {
                messageList
            } else if viewModel.loadingState == .loaded {
                emptyState
            } else {
                ThreadSkeleton()
            }
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.messages.isEmpty)
        .animation(.easeOut(duration: 0.25), value: viewModel.loadingState)
        // Tap anywhere in the thread to dismiss the attachment popup.
        .overlay {
            if showAttachMenu {
                Color.black.opacity(0.001)
                    .contentShape(.rect)
                    .onTapGesture { closeAttachMenu() }
            }
        }
        // Custom attachment popup — anchored just above the + button (which lives
        // at the leading edge of the input bar), not a bottom sheet.
        .overlay(alignment: .bottomLeading) {
            if showAttachMenu {
                attachMenuPopup
                    .padding(.leading, ViewConst.screenPaddings)
                    .padding(.bottom, 10)
                    .transition(.scale(scale: 0.9, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in handlePhoto(item) }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf, .audio, .movie, .plainText, .data],
            allowsMultipleSelection: false
        ) { handleFile($0) }
        .alert("Attachment", isPresented: Binding(
            get: { viewModel.attachmentError != nil },
            set: { if !$0 { viewModel.attachmentError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.attachmentError ?? "")
        }
        // "Add to Workspace" for an audio attachment — pick a folder to copy it into.
        .sheet(item: $workspaceTarget) { target in
            AttachmentFolderPicker(url: target.url, fileName: target.name, fileType: target.type)
        }
        // Long-press options for an audio attachment — same sheet style as the
        // track "…" menus everywhere else in the app.
        .sheet(item: $optionsTarget) { target in
            TrackOptionsSheet(
                artwork: .placeholder(name: target.name),
                title: target.name ?? "Audio",
                meta: (target.name as NSString?)?.pathExtension.uppercased(),
                actions: [
                    .init(icon: .folderPlus, title: "Add to Workspace", subtitle: "Copy this file into a folder") {
                        workspaceTarget = target
                    },
                    .init(icon: .share2, title: "Share", subtitle: "Save to Files or send it on", dismissesSheet: false) {
                        await shareAttachment(target)
                    },
                ]
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .presentationDragIndicator(.visible)
            .sheetBackground()
        }
    }

    /// Downloads the attachment to a temp file and presents the share sheet
    /// (over the options sheet, which stays up — same pattern as track share).
    private func shareAttachment(_ target: WorkspaceAttachmentTarget) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: target.url)
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(target.name ?? "audio")
            try data.write(to: tmp, options: .atomic)
            let activityVC = UIActivityViewController(activityItems: [tmp], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                var presenter = rootVC
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                activityVC.popoverPresentationController?.sourceView = presenter.view
                presenter.present(activityVC, animated: true)
            }
        } catch {
            viewModel.attachmentError = "Couldn't download the file. Please try again."
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.vSurface).frame(width: 64, height: 64)
                LucideIcon(.messageCircle, .xl).foregroundStyle(Color.vText2)
            }
            Text("No messages yet").font(.appCalloutSemibold).foregroundStyle(.white)
            Text("Say hello 👋").font(.appFootnote).foregroundStyle(Color.vText3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Non-lazy: the thread is capped at 50 messages, and a LazyVStack
                // doesn't render the bottom rows until scrolled — which makes the
                // initial scroll-to-bottom silently no-op (opening blank).
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, msg in
                        let divider = shouldShowDivider(at: index)
                        if divider { timeDivider(msg.createdAt) }
                        bubble(msg, tail: endsGroup(at: index))
                            .padding(.top, divider ? 2 : (startsGroup(at: index) ? 9 : 2))
                            .id(msg.id)
                        // The request's lifecycle as its own system-style message
                        // right under the request bubble (replaces the old pill).
                        if msg.isCollabRequest {
                            collabStatusMessage(msg)
                        }
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.vertical, 10)
            }
            // Opens already pinned to the latest message — no load-then-jump.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in scrollToBottom(proxy, animated: true) }
            // `defaultScrollAnchor` alone can land at the top when messages arrive
            // after first layout — force the bottom once the list is on screen.
            .onAppear { DispatchQueue.main.async { scrollToBottom(proxy, animated: false) } }
            // The tab root sets `.ignoresSafeArea(.keyboard)`, so the keyboard's
            // layout shift here isn't reflected in the scroll until nudged — re-pin
            // to the bottom when the keyboard opens (deferred so the bottom inset
            // has settled first). `willShow` (not `willChangeFrame`) so it doesn't
            // fight the interactive drag-to-dismiss.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
                }
            }
        }
    }

    private func timeDivider(_ date: Date) -> some View {
        Text(MessageTime.divider(date))
            .font(.appCaption2Medium)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
        } else {
            proxy.scrollTo(bottomAnchor, anchor: .bottom)
        }
    }

    // MARK: Grouping

    /// New visual group: first message, sender flips, a system message, or a >15-min
    /// gap (which also draws a divider).
    private func startsGroup(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = viewModel.messages[index - 1]
        let cur = viewModel.messages[index]
        if prev.isSystem || cur.isSystem { return true }
        if prev.isFromMe != cur.isFromMe { return true }
        return cur.createdAt.timeIntervalSince(prev.createdAt) > 15 * 60
    }

    /// Last message of a group → gets the bubble tail.
    private func endsGroup(at index: Int) -> Bool {
        let messages = viewModel.messages
        guard index < messages.count - 1 else { return true }
        let next = messages[index + 1]
        let cur = messages[index]
        if next.isSystem || cur.isSystem { return true }
        if next.isFromMe != cur.isFromMe { return true }
        return next.createdAt.timeIntervalSince(cur.createdAt) > 15 * 60
    }

    private func shouldShowDivider(at index: Int) -> Bool {
        guard index > 0 else { return true }
        let prev = viewModel.messages[index - 1].createdAt
        let cur = viewModel.messages[index].createdAt
        return cur.timeIntervalSince(prev) > 15 * 60
    }

    // MARK: Bubbles

    @ViewBuilder
    private func bubble(_ msg: ChatMessage, tail: Bool) -> some View {
        if msg.isSystem {
            Text(msg.text)
                .font(.appCaption)
                .foregroundStyle(Color.vText2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.vSurface, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else {
            HStack(spacing: 0) {
                if msg.isFromMe { Spacer(minLength: 56) }
                VStack(alignment: msg.isFromMe ? .trailing : .leading, spacing: 4) {
                    if msg.isAttachment { attachmentView(msg) }
                    if !msg.text.isEmpty { messageContent(msg, tail: tail) }
                }
                .opacity(msg.pending ? 0.5 : 1)
                if !msg.isFromMe { Spacer(minLength: 56) }
            }
        }
    }

    /// Renders the message body — plain text, or (for collab requests) a caption,
    /// a rich card per shared track, and the Accept/Decline (or status) footer.
    @ViewBuilder
    private func messageContent(_ msg: ChatMessage, tail: Bool) -> some View {
        if msg.sharedTracks.isEmpty && !msg.isCollabRequest {
            textBubble(msg.text, isFromMe: msg.isFromMe, tail: tail)
        } else {
            let caption = CollabMessage.strippedCaption(msg.text)
            if !caption.isEmpty {
                textBubble(caption, isFromMe: msg.isFromMe, tail: false)
            }
            ForEach(msg.sharedTracks) { track in
                trackShareCard(track, isFromMe: msg.isFromMe)
            }
        }
    }

    /// The request's lifecycle rendered as a centered system-style message —
    /// direction-aware wording for pending / accepted / declined (the actions
    /// themselves live in the conversation header).
    private func collabStatusMessage(_ msg: ChatMessage) -> some View {
        let (icon, text, tint): (LucideIcon.Name, String, Color) = switch msg.requestStatus ?? "pending" {
        case "accepted":
            (.circleCheck,
             msg.isFromMe
                 ? "@\(otherUsername) accepted your collab request — you can now message each other."
                 : "You accepted the collab request — you can now message each other.",
             .green)
        case "rejected":
            (.circleX,
             msg.isFromMe
                 ? "@\(otherUsername) declined your collab request."
                 : "You declined the collab request.",
             Color.vText3)
        default:
            (.clock,
             msg.isFromMe
                 ? "Waiting for @\(otherUsername) to respond — messaging unlocks once they accept."
                 : "@\(otherUsername) wants to collaborate — accept to start messaging.",
             Color.vText3)
        }
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            LucideIcon(icon, .xs)
            Text(text)
        }
        .font(.appCaption2Medium)
        .foregroundStyle(tint)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func textBubble(_ text: String, isFromMe: Bool, tail: Bool) -> some View {
        let shape = bubbleShape(isFromMe: isFromMe, tail: tail)
        return Text(text)
            .font(.appCalloutRegular)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if isFromMe {
                    shape.fill(accentGradient)
                        .shadow(color: Color.brand.opacity(0.28), radius: 7, y: 3)
                } else {
                    shape.fill(Color.vSurface)
                }
            }
    }

    /// A rich, playable card for a track shared in a collab request — real cover,
    /// title and artist, resolved from the message's structured metadata.
    private func trackShareCard(_ track: SharedTrack, isFromMe: Bool) -> some View {
        Button {
            playSharedTrack(track)
        } label: {
            HStack(spacing: 11) {
                ArtworkView(track.coverURL.map { .webImage($0) } ?? .placeholder(name: track.title), cornerRadius: 10)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.appSubheadlineSemibold).foregroundStyle(.white)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text("@\(artist)")
                            .font(.appCaption2).foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle().fill(.white.opacity(0.92)).frame(width: 30, height: 30)
                    Image(systemName: "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                }
            }
            .padding(9)
            .frame(width: 252)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFromMe ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.vSurface))
            }
        }
        .buttonStyle(.plain)
    }

    /// Opens the artist's profile and starts playing the track — same as tapping it
    /// on the profile.
    private func playSharedTrack(_ track: SharedTrack) {
        if let artistId = track.artistUserId {
            router.navigateToProfile(userId: artistId)
        }
        let media = Media(
            id: MediaID(track.id),
            meta: MediaMeta(
                artwork: track.coverURL,
                title: track.title,
                artist: track.artist,
                audioURL: track.audioURL
            )
        )
        playerController.playSingle(media)
    }

    /// Rounded bubble with a single sharp corner (the tail) on the sender's side,
    /// only on the last message of a group.
    private func bubbleShape(isFromMe: Bool, tail: Bool) -> UnevenRoundedRectangle {
        let r: CGFloat = 19
        return UnevenRoundedRectangle(
            topLeadingRadius: r,
            bottomLeadingRadius: (!isFromMe && tail) ? 5 : r,
            bottomTrailingRadius: (isFromMe && tail) ? 5 : r,
            topTrailingRadius: r,
            style: .continuous
        )
    }

    // MARK: Attachments

    @ViewBuilder
    private func attachmentView(_ msg: ChatMessage) -> some View {
        if msg.isImageAttachment {
            if let url = msg.attachmentURL {
                KFImage.url(url, cacheKey: attachmentCacheKey(url))
                    .downsampled(to: 220)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 210, height: 210)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .contentShape(.rect)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { imageFrames[msg.id] = $0 }
                    .onTapGesture {
                        avatarPreview.present(url: url, sourceFrame: imageFrames[msg.id] ?? .zero, circular: false)
                    }
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 210, height: 210)
                    .shimmering()
            }
        } else if msg.isAudioAttachment, let url = msg.attachmentURL {
            AudioAttachmentPlayer(url: url, name: msg.attachmentName, onStartPlaying: {
                // Don't play over the app's music — pause it when a voice note starts.
                if playerController.state.isPlaying { playerController.onPlayPause() }
            }, onLongPress: {
                // Hold the bubble for the options sheet (Add to Workspace / Share).
                Haptics.impact(.medium)
                optionsTarget = WorkspaceAttachmentTarget(url: url, name: msg.attachmentName, type: msg.attachmentType)
            })
        } else {
            fileChip(msg)
        }
    }

    private func fileChip(_ msg: ChatMessage) -> some View {
        let ext = (msg.attachmentName as NSString?)?.pathExtension ?? ""
        let chip = HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
                LucideIcon(.file, .lg).foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg.attachmentName ?? "Attachment")
                    .font(.appSubheadlineMedium).foregroundStyle(.white).lineLimit(1)
                Text(msg.attachmentURL == nil ? "Uploading…" : (ext.isEmpty ? "File" : ext.uppercased()))
                    .font(.appCaption2).foregroundStyle(Color.vText3).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: 250, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        return Group {
            if let url = msg.attachmentURL {
                Button { openURL(url) } label: { chip }.buttonStyle(.plain)
            } else {
                chip
            }
        }
    }

    // MARK: Input

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let att = pendingAttachment {
                attachmentPreview(att)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { showAttachMenu.toggle() }
                } label: {
                    LucideIcon(.plus, .lg)
                        .foregroundStyle(Color.vText2)
                        .rotationEffect(.degrees(showAttachMenu ? 45 : 0))
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.07), in: Circle())
                        // Center the circle against the single-line pill (44pt) instead
                        // of bottom-aligning the shorter 38pt button — while still
                        // sinking to the bottom-left once the field grows multi-line.
                        .frame(height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("", text: $viewModel.draft, prompt: Text(pendingAttachment != nil ? "Add a caption…" : "Message…").foregroundStyle(Color.vText3), axis: .vertical)
                        .font(.appCalloutRegular)
                        .foregroundStyle(.white)
                        .tint(Color.brand)
                        .focused($inputFocused)
                        .lineLimit(1 ... 5)
                        .padding(.leading, 16)
                        .padding(.trailing, canSend ? 6 : 16)
                        .padding(.vertical, 9)

                    if canSend {
                        Button {
                            sendCurrent()
                        } label: {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(accentGradient, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(minHeight: 44)
                .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.vBorder))
                .animation(.spring(response: 0.32, dampingFraction: 0.72), value: canSend)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            // The chat is full-screen (tab bar + mini-player hide while it's open),
            // so the bar simply pins to the bottom: above the keyboard when typing,
            // above the home indicator otherwise. The fill bleeds into the inset.
            Color.vBase
                .overlay(alignment: .top) { Rectangle().fill(Color.vBorder).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: Attachment menu (custom popup)

    private var attachMenuPopup: some View {
        VStack(spacing: 0) {
            attachRow(icon: .image, title: "Photo") {
                closeAttachMenu()
                showPhotoPicker = true
            }
            Divider().overlay(Color.white.opacity(0.08))
            attachRow(icon: .file, title: "File") {
                closeAttachMenu()
                showFileImporter = true
            }
        }
        .frame(width: 184)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }

    private func attachRow(icon: LucideIcon.Name, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                LucideIcon(icon, .md).foregroundStyle(.white)
                Text(title).font(.appCallout).foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func closeAttachMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { showAttachMenu = false }
    }

    /// Preview of the staged attachment sitting above the input row, with a remove
    /// (×) control. Sends only when the send button is tapped.
    private func attachmentPreview(_ att: PendingAttachment) -> some View {
        HStack(spacing: 10) {
            Group {
                if let img = att.previewImage {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Color.white.opacity(0.08)
                        LucideIcon(.file, .md).foregroundStyle(Color.vText2)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                // Photos use an auto-generated filename — show a clean label instead.
                Text(att.fileType.hasPrefix("image") ? "Photo" : att.fileName)
                    .font(.appFootnoteMedium).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.middle)
                Text("Ready to send").font(.appCaption).foregroundStyle(Color.vText3)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { pendingAttachment = nil }
            } label: {
                LucideIcon(.x, .sm)
                    .foregroundStyle(Color.vText2)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.vBorder))
    }

    /// Sends the staged attachment (with the draft as caption) if present, else a
    /// plain text message.
    private func sendCurrent() {
        if let att = pendingAttachment {
            let caption = viewModel.draft
            withAnimation(.easeOut(duration: 0.2)) { pendingAttachment = nil }
            viewModel.draft = ""
            Task {
                await viewModel.sendAttachment(
                    data: att.data, fileName: att.fileName, fileType: att.fileType, caption: caption
                )
            }
        } else {
            Task { await viewModel.send() }
        }
    }

    // MARK: Attachment pickers

    /// Stages the picked photo in the input bar (does not send).
    private func handlePhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let utype = item.supportedContentTypes.first
                let mime = utype?.preferredMIMEType ?? "image/jpeg"
                let ext = utype?.preferredFilenameExtension ?? "jpg"
                let name = "photo-\(Int(Date().timeIntervalSince1970)).\(ext)"
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    pendingAttachment = PendingAttachment(
                        data: data, fileName: name, fileType: mime, previewImage: UIImage(data: data)
                    )
                }
            }
            photoItem = nil
        }
    }

    /// Stages the picked file in the input bar (does not send).
    private func handleFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let preview = mime.hasPrefix("image") ? UIImage(data: data) : nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            pendingAttachment = PendingAttachment(
                data: data, fileName: url.lastPathComponent, fileType: mime, previewImage: preview
            )
        }
    }
}

// MARK: - Loading skeleton (alternating bubble bones, soft pulse)

private struct ThreadSkeleton: View {
    private let bone = Color.white.opacity(0.07)

    /// (fromMe, width) — a plausible-looking back-and-forth.
    private let rows: [(Bool, CGFloat)] = [
        (false, 180), (false, 120), (true, 200), (true, 90),
        (false, 220), (true, 150), (false, 110), (true, 230),
    ]

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    if row.0 { Spacer(minLength: 56) }
                    UnevenRoundedRectangle(
                        topLeadingRadius: 19,
                        bottomLeadingRadius: row.0 ? 19 : 5,
                        bottomTrailingRadius: row.0 ? 5 : 19,
                        topTrailingRadius: 19,
                        style: .continuous
                    )
                    .fill(bone)
                    .frame(width: row.1, height: 40)
                    if !row.0 { Spacer(minLength: 56) }
                }
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shimmering()
    }
}

// MARK: - Audio attachment player

/// Inline audio player (play/pause + scrubber + time), mirroring the web's
/// AudioPreview. Streams the signed URL with its own AVPlayer.
/// Coordinates inline audio attachments so only one plays at a time — starting one
/// pauses whichever was already playing (each has its own AVPlayer and would
/// otherwise overlap).
@MainActor
private final class AudioAttachmentCoordinator {
    static let shared = AudioAttachmentCoordinator()
    private var activeToken: UUID?
    private var pauseActive: (() -> Void)?

    func play(token: UUID, pauseSelf: @escaping () -> Void) {
        if activeToken != token { pauseActive?() }
        activeToken = token
        pauseActive = pauseSelf
    }

    func stop(token: UUID) {
        if activeToken == token { activeToken = nil; pauseActive = nil }
    }
}

private struct AudioAttachmentPlayer: View {
    let url: URL
    let name: String?
    /// Fired when this attachment starts playing (used to pause the app's music).
    var onStartPlaying: () -> Void = {}
    /// Fired on a long press (opens the attachment options sheet). While the
    /// press is held, the bubble darkens and sinks slightly as feedback.
    var onLongPress: (() -> Void)? = nil

    /// Long-press feedback state — drives the darken + sink.
    @State private var pressed = false

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var endObserver: (any NSObjectProtocol)?
    @State private var playToken = UUID()

    var body: some View {
        VStack(spacing: 11) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.08))
                    LucideIcon(.music, .md).foregroundStyle(.white)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "Audio").font(.appSubheadlineMedium).foregroundStyle(.white).lineLimit(1)
                    Text(metaText).font(.appCaption2).foregroundStyle(Color.vText3)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 11) {
                Button { toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        // Swap the glyph instantly (like the expanded player) — no fade.
                        .contentTransition(.identity)
                        .animation(nil, value: isPlaying)
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(get: { current }, set: { current = $0 }),
                    in: 0 ... max(duration, 0.1),
                    onEditingChanged: { editing in
                        if editing {
                            isSeeking = true
                        } else {
                            // Leave `isSeeking` true until the seek lands (see `seek`).
                            seek(to: current)
                        }
                    }
                )
                .tint(.white)

                Text("\(fmt(current)) / \(fmt(duration))")
                    .font(.appCaption2)
                    .foregroundStyle(Color.vText3)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .frame(width: 264)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Press feedback for the long-press options: darken + sink while held.
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(pressed ? 0.22 : 0))
                .allowsHitTesting(false)
        )
        .scaleEffect(pressed ? 0.97 : 1)
        .onLongPressGesture(minimumDuration: 0.4) {
            onLongPress?()
        } onPressingChanged: { pressing in
            guard onLongPress != nil else { return }
            // Ease in with a slight delay so quick taps (play, scrub) don't
            // flash the dim; release restores immediately.
            withAnimation(pressing ? .easeInOut(duration: 0.22).delay(0.08) : .easeOut(duration: 0.18)) {
                pressed = pressing
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: teardown)
    }

    private var metaText: String {
        let ext = (name as NSString?)?.pathExtension.uppercased() ?? ""
        if duration > 0 {
            return ext.isEmpty ? fmt(duration) : "\(ext) · \(fmt(duration))"
        }
        return ext.isEmpty ? "Audio" : ext
    }

    private func setup() {
        let p = AVPlayer(url: url)
        player = p
        // Both callbacks are delivered on the main queue (`queue: .main`), so
        // hopping onto the main actor is assumption, not a thread switch.
        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main
        ) { time in
            MainActor.assumeIsolated {
                if !isSeeking { current = time.seconds }
            }
        }
        Task {
            guard let item = p.currentItem else { return }
            if let d = try? await item.asset.load(.duration), d.seconds.isFinite {
                duration = d.seconds
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: p.currentItem, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isPlaying = false
                current = 0
                p.seek(to: .zero)
                AudioAttachmentCoordinator.shared.stop(token: playToken)
            }
        }
    }

    private func teardown() {
        AudioAttachmentCoordinator.shared.stop(token: playToken)
        player?.pause()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        player = nil
    }

    private func toggle() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            AudioAttachmentCoordinator.shared.stop(token: playToken)
        } else {
            if duration > 0, current >= duration - 0.1 { player.seek(to: .zero); current = 0 }
            // Pause the app's music and any other playing attachment first.
            onStartPlaying()
            AudioAttachmentCoordinator.shared.play(token: playToken) {
                player.pause()
                isPlaying = false
            }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        guard let player else { isSeeking = false; return }
        // Precise seek, and keep swallowing periodic-observer ticks until it lands.
        // Otherwise the observer fires once with the pre-seek time and the thumb
        // rubber-bands back to the old position before the player catches up.
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { _ in
            Task { @MainActor in isSeeking = false }
        }
    }

    private func fmt(_ s: Double) -> String {
        guard s.isFinite, s >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    ConversationScreen(conversation: ActiveConversation(
        convoId: "preview", otherUserId: nil, username: "DJ Shadow", avatarURL: nil
    ))
    .withRouter()
    .environment(dependencies)
    .environment(playerController)
    .environment(ConversationState())
    .environment(AvatarPreviewState())
}
