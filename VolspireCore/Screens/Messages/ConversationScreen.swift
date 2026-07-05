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

/// Accent fill for the current user's bubbles + send button — a brand-led blue
/// gradient that keeps white text/icons legible (brand alone is too light).
private let accentGradient = LinearGradient(
    colors: [Color.brand, Color(red: 0.16, green: 0.40, blue: 0.86)],
    startPoint: .topLeading, endPoint: .bottomTrailing
)

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
                ChatThread(viewModel: viewModel)
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
            await vm.load()
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
            Button { if let onBack { onBack() } else { dismiss() } } label: {
                LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
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
                        if conversation.otherUserId != nil {
                            Text("View profile")
                                .font(.appCaption)
                                .foregroundStyle(Color.vText3)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(conversation.otherUserId == nil)

            Spacer(minLength: 0)
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

private struct ChatThread: View {
    @Bindable var viewModel: ConversationViewModel
    @Environment(\.openURL) private var openURL
    @Environment(AvatarPreviewState.self) private var avatarPreview

    @FocusState private var inputFocused: Bool
    @State private var photoItem: PhotosPickerItem?
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    /// On-screen frame of each image bubble, so tapping one zooms it from its spot.
    @State private var imageFrames: [String: CGRect] = [:]

    private let bottomAnchor = "thread-bottom"

    private var canSend: Bool {
        !viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isSending
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
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, msg in
                        let divider = shouldShowDivider(at: index)
                        if divider { timeDivider(msg.createdAt) }
                        bubble(msg, tail: endsGroup(at: index))
                            .padding(.top, divider ? 2 : (startsGroup(at: index) ? 9 : 2))
                            .id(msg.id)
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
            .onChange(of: inputFocused) { _, focused in if focused { scrollToBottom(proxy, animated: true) } }
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
                    if !msg.text.isEmpty { textBubble(msg, tail: tail) }
                }
                .opacity(msg.pending ? 0.5 : 1)
                if !msg.isFromMe { Spacer(minLength: 56) }
            }
        }
    }

    private func textBubble(_ msg: ChatMessage, tail: Bool) -> some View {
        let shape = bubbleShape(isFromMe: msg.isFromMe, tail: tail)
        return Text(msg.text)
            .font(.appCalloutRegular)
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if msg.isFromMe {
                    shape.fill(accentGradient)
                        .shadow(color: Color.brand.opacity(0.28), radius: 7, y: 3)
                } else {
                    shape.fill(Color.vSurface)
                }
            }
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
            AudioAttachmentPlayer(url: url, name: msg.attachmentName)
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
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button { showPhotoPicker = true } label: { Label("Photo", systemImage: "photo") }
                Button { showFileImporter = true } label: { Label("File", systemImage: "doc") }
            } label: {
                LucideIcon(.plus, .lg)
                    .foregroundStyle(Color.vText2)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.07), in: Circle())
                    .contentShape(.rect)
            }
            .disabled(viewModel.isSending)

            HStack(alignment: .bottom, spacing: 6) {
                TextField("", text: $viewModel.draft, prompt: Text("Message…").foregroundStyle(Color.vText3), axis: .vertical)
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
                        Task { await viewModel.send() }
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

    // MARK: Attachment pickers

    private func handlePhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        let caption = viewModel.draft
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let utype = item.supportedContentTypes.first
                let mime = utype?.preferredMIMEType ?? "image/jpeg"
                let ext = utype?.preferredFilenameExtension ?? "jpg"
                let name = "photo-\(Int(Date().timeIntervalSince1970)).\(ext)"
                await viewModel.sendAttachment(data: data, fileName: name, fileType: mime, caption: caption)
                if viewModel.attachmentError == nil { viewModel.draft = "" }
            }
            photoItem = nil
        }
    }

    private func handleFile(_ result: Result<[URL], Error>) {
        guard case let .success(urls) = result, let url = urls.first else { return }
        let caption = viewModel.draft
        Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            await viewModel.sendAttachment(data: data, fileName: url.lastPathComponent, fileType: mime, caption: caption)
            if viewModel.attachmentError == nil { viewModel.draft = "" }
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
private struct AudioAttachmentPlayer: View {
    let url: URL
    let name: String?

    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var isSeeking = false
    @State private var timeObserver: Any?
    @State private var endObserver: (any NSObjectProtocol)?

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
                        .frame(width: 34, height: 34)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(get: { current }, set: { current = $0 }),
                    in: 0 ... max(duration, 0.1),
                    onEditingChanged: { editing in
                        isSeeking = editing
                        if !editing { seek(to: current) }
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
            forInterval: CMTime(seconds: 0.3, preferredTimescale: 600), queue: .main
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
            }
        }
    }

    private func teardown() {
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
        } else {
            if duration > 0, current >= duration - 0.1 { player.seek(to: .zero); current = 0 }
            player.play()
            isPlaying = true
        }
    }

    private func seek(to seconds: Double) {
        player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
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
