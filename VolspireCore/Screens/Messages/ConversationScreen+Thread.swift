//
//  ConversationScreen+Thread.swift
//  Volspire
//
//  The message thread: bubble list, grouping/dividers, composer, and attachment sending.
//

import AVFoundation
import DesignSystem
import Kingfisher
import MediaLibrary
import PhotosUI
import Services
import SharedUtilities
import SwiftUI
import UniformTypeIdentifiers

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

/// A held attachment (photo / audio / file) — drives its options sheet and
/// "Add to Workspace".
private struct WorkspaceAttachmentTarget: Identifiable {
    let id = UUID()
    let url: URL
    let name: String?
    let type: String?
    /// The message this attachment belongs to — powers "Report" in the options sheet.
    var senderMessage: ChatMessage? = nil

    var isImage: Bool { type?.hasPrefix("image") ?? false }
    var isAudio: Bool { type?.hasPrefix("audio") ?? false }
}

struct ChatThread: View {
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
    /// The attach sheet (inline photo grid + Files).
    @State private var showAttachSheet = false
    /// Brief confirmation pill above the composer ("Saved to Photos").
    /// A picked photo/file staged in the input bar — sent only when send is tapped.
    @State private var pendingAttachment: PendingAttachment?
    /// Audio attachment staged for "Add to Workspace" (drives the folder picker).
    @State private var workspaceTarget: WorkspaceAttachmentTarget?
    /// Audio attachment whose long-press options sheet is open.
    @State private var optionsTarget: WorkspaceAttachmentTarget?
    /// Long-press options for a text message (Copy / Report). Report is staged
    /// then presented once the options sheet dismisses.
    @State private var optionsMessage: ChatMessage?
    @State private var pendingReportMessage: ChatMessage?
    @State private var reportingMessage: ChatMessage?
    /// The thread is scrolled within ~a screen of its top (drives auto-loading
    /// earlier pages).
    @State private var nearTop = false
    /// The user has scrolled at least once — the open-at-bottom settle can
    /// briefly read as "near top", which must not page in history by itself.
    @State private var userScrolled = false
    /// The thread's backing UIScrollView — keep-your-place on prepend sets its
    /// offset directly (SwiftUI's ScrollPosition is ignored mid-fling).
    @State private var threadScroll = EnclosingScrollView.Box()

    private let bottomAnchor = "thread-bottom"

    private var canSend: Bool {
        let hasText = !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || pendingAttachment != nil) && !viewModel.isSending
            && viewModel.composerReady && viewModel.collabRequestGate == nil
    }

    var body: some View {
        Group {
            if !viewModel.messages.isEmpty {
                messageList
            } else if viewModel.loadingState == .loaded {
                emptyState
            } else if case .error = viewModel.loadingState {
                LoadErrorView(icon: .messageCircle, title: "Couldn't load messages") {
                    Task { await viewModel.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ThreadSkeleton()
            }
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.messages.isEmpty)
        .animation(.easeOut(duration: 0.25), value: viewModel.loadingState)
        .sheet(isPresented: $showAttachSheet) {
            // Each tile closes the sheet, then opens its picker once it's gone.
            AttachSheet(
                onPhotos: {
                    showAttachSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showPhotoPicker = true }
                },
                onFiles: {
                    showAttachSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showFileImporter = true }
                }
            )
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in handlePhoto(item) }
        .safeAreaInset(edge: .bottom) {
            // Nothing until the thread is known (see `composerReady`) — then
            // a gated thread swaps the composer for the reason it's closed (a
            // disabled field with no explanation reads as a bug).
            Group {
                if !viewModel.composerReady {
                    Color.clear.frame(height: 0)
                } else if let gate = viewModel.collabRequestGate {
                    gatedNotice(gate).transition(.opacity)
                } else {
                    inputBar.transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: viewModel.composerReady)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf, .audio, .movie, .plainText, .data],
            allowsMultipleSelection: false
        ) { handleFile($0) }
        // Failures surface as the app's error toast, not a system alert.
        .onChange(of: viewModel.attachmentError) { _, error in
            guard let error else { return }
            ToastCenter.shared.show(error, style: .error)
            viewModel.attachmentError = nil
        }
        // "Add to Workspace" for an audio attachment — pick a folder to copy it into.
        .sheet(item: $workspaceTarget) { target in
            AttachmentFolderPicker(url: target.url, fileName: target.name, fileType: target.type)
        }
        // Long-press a text message → Copy / Report.
        .sheet(item: $optionsMessage, onDismiss: {
            if let msg = pendingReportMessage {
                pendingReportMessage = nil
                reportingMessage = msg
            }
        }) { msg in
            MessageOptionsSheet(message: msg, onReport: { pendingReportMessage = msg })
        }
        .sheet(item: $reportingMessage) { msg in
            ReportSheet(targetType: .message, targetId: msg.id, subject: "@\(otherUsername)")
        }
        // Long-press options for an audio attachment — same sheet style as the
        // track "…" menus everywhere else in the app.
        .sheet(item: $optionsTarget) { target in
            TrackOptionsSheet(
                artwork: target.isImage ? .webImage(target.url) : .placeholder(name: target.name),
                title: target.isImage ? "Photo" : (target.name ?? (target.isAudio ? "Audio" : "File")),
                meta: target.isImage ? nil : (target.name as NSString?)?.pathExtension.uppercased(),
                actions: attachmentActions(target)
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .sheetBackground()
        }
    }

    /// Options for a held attachment — Download (photos → Photos, everything
    /// else → Files), Add to Workspace (audio), plus Report on the other
    /// person's messages (reports the message the attachment belongs to).
    private func attachmentActions(_ target: WorkspaceAttachmentTarget) -> [TrackOptionsSheet.Action] {
        var actions: [TrackOptionsSheet.Action] = []
        if target.isImage {
            actions.append(.init(icon: .download, title: "Save to Photos", subtitle: "Download it to your library",
                                 awaitsCompletion: true) {
                if await AttachmentDownloads.saveToPhotos(from: target.url, name: target.name) {
                    Haptics.success()
                    ToastCenter.shared.show("Saved to Photos")
                } else {
                    viewModel.attachmentError = "Couldn't save the photo. Check Volspire's Photos access in Settings."
                }
            })
        } else {
            actions.append(.init(icon: .download, title: "Download", subtitle: "Save it to Files",
                                 dismissesSheet: false) {
                do {
                    let tmp = try await AttachmentDownloads.toTempFile(target.url, name: target.name)
                    UIApplication.presentSaveToFiles(tmp) { saved in
                        // Close the options sheet so the toast (root level) is visible.
                        optionsTarget = nil
                        if saved {
                            Haptics.success()
                            ToastCenter.shared.show("Saved to Files")
                        }
                    }
                } catch {
                    optionsTarget = nil
                    viewModel.attachmentError = "Couldn't download the file. Please try again."
                }
            })
        }
        if target.isAudio {
            actions.append(.init(icon: .folderPlus, title: "Add to Workspace", subtitle: "Copy this file into a folder") {
                workspaceTarget = target
            })
        }
        if let msg = target.senderMessage, !msg.isFromMe {
            actions.append(.init(icon: .flag, title: "Report", subtitle: "Flag this message for review") {
                // TrackOptionsSheet runs perform ~0.3s after dismissing, so setting
                // this now presents the report sheet once the options sheet is gone.
                reportingMessage = msg
            })
        }
        return actions
    }


    private var emptyState: some View {
        InboxEmptyState(
            title: "Start the conversation",
            message: "Say hi to @\(otherUsername).",
            compact: true
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Non-lazy: a page is 50 messages (more only as the user scrolls
                // back), and a LazyVStack doesn't render the bottom
                // rows until scrolled — which makes the initial scroll-to-bottom
                // silently no-op (opening blank).
                VStack(spacing: 0) {
                    if viewModel.hasOlder {
                        // Earlier pages load on their own as you scroll up —
                        // this is just the "more above" spinner. Fixed height
                        // in every state so it never shifts the thread.
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
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
                .background(EnclosingScrollView(box: threadScroll))
            }
            // Opens already pinned to the latest message — no load-then-jump.
            .defaultScrollAnchor(.bottom)
            // Keep your place when an earlier page is prepended: the first
            // message changed in the SAME layout pass as the height (an
            // onChange fires after layout — too late), so shift the offset by
            // exactly the added height. Set on the UIScrollView itself, which
            // also holds mid-fling (a fling carries on from the new spot).
            .onScrollGeometryChange(for: ThreadScrollMetrics.self) { geo in
                ThreadScrollMetrics(height: geo.contentSize.height, firstId: viewModel.messages.first?.id)
            } action: { old, new in
                guard old.firstId != nil, old.firstId != new.firstId,
                      let sv = threadScroll.scrollView else { return }
                let delta = new.height - old.height
                guard delta != 0 else { return }
                sv.contentOffset.y += delta
            }
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { userScrolled = true }
            }
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top < geo.containerSize.height
            } action: { _, isNear in
                nearTop = isNear
                loadOlderIfNeeded()
            }
            .scrollDismissesKeyboard(.interactively)
            // Tap on inert space drops the keyboard (bubbles' own taps/long-
            // presses still win) — the app-wide behaviour.
            .tapToDismissKeyboard()
            // Follow a NEW latest message only — prepending earlier pages must
            // not yank the thread to the bottom.
            .onChange(of: viewModel.messages.last?.id) { _, _ in scrollToBottom(proxy, animated: true) }
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

    struct ThreadScrollMetrics: Equatable {
        var height: CGFloat
        var firstId: String?
    }

    /// Pages in earlier messages while the reader is near the top — and keeps
    /// going if a short page still leaves them there. The prepend offset
    /// compensation (messageList) holds their place.
    private func loadOlderIfNeeded() {
        guard nearTop, userScrolled, viewModel.hasOlder, !viewModel.isLoadingOlder else { return }
        Task {
            let before = viewModel.messages.count
            await viewModel.loadOlder()
            // A failed/empty page stops here (no retry loop while offline) —
            // the next scroll toward the top tries again.
            guard viewModel.messages.count > before else { return }
            // Let the prepended rows lay out (updates nearTop) before re-checking.
            try? await Task.sleep(for: .milliseconds(100))
            loadOlderIfNeeded()
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
                if msg.isFromMe { Spacer(minLength: 40) }
                VStack(alignment: msg.isFromMe ? .trailing : .leading, spacing: 4) {
                    if msg.isAttachment { attachmentView(msg, tail: tail) }
                    // An image's caption lives inside the image bubble.
                    if !msg.text.isEmpty, !msg.isImageAttachment {
                        messageContent(msg, tail: tail)
                            // Hold a plain text bubble for Copy / Report (collab
                            // requests are handled from the header instead).
                            .onLongPressGesture(minimumDuration: 0.35) {
                                guard !msg.isCollabRequest, msg.sharedTracks.isEmpty else { return }
                                Haptics.impact(.medium)
                                optionsMessage = msg
                            }
                    }
                }
                .opacity(msg.pending ? 0.5 : 1)
                if !msg.isFromMe { Spacer(minLength: 40) }
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
    /// direction-aware wording for pending / accepted / declined / withdrawn (the actions
    /// themselves live in the conversation header).
    private func collabStatusMessage(_ msg: ChatMessage) -> some View {
        let status = msg.requestStatus ?? "pending"
        let text = switch status {
        case "accepted":
            msg.isFromMe
                ? "@\(otherUsername) accepted your collab request. You can now message each other."
                : "You accepted the collab request. You can now message each other."
        case "rejected":
            msg.isFromMe
                ? "@\(otherUsername) declined your collab request."
                : "You declined the collab request."
        case "withdrawn":
            msg.isFromMe
                ? "You withdrew your collab request."
                : "@\(otherUsername) withdrew their collab request."
        default:
            msg.isFromMe
                ? "Waiting for @\(otherUsername) to respond. Messaging unlocks once they accept."
                : "@\(otherUsername) wants to collaborate. Accept to start messaging."
        }
        // Same neutral surface as other system rows; the outcome rides on the
        // app's pop mark (green check / grey cross) rather than tinted text.
        // Static, not SuccessMark: it's a status line, so it mustn't re-pop
        // every time the thread opens.
        return HStack(spacing: 8) {
            switch status {
            case "accepted": PopMark(isOn: true, rest: .none, size: 18)
            case "rejected": PopMark(isOn: true, mark: .cross, rest: .none, tint: Color.vText3, size: 18)
            case "withdrawn": LucideIcon(.circleMinus, .xs).foregroundStyle(Color.vText3)
            default: LucideIcon(.clock, .xs).foregroundStyle(Color.vText3)
            }
            Text(text)
                .font(.appCaption)
                .foregroundStyle(Color.vText2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func textBubble(_ text: String, isFromMe: Bool, tail: Bool) -> some View {
        let shape = bubbleShape(isFromMe: isFromMe, tail: tail)
        return Text(text)
            .font(.appBody)
            // Yours: the brand accent with white type (iMessage-style), so your
            // side of the thread reads at a glance; theirs stays neutral.
            .foregroundStyle(isFromMe ? Color.vOnColor : Color.vText)
            .tint(isFromMe ? Color.vOnColor : Color.vAccent)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                shape.fill(isFromMe ? Color.vAccent : Color.vSurface)
            }
    }

    /// A rich, playable card for a track shared in a collab request — real cover,
    /// title and artist, resolved from the message's structured metadata.
    private func trackShareCard(_ track: SharedTrack, isFromMe: Bool) -> some View {
        Button {
            playSharedTrack(track)
        } label: {
            HStack(spacing: 11) {
                ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: 10)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.appFont.trackTitle).foregroundStyle(Color.vText)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text("@\(artist)")
                            .font(.appFont.trackSubtitle).foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle().fill(Color.vInverse).frame(width: 30, height: 30)
                    LucideIcon(.playFill, .xs).foregroundStyle(Color.vOnInverse)
                }
            }
            .padding(9)
            .frame(width: 252)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isFromMe ? Color.vSurface2 : Color.vSurface)
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
    private func attachmentView(_ msg: ChatMessage, tail: Bool) -> some View {
        if msg.isImageAttachment {
            ChatImageBubble(
                url: msg.attachmentURL,
                caption: msg.text,
                isFromMe: msg.isFromMe,
                shape: bubbleShape(isFromMe: msg.isFromMe, tail: tail),
                onTap: { url, frame in
                    avatarPreview.present(url: url, sourceFrame: frame, circular: false, name: msg.attachmentName)
                },
                onLongPress: {
                    // Hold a photo for Save to Photos / Report.
                    guard let url = msg.attachmentURL else { return }
                    Haptics.impact(.medium)
                    optionsTarget = WorkspaceAttachmentTarget(
                        url: url, name: msg.attachmentName, type: msg.attachmentType, senderMessage: msg
                    )
                }
            )
        } else if msg.isAudioAttachment, let url = msg.attachmentURL {
            AudioAttachmentPlayer(url: url, name: msg.attachmentName, onStartPlaying: {
                // Don't play over the app's music — pause it when a voice note starts.
                if playerController.state.isPlaying { playerController.onPlayPause() }
            }, onLongPress: {
                // Hold the bubble for options (Add to Workspace / Report).
                Haptics.impact(.medium)
                optionsTarget = WorkspaceAttachmentTarget(
                    url: url, name: msg.attachmentName, type: msg.attachmentType, senderMessage: msg
                )
            })
        } else {
            fileChip(msg)
                .onLongPressGesture(minimumDuration: 0.35) {
                    // Hold a file for Download / Report.
                    guard let url = msg.attachmentURL else { return }
                    Haptics.impact(.medium)
                    optionsTarget = WorkspaceAttachmentTarget(
                        url: url, name: msg.attachmentName, type: msg.attachmentType, senderMessage: msg
                    )
                }
        }
    }

    private func fileChip(_ msg: ChatMessage) -> some View {
        let ext = (msg.attachmentName as NSString?)?.pathExtension ?? ""
        let chip = HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).fill(Color.vControl)
                LucideIcon(.file, .lg).foregroundStyle(Color.vText)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(msg.attachmentName ?? "Attachment")
                    .font(.appSubheadlineMedium).foregroundStyle(Color.vText).lineLimit(1)
                Text(msg.attachmentURL == nil ? "Uploading…" : (ext.isEmpty ? "File" : ext.uppercased()))
                    .font(.appCaption2).foregroundStyle(Color.vText3).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: 250, alignment: .leading)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

        return Group {
            if let url = msg.attachmentURL {
                Button { openURL(downloadDispositionURL(url, name: msg.attachmentName)) } label: { chip }
                    .buttonStyle(.plain)
            } else {
                chip
            }
        }
    }

    /// Appends Supabase Storage's `download` query param so the signed URL is served
    /// with `Content-Disposition: attachment`. A hostile sender can set an attachment's
    /// stored Content-Type to `text/html`; without this, tapping the chip opens it
    /// inline in Safari on the storage origin — a phishing surface. Forcing a download
    /// makes the browser save/preview the file instead of rendering it as a web page.
    private func downloadDispositionURL(_ url: URL, name: String?) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let safe = ((name ?? "") as NSString).lastPathComponent
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "download", value: safe.isEmpty ? "attachment" : safe))
        comps.queryItems = items
        return comps.url ?? url
    }

    // MARK: Input

    /// Replaces the composer while a collab request (either side's) is
    /// unanswered or declined. Same chrome as `inputBar` (hairline + `vBase` bleeding into the
    /// safe area) so the bottom of the screen doesn't change shape.
    private func gatedNotice(_ gate: CollabRequestGate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(gate == .declined || gate == .youDeclined ? .circleX : .clock, .sm)
                .foregroundStyle(Color.vText3)
                .padding(.top, 1)
            Text(gate.message)
                .font(.appFootnote)
                .foregroundStyle(Color.vText2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 14)
        .background {
            Color.vBase
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var inputBar: some View {
        VStack(spacing: 8) {
            if let att = pendingAttachment {
                attachmentPreview(att)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                // Ghost paperclip — opens the attach sheet (photos + Files).
                Button {
                    inputFocused = false
                    showAttachSheet = true
                } label: {
                    LucideIcon(.paperclip, .xl)
                        .foregroundStyle(showAttachSheet ? Color.vText : Color.vText3)
                        .frame(width: 36, height: 40)
                        .minimumHitArea(for: 36)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSending)
                .accessibilityLabel("Attach")

                // One 40pt capsule with the send button inside — the Now
                // Playing comment composer's: an accent send button that pops in once
                // there's something to send.
                HStack(alignment: .bottom, spacing: 4) {
                    TextField("", text: Binding(
                        get: { viewModel.draft },
                        // The server's message cap (send_message*).
                        set: { viewModel.draft = String($0.prefix(2000)) }
                    ), prompt: Text(pendingAttachment != nil ? "Add a caption…" : "Message…").foregroundStyle(Color.vText3), axis: .vertical)
                        .font(.appBody)
                        .foregroundStyle(Color.vText)
                        .tint(Color.vText)
                        .focused($inputFocused)
                        .lineLimit(1 ... 5)
                        .padding(.leading, 16)
                        // Text keeps clear of the capsule's edge while the
                        // send button is hidden.
                        .padding(.trailing, canSend || viewModel.isSending ? 0 : 12)
                        .padding(.vertical, 10)

                    NearLimitCounter(count: viewModel.draft.count, limit: 2000)
                        .padding(.bottom, 12)
                    if canSend || viewModel.isSending {
                        SendButton(busy: viewModel.isSending) { sendCurrent() }
                            .padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(minHeight: 40)
                .background(Color.vField, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .animation(.easeOut(duration: 0.15), value: canSend)
                .animation(.easeOut(duration: 0.15), value: viewModel.isSending)
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
                .ignoresSafeArea(edges: .bottom)
        }
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
                        Color.vControl
                        LucideIcon(.file, .md).foregroundStyle(Color.vText2)
                    }
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                // Photos use an auto-generated filename — show a clean label instead.
                Text(att.fileType.hasPrefix("image") ? "Photo" : att.fileName)
                    .font(.appFootnoteMedium).foregroundStyle(Color.vText)
                    .lineLimit(1).truncationMode(.middle)
                Text("Ready to send").font(.appCaption).foregroundStyle(Color.vText3)
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeOut(duration: 0.2)) { pendingAttachment = nil }
            } label: {
                LucideIcon(.x, .md)
                    .foregroundStyle(Color.vText2)
                    .frame(width: 30, height: 30)
                    .background(Color.vControl, in: Circle())
                    .minimumHitArea(for: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
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
        // Shared scoped-access dance; denied access or a failed read = silent
        // skip, but an over-cap file says so (checked before it's read in).
        let data: Data
        do {
            guard let read = try SecurityScopedFile.read(url, maxBytes: StorageBucket.messageAttachments.maxUploadBytes) else { return }
            data = read
        } catch let error as FileTooLargeError {
            viewModel.attachmentError = error.localizedDescription
            return
        } catch {
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let preview = mime.hasPrefix("image") ? UIImage(data: data) : nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            pendingAttachment = PendingAttachment(
                data: data, fileName: url.lastPathComponent, fileType: mime, previewImage: preview
            )
        }
    }
}

// MARK: - Message options sheet

/// Long-press options for a text message: Copy + Report (report only on the
/// other person's messages). Mirrors the comment options sheet; sizes to content.
private struct MessageOptionsSheet: View {
    let message: ChatMessage
    let onReport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .messageCircle, title: "Message", subtitle: message.text) { dismiss() }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .copy, title: "Copy") {
                    UIPasteboard.general.string = message.text
                    dismiss()
                }
                if !message.isFromMe {
                    OptionSheetRow(icon: .flag, title: "Report") {
                        dismiss()
                        onReport()
                    }
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}

// MARK: - Image bubble

/// Remembered image aspect ratios (by cache key), persisted across launches,
/// so a photo seen once lays out at its real shape straight away — opening a
/// conversation never shows bubbles resizing from square.
@MainActor enum ChatImageAspects {
    private static let defaultsKey = "volspire:chat-image-aspects"
    private static var byKey: [String: Double] =
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double]) ?? [:]

    static func get(_ key: String) -> CGFloat? { byKey[key].map { CGFloat($0) } }

    static func set(_ key: String, _ aspect: CGFloat) {
        guard byKey[key] != Double(aspect) else { return }
        // Keep the table small — old entries just fall back to square once.
        if byKey.count > 600 { byKey.removeAll() }
        byKey[key] = Double(aspect)
        UserDefaults.standard.set(byKey, forKey: defaultsKey)
    }
}

/// A photo message, iMessage-style: the image at its own shape (portrait,
/// landscape or square, clamped to sensible bounds) inside the message
/// bubble shape — tail corner and all — with the caption, if any, in the same
/// bubble underneath. Hairline edge so light photos don't bleed into the
/// page. Shimmer bones while it downloads; an "Uploading…" spinner before the
/// upload lands. Tap zooms it from its spot; hold for options.
private struct ChatImageBubble: View {
    let url: URL?
    let caption: String
    let isFromMe: Bool
    let shape: UnevenRoundedRectangle
    let onTap: (URL, CGRect) -> Void
    let onLongPress: () -> Void

    @State private var aspect: CGFloat?
    @State private var frame: CGRect = .zero

    private static let maxWidth: CGFloat = 240
    private static let maxHeight: CGFloat = 300
    private static let minWidth: CGFloat = 150
    private static let minHeight: CGFloat = 120

    /// The image's on-screen size: full width, height from the aspect, then
    /// clamped (very tall images narrow down; very wide ones get a floor).
    private var imageSize: CGSize {
        guard let a = aspect ?? cachedAspect, a > 0 else { return CGSize(width: Self.maxWidth, height: Self.maxWidth) }
        var w = Self.maxWidth
        var h = w / a
        if h > Self.maxHeight { h = Self.maxHeight; w = max(Self.minWidth, h * a) }
        if h < Self.minHeight { h = Self.minHeight }
        return CGSize(width: w.rounded(), height: h.rounded())
    }

    private var cachedAspect: CGFloat? {
        url.flatMap { ChatImageAspects.get(attachmentCacheKey($0)) }
    }

    var body: some View {
        let size = imageSize
        let hasCaption = !caption.isEmpty
        VStack(alignment: .leading, spacing: 0) {
            image(size)
                // The photo's own spot (not the caption) — the viewer grows from it.
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            if hasCaption {
                Text(caption)
                    .font(.appCalloutRegular)
                    .foregroundStyle(isFromMe ? Color.vOnColor : Color.vText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(width: size.width, alignment: .leading)
            }
        }
        // A sent photo's caption sits on your accent, like your text bubbles.
        .background(isFromMe ? Color.vAccent : Color.vSurface)
        .clipShape(shape)
        .overlay { shape.strokeBorder(Color.ink(0.08), lineWidth: 0.5) }
        .contentShape(shape)
        .onTapGesture { if let url { onTap(url, frame) } }
        .onLongPressGesture(minimumDuration: 0.35, perform: onLongPress)
    }

    @ViewBuilder
    private func image(_ size: CGSize) -> some View {
        if let url {
            // Sized placeholder + overlay, so the fill image can't stretch the bubble.
            Color.vSkeleton
                .frame(width: size.width, height: size.height)
                .overlay {
                    KFImage.url(url, cacheKey: attachmentCacheKey(url))
                        .placeholder { Color.vSkeleton.shimmering() }
                        .onSuccess { result in
                            let s = result.image.size
                            guard s.height > 0 else { return }
                            let a = s.width / s.height
                            Task { @MainActor in
                                ChatImageAspects.set(attachmentCacheKey(url), a)
                                // Snap, never animate: a resize mid-open read
                                // as the thread jumping around.
                                guard aspect != a else { return }
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) { aspect = a }
                            }
                        }
                        .downsampled(to: 480)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
        } else {
            Color.vSkeleton
                .frame(width: size.width, height: size.height)
                .shimmering()
                .overlay {
                    VStack(spacing: 8) {
                        ProgressView().tint(Color.vText2)
                        Text("Uploading…").font(.appCaption).foregroundStyle(Color.vText2)
                    }
                }
        }
    }
}

// MARK: - Attach sheet

/// The paperclip's sheet: two big tiles — Photos (your library) and Files
/// (documents, audio, video). Each opens the system picker; whatever you
/// pick is staged above the composer for a caption before sending.
private struct AttachSheet: View {
    let onPhotos: () -> Void
    let onFiles: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .paperclip, title: "Attach", subtitle: "Add a photo or file to your message") { dismiss() }

            HStack(spacing: 12) {
                tile(icon: .image, title: "Photos", caption: "From your library",
                     fill: Color.vInverse, glyph: Color.vOnInverse, action: onPhotos)
                tile(icon: .file, title: "Files", caption: "Docs, audio, video",
                     fill: Color.vInverse, glyph: Color.vOnInverse, action: onFiles)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    private func tile(icon: LucideIcon.Name, title: String, caption: String,
                      fill: Color, glyph: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                LucideIcon(icon, .lg)
                    .foregroundStyle(glyph)
                    .frame(width: 44, height: 44)
                    .background(fill, in: Circle())
                Text(title)
                    .font(.appSubheadlineSemibold)
                    .foregroundStyle(Color.vText)
                    .padding(.top, 28)
                Text(caption)
                    .font(.appCaption)
                    .foregroundStyle(Color.vText3)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.vControl, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(CardPress())
        .accessibilityLabel("\(title), \(caption)")
    }
}

// MARK: - Backing scroll view

/// Finds the UIScrollView behind a SwiftUI ScrollView (place it in the
/// content's background) so its offset can be adjusted synchronously.
struct EnclosingScrollView: UIViewRepresentable {
    final class Box { weak var scrollView: UIScrollView? }
    let box: Box

    func makeUIView(context: Context) -> UIView {
        let view = FinderView()
        view.box = box
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    private final class FinderView: UIView {
        var box: Box?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            var v = superview
            while let current = v, !(current is UIScrollView) { v = current.superview }
            if let sv = v as? UIScrollView { box?.scrollView = sv }
        }
    }
}
