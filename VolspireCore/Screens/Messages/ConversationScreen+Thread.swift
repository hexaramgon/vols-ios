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

/// An audio attachment staged for "Add to Workspace" (sheet item).
private struct WorkspaceAttachmentTarget: Identifiable {
    let id = UUID()
    let url: URL
    let name: String?
    let type: String?
    /// The message this attachment belongs to — powers "Report" in the options sheet.
    var senderMessage: ChatMessage? = nil
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
    /// Long-press options for a text message (Copy / Report). Report is staged
    /// then presented once the options sheet dismisses.
    @State private var optionsMessage: ChatMessage?
    @State private var pendingReportMessage: ChatMessage?
    @State private var reportingMessage: ChatMessage?

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
                artwork: .placeholder(name: target.name),
                title: target.name ?? "Audio",
                meta: (target.name as NSString?)?.pathExtension.uppercased(),
                actions: attachmentActions(target)
            )
            // Detents come from TrackOptionsSheet itself (sized to its rows).
            .sheetBackground()
        }
    }

    /// Options for a held attachment — Add to Workspace / Share, plus Report on
    /// the other person's messages (reports the message the attachment belongs to).
    private func attachmentActions(_ target: WorkspaceAttachmentTarget) -> [TrackOptionsSheet.Action] {
        var actions: [TrackOptionsSheet.Action] = [
            .init(icon: .folderPlus, title: "Add to Workspace", subtitle: "Copy this file into a folder") {
                workspaceTarget = target
            },
            .init(icon: .share2, title: "Share", subtitle: "Save to Files or send it on", dismissesSheet: false) {
                await shareAttachment(target)
            },
        ]
        if let msg = target.senderMessage, !msg.isFromMe {
            actions.append(.init(icon: .flag, title: "Report", subtitle: "Flag this message for review") {
                // TrackOptionsSheet runs perform ~0.3s after dismissing, so setting
                // this now presents the report sheet once the options sheet is gone.
                reportingMessage = msg
            })
        }
        return actions
    }

    /// Downloads the attachment to a temp file and presents the share sheet
    /// (over the options sheet, which stays up — same pattern as track share).
    private func shareAttachment(_ target: WorkspaceAttachmentTarget) async {
        do {
            let (data, _) = try await URLSession.shared.data(from: target.url)
            // The attachment name is sender-controlled; `lastPathComponent` strips any
            // directory / `..` segments so it can't escape the temp dir, and a UUID
            // prefix avoids collisions between concurrent shares.
            let safeName = ((target.name ?? "audio") as NSString).lastPathComponent
            let fileName = safeName.isEmpty ? "attachment" : safeName
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(fileName)")
            try data.write(to: tmp, options: .atomic)
            UIApplication.presentActivitySheet([tmp])
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
            // Tap on inert space drops the keyboard (bubbles' own taps/long-
            // presses still win) — the app-wide behaviour.
            .tapToDismissKeyboard()
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
                    if !msg.text.isEmpty {
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
                ArtworkView(.placeholder(track.coverURL, name: track.title), cornerRadius: 10)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.appFont.trackTitle).foregroundStyle(.white)
                        .lineLimit(1)
                    if let artist = track.artist {
                        Text("@\(artist)")
                            .font(.appFont.trackSubtitle).foregroundStyle(Color.vText3)
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
                    // Same shimmer bone as the no-URL state — the bubble never
                    // renders as empty space while the image downloads.
                    .placeholder {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 210, height: 210)
                            .shimmering()
                    }
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
                    .onLongPressGesture(minimumDuration: 0.35) {
                        // Nothing to show on your own caption-less image.
                        guard !msg.isFromMe || !msg.text.isEmpty else { return }
                        Haptics.impact(.medium)
                        optionsMessage = msg
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
                // Hold the bubble for options (Add to Workspace / Share / Report).
                Haptics.impact(.medium)
                optionsTarget = WorkspaceAttachmentTarget(
                    url: url, name: msg.attachmentName, type: msg.attachmentType, senderMessage: msg
                )
            })
        } else {
            fileChip(msg)
                .onLongPressGesture(minimumDuration: 0.35) {
                    guard !msg.isFromMe || !msg.text.isEmpty else { return }
                    Haptics.impact(.medium)
                    optionsMessage = msg
                }
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
        // Shared scoped-access dance; denied access or a failed read = silent skip.
        guard let data = (try? SecurityScopedFile.read(url)) ?? nil else { return }
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

