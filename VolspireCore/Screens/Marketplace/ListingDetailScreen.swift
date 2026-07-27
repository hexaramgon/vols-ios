//
//  ListingDetailScreen.swift
//  Volspire
//
//  Collab-board listing detail. Text-forward like the web `listing-detail`:
//  category + status, title, author + stats, Respond / Save actions, the
//  description, tags, playable audio clips, and comments.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI
import UIKit

struct ListingDetailScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(ConversationState.self) private var conversationState
    @Environment(PlayerController.self) private var playerController
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ListingDetailViewModel
    @State private var showRespond = false
    @State private var showDeleteConfirm = false
    @State private var showAdminOptions = false
    @State private var pendingAdminDelete = false
    @State private var pendingEdit = false
    @State private var showEdit = false
    /// The comment whose options sheet is open (matches the track comments UX).
    @State private var commentOptions: ApiListingComment?
    /// Staged report → presented after the options sheet dismisses.
    @State private var pendingReportComment: ApiListingComment?
    @State private var reportingComment: ApiListingComment?
    @FocusState private var commentFocused: Bool
    // Non-author viewer "…": report the listing / author, or block the author.
    @State private var showViewerOptions = false
    @State private var pendingViewer: ViewerAction?
    @State private var reportTarget: ReportTarget?
    @State private var showBlockAuthor = false
    /// Scroll-driven chrome state — read only by `CollapsedTitleBar`.
    @State private var barState = ScrollFadeState()
    /// Which discussion list the author is viewing (visitors only see comments).
    @State private var discussionTab: DiscussionTab = .comments
    /// Signed-in user's avatar for the composer pill (matches the player's).
    @State private var myAvatarUrl: String?
    @State private var myInitial: String = "?"

    enum DiscussionTab { case comments, responses }

    init(listing: ApiListing) {
        _viewModel = State(wrappedValue: ListingDetailViewModel(listing: listing))
    }

    private var listing: ApiListing { viewModel.listing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 26) {
                    // The pitch first — description, tags, reference clips —
                    // THEN the decision point (Respond/Save), then discussion.
                    if let desc = listing.description, !desc.isEmpty { bodyText(desc) }
                    if let tags = listing.tags, !tags.isEmpty { chipRow(tags.map { "#\($0)" }) }
                    if !listing.attachments.isEmpty { audioCard }
                    // Respond + Save are for visitors only — authors manage via the "…" menu.
                    if !viewModel.isAuthor { actionRow }
                    discussion
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        // Tapping anywhere on the content drops the keyboard (buttons still
        // win the tap — this only catches otherwise-inert space).
        .tapToDismissKeyboard()
        // Composer pinned at the screen bottom, like the expanded player's —
        // hidden while the author is browsing responses (it posts comments).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !(viewModel.isAuthor && discussionTab == .responses) {
                composerBar
                    // Slides down + fades when the author flips to Responses
                    // (the pill tap drives this inside withAnimation).
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Let the system inset the scroll for the keyboard (like the Messages
        // thread) so the bottom comments stay reachable while typing — the
        // composer's `safeAreaInset` rides up with it.
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            barState.update(offsetY: y)
        }
        .background(Color.vBase.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) { backButton }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isAuthor { adminButton } else { viewerButton }
            }
        }
        // Solid bar + centred title fade in once the hero scrolls away — its
        // own component observing `barState`, so per-frame scroll writes never
        // re-render this page (same isolation as the profile/Home headers).
        .overlay(alignment: .top) {
            CollapsedTitleBar(
                state: barState,
                title: "\(listing.categoryLabel) Listing",
                subtitle: "@\(listing.author.username)"
            )
        }
        .enableSwipeBack()
        // Reset the shared chrome flag on leave so the tab bar + mini player
        // return (it's toggled by the keyboard handlers on the composer).
        .onDisappear { conversationState.composerActive = false }
        .task { await viewModel.load() }
        // Own avatar for the composer pill — cached profile fetch, cheap.
        .task {
            guard let uid = dependencies.authManager.currentUserId,
                  let profile = try? await dependencies.supabaseService.getUserProfile(userId: uid)
            else { return }
            myAvatarUrl = profile.profileImageUrl
            myInitial = (profile.username?.first).map { String($0).uppercased() } ?? "?"
        }
        .sheet(isPresented: $showRespond) { respondSheet }
        .sheet(isPresented: $showAdminOptions, onDismiss: {
            if pendingAdminDelete { pendingAdminDelete = false; showDeleteConfirm = true }
            if pendingEdit { pendingEdit = false; showEdit = true }
        }) { adminOptionsSheet }
        .sheet(item: $commentOptions, onDismiss: {
            if let comment = pendingReportComment {
                pendingReportComment = nil
                reportingComment = comment
            }
        }) { comment in
            ListingCommentOptionsSheet(
                comment: comment,
                isOwn: viewModel.isOwnComment(comment),
                onReport: { pendingReportComment = comment },
                onDelete: { Task { await viewModel.deleteComment(comment) } }
            )
        }
        .sheet(item: $reportingComment) { comment in
            ReportSheet(
                targetType: .listingComment,
                targetId: comment.commentId,
                subject: "@\(comment.user.username)"
            )
        }
        .sheet(isPresented: $showViewerOptions, onDismiss: {
            switch pendingViewer {
            case .reportListing: reportTarget = .listing
            case .reportAuthor: reportTarget = .author
            case .block: showBlockAuthor = true
            case nil: break
            }
            pendingViewer = nil
        }) { viewerOptionsSheet }
        .sheet(item: $reportTarget) { target in
            switch target {
            case .listing:
                ReportSheet(targetType: .listing, targetId: listing.listingId, subject: listing.title)
            case .author:
                ReportSheet(targetType: .user, targetId: listing.author.userId, subject: "@\(listing.author.username)")
            }
        }
        .blockUserDialog(username: listing.author.username, isPresented: $showBlockAuthor) { blockAuthor() }
        .fullScreenCover(isPresented: $showEdit, onDismiss: { Task { await viewModel.load() } }) {
            CreateListingScreen(viewModel: CreateListingViewModel(
                editing: listing,
                supabaseService: dependencies.supabaseService,
                authManager: dependencies.authManager
            ))
        }
        .destructiveConfirm(
            "Delete this listing?",
            isPresented: $showDeleteConfirm,
            message: "This permanently removes the listing and its responses."
        ) {
            Task { if await viewModel.deleteListing() { dismiss() } }
        }
    }

    /// Author-only "…" — opens a slide-up sheet to open/close or delete.
    private var adminButton: some View {
        HeaderIconButton(icon: .ellipsis, shadow: true, size: ViewConst.heroOverlayIconSize) { showAdminOptions = true }
    }

    private enum ViewerAction { case reportListing, reportAuthor, block }
    private enum ReportTarget: Int, Identifiable { case listing, author; var id: Int { rawValue } }

    /// Non-author "…" — report the listing or its author, or block the author.
    private var viewerButton: some View {
        HeaderIconButton(icon: .ellipsis, shadow: true, size: ViewConst.heroOverlayIconSize) { showViewerOptions = true }
    }

    /// Viewer options as a slide-up sheet — mirrors `adminOptionsSheet`.
    private var viewerOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: listing.categoryIcon, title: listing.title, subtitle: "@\(listing.author.username)") {
                showViewerOptions = false
            }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .flag, title: "Report listing") {
                    pendingViewer = .reportListing
                    showViewerOptions = false
                }
                OptionSheetRow(icon: .flag, title: "Report @\(listing.author.username)") {
                    pendingViewer = .reportAuthor
                    showViewerOptions = false
                }
                OptionSheetRow(icon: .ban, title: "Block @\(listing.author.username)", tint: .vDestructive) {
                    pendingViewer = .block
                    showViewerOptions = false
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// Blocks the listing's author, then pops back off the detail screen.
    private func blockAuthor() {
        Task {
            try? await dependencies.supabaseService.blockUser(listing.author.userId)
            dismiss()
        }
    }

    /// Author options as a slide-up sheet — the shared `SheetHeader` + Lucide rows,
    /// matching the folder / playlist / track option sheets.
    private var adminOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: listing.categoryIcon, title: listing.title, subtitle: viewModel.isClosed ? "Closed" : "Open") {
                showAdminOptions = false
            }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .squarePen, title: "Edit listing") {
                    pendingEdit = true
                    showAdminOptions = false
                }
                OptionSheetRow(icon: viewModel.isClosed ? .circleCheck : .lock,
                               title: viewModel.isClosed ? "Reopen listing" : "Close listing") {
                    showAdminOptions = false
                    Task { await viewModel.toggleStatus() }
                }
                OptionSheetRow(icon: .trash2, title: "Delete listing",
                               tint: .vDestructive) {
                    pendingAdminDelete = true
                    showAdminOptions = false
                }
            }
            .padding(.top, 6)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}

// MARK: - Hero + actions

private extension ListingDetailScreen {
    /// Immersive header — the Playlists/Workspace brand-wash recipe behind the
    /// category chip, title, author and stats. Content-sized; the wash alone
    /// stretches on overscroll (backdrop-scoped, so nothing interactive sits
    /// under per-frame geometry).
    var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(listing.title)
                .font(.appTitle)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            // Author + date on the left, category (and Closed) on the right —
            // one compact identity row, no stats belt.
            HStack(spacing: 8) {
                authorRow
                if viewModel.isClosed { closedChip }
                categoryChip
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, ViewConst.safeAreaInsets.top + 56)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                let stretch = max(0, geo.frame(in: .scrollView).minY)
                heroWash
                    .frame(height: geo.size.height + stretch)
                    .offset(y: -stretch)
            }
        }
    }

    /// The app's hero wash: brand fading into the base + a corner glow + grain.
    var heroWash: some View {
        ZStack {
            Color.vBase
            LinearGradient(
                stops: [
                    .init(color: Color.brand.opacity(0.42), location: 0),
                    .init(color: Color.brand.opacity(0.12), location: 0.45),
                    .init(color: Color.brand.opacity(0), location: 0.95),
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.brand.opacity(0.18), Color.brand.opacity(0)],
                center: .topTrailing, startRadius: 0, endRadius: 220
            )
            GrainOverlay()
        }
    }

    /// Category on the brand accent — same chip family as the Collaborator
    /// badge and the "New" pills, sized down to sit in the author row.
    var categoryChip: some View {
        HStack(spacing: 5) {
            LucideIcon(listing.categoryIcon, .xs)
            Text(listing.categoryLabel).font(.appCaptionMedium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(LinearGradient.sendAccent, in: Capsule())
    }

    var closedChip: some View {
        Text("Closed")
            .font(.appCaptionMedium)
            .foregroundStyle(Color.vDestructive)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.vDestructive.opacity(0.16), in: Capsule())
    }

    var authorRow: some View {
        Button { router.navigateToProfile(userId: listing.author.userId) } label: {
            HStack(spacing: 9) {
                avatar(listing.author, size: 30)
                Text("@\(listing.author.username)")
                    .font(.appFootnoteMedium).foregroundStyle(.white)
                Text("·").foregroundStyle(Color.vText3)
                Text(MessageTime.agoLong(iso: listing.createdAt))
                    .font(.appFootnote).foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    var backButton: some View {
        BackButton()
    }

    /// Audio clips — each rendered with the same inline player as chat audio
    /// attachments (scrubber + time, one-at-a-time playback). No section
    /// header: the players are self-describing.
    var audioCard: some View {
        VStack(spacing: 10) {
            ForEach(Array(listing.attachments.enumerated()), id: \.offset) { idx, clip in
                if let url = viewModel.clipURL(clip) {
                    AudioAttachmentPlayer(
                        url: url,
                        name: clip.title ?? "Clip \(idx + 1)",
                        fixedWidth: nil,
                        onStartPlaying: {
                            // Don't play over the app's music.
                            if playerController.state.isPlaying { playerController.onPlayPause() }
                        }
                    )
                }
            }
        }
    }

    var actionRow: some View {
        HStack(spacing: 10) {
            PrimaryButton(respondLabel, size: .inline, enabled: canRespond) {
                if let convoId = viewModel.existingConvoId { openConversation(convoId: convoId, with: listing.author) }
                else { showRespond = true }
            }

            // Save matches the expanded player's save: a bare .xl bookmark,
            // no background — the 48pt frame is just the tap target.
            Button { Task { await viewModel.toggleSave() } } label: {
                LucideIcon(viewModel.isSaved ? .bookmarkFill : .bookmark, .xl)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving)
        }
    }

    /// Respond/Open-chat is enabled unless the listing is closed with no thread.
    var canRespond: Bool { viewModel.existingConvoId != nil || !viewModel.isClosed }

    var respondLabel: String {
        if viewModel.existingConvoId != nil { return "Open chat" }
        return viewModel.isClosed ? "Closed" : "Respond"
    }

}

// MARK: - Author + Comments

private extension ListingDetailScreen {
    /// Comments + (author-only) responses — no text headers: the author flips
    /// between the two with segmented pills (the app's 7D/30D toggle style);
    /// visitors get the comments flowing straight in after a hairline.
    var discussion: some View {
        VStack(alignment: .leading, spacing: 16) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5)

            if viewModel.isAuthor {
                HStack(spacing: 6) {
                    discussionPill("Comments", count: viewModel.comments.count, tab: .comments)
                    discussionPill("Responses", count: viewModel.responses.count, tab: .responses)
                    Spacer(minLength: 0)
                }
            }

            // The same subtle centred marker on your own post as on others' —
            // reflecting whichever list is showing.
            if viewModel.isAuthor, discussionTab == .responses {
                discussionMarker("Responses", count: viewModel.responses.count, loaded: viewModel.responsesLoaded)
                responsesContent
            } else {
                discussionMarker("Comments", count: viewModel.comments.count, loaded: viewModel.commentsLoaded)
                commentsContent
            }
        }
    }

    /// Small muted "label · count" centred under the divider (spinner while
    /// the list loads) — shared by the author and visitor views.
    func discussionMarker(_ label: String, count: Int, loaded: Bool) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.appFootnoteMedium)
                .foregroundStyle(Color.vText2)
            if !loaded {
                ProgressView().tint(.white.opacity(0.35)).scaleEffect(0.6)
            } else {
                Text("\(count)")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }


    func discussionPill(_ label: String, count: Int, tab: DiscussionTab) -> some View {
        let selected = discussionTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.22)) { discussionTab = tab }
        } label: {
            Text(count > 0 ? "\(label) · \(count)" : label)
                .font(.appFootnoteMedium)
                .foregroundStyle(selected ? .black : Color.vText2)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Color.white : Color.white.opacity(0.06), in: Capsule())
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Author-only: who's responded, tap to open that chat.
    @ViewBuilder
    var responsesContent: some View {
        if !viewModel.responsesLoaded {
            responsesSkeleton
        } else if viewModel.responses.isEmpty {
            Text("No one has responded yet.")
                .font(.appFootnote).foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.responses.enumerated()), id: \.element.id) { idx, response in
                    responseRow(response)
                    if idx < viewModel.responses.count - 1 {
                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                    }
                }
            }
        }
    }

    func responseRow(_ response: ApiListingResponse) -> some View {
        Button {
            if let convoId = response.convoId { openConversation(convoId: convoId, with: response.responder) }
        } label: {
            HStack(spacing: 11) {
                avatar(response.responder, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(response.responder.username)").font(.appSubheadlineSemibold).foregroundStyle(.white).lineLimit(1)
                    if let preview = response.messagePreview, !preview.isEmpty {
                        Text(preview).font(.appCaption).foregroundStyle(Color.vText3).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                LucideIcon(.messageCircle, .md).foregroundStyle(Color.vText3)
            }
            .padding(.vertical, 9)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(response.convoId == nil)
    }

    /// Shimmer bone colour for the loading placeholders.
    private var bone: Color { Color.white.opacity(0.08) }

    /// Placeholder rows shown while responses load.
    var responsesSkeleton: some View {
        VStack(spacing: 18) {
            ForEach(0 ..< 2, id: \.self) { _ in
                HStack(spacing: 11) {
                    Circle().fill(bone).frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(bone).frame(width: 130, height: 12)
                        RoundedRectangle(cornerRadius: 5).fill(bone).frame(width: 90, height: 10)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 2)
        .shimmering()
    }

    /// Placeholder rows shown while comments load — they resolve in the same
    /// concurrent pass as the responses skeleton, so both fill in together.
    var commentsSkeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(0 ..< 3, id: \.self) { _ in
                HStack(alignment: .top, spacing: 11) {
                    Circle().fill(bone).frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 5).fill(bone).frame(width: 110, height: 11)
                        RoundedRectangle(cornerRadius: 5).fill(bone).frame(maxWidth: .infinity).frame(height: 11)
                        RoundedRectangle(cornerRadius: 5).fill(bone).frame(width: 170, height: 11)
                    }
                }
            }
        }
        .padding(.top, 2)
        .shimmering()
    }

    /// The comments list — the composer is pinned at the screen bottom
    /// (`composerBar`), like the expanded player's.
    @ViewBuilder
    var commentsContent: some View {
        if !viewModel.commentsLoaded {
            commentsSkeleton
        } else if viewModel.comments.isEmpty {
            Text("No comments yet — start the conversation.")
                .font(.appFootnote).foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.comments) { comment in
                    VStack(alignment: .leading, spacing: 12) {
                        commentRow(comment)
                        if let replies = comment.replies, !replies.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(replies) { commentRow($0, isReply: true) }
                            }
                            // Indent replies under the parent's avatar + gutter.
                            .padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    /// Bottom comment bar — an `.appBody` field in a rounded pill with the
    /// gradient send circle. It's a `safeAreaInset` the system lifts over the
    /// keyboard (so the scroll insets and every comment stays reachable), and it
    /// clears the tab bar + mini player at rest / hugs the keyboard while typing.
    var composerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // "Replying to @user" chip — shown while the composer is aimed at a
            // thread; the ✕ clears it back to posting a new top-level comment.
            if let replyingTo = viewModel.replyingTo {
                HStack(spacing: 6) {
                    LucideIcon(.reply, .xs).foregroundStyle(Color.vText3)
                    Text("Replying to @\(replyingTo.user.username)")
                        .font(.appCaption2Medium).foregroundStyle(Color.vText2)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button { viewModel.replyingTo = nil } label: {
                        LucideIcon(.x, .xs).foregroundStyle(Color.vText3)
                            .frame(width: 24, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }

            composerRow
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 10)
        // Clear the floating tab bar + mini player at rest; while the keyboard
        // is up that chrome is behind it, so hug the keyboard instead. Driven by
        // `composerActive`, which ALSO hides the tab bar + mini player — all in
        // one keyboard-triggered transaction below, so nothing bounces.
        .padding(.bottom, conversationState.composerActive ? 10 : bottomChromeInset)
        .background {
            Color.vBar
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.vBorder).frame(height: 0.5)
                }
                // Bleed DOWNWARD only (behind the keyboard / home indicator),
                // like the chat input bar — ignoring all edges made the fill
                // fail to reach the bottom mid-dismiss, leaving a dark gap.
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.easeOut(duration: 0.22), value: canPostComment)
        .animation(.easeOut(duration: 0.2), value: viewModel.replyingTo?.id)
        // SCOPED animation for the composer's clearance change (and, via the
        // shared flag, the tab-bar / mini-player hide). Two rules that killed the
        // bounce: (1) NEVER wrap `composerActive` in `withAnimation` in the
        // keyboard handler — it merges with the system keyboard animation and
        // overshoots; a scoped `.animation(value:)` stays decoupled. (2) Use a
        // SLOW-START curve (easeInOut). The keyboard HIDES with a slow start
        // (ease-in); a fast-start easeOut here grows the 60pt clearance quicker
        // than the keyboard begins descending, so the pill hops UP ~50pt before
        // it falls (the tiny residual spring). easeInOut keeps the padding still
        // until the keyboard commits → monotonic both ways.
        .animation(.easeInOut(duration: 0.25), value: conversationState.composerActive)
        // Toggle the shared flag PLAINLY (no withAnimation). Gated on our own
        // field so a presented sheet's keyboard never moves this page.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            guard commentFocused else { return }
            conversationState.composerActive = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            conversationState.composerActive = false
        }
    }

    /// The avatar-pill field + gradient send circle (the row the "Replying to"
    /// chip sits above).
    var composerRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Your avatar + the field share one pill — the expanded player's
            // composer look.
            HStack(alignment: .center, spacing: 10) {
                myAvatar

                TextField("", text: $viewModel.commentText, prompt: Text(viewModel.replyingTo == nil ? "Add a comment…" : "Add a reply…").foregroundColor(Color.vText3), axis: .vertical)
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .lineLimit(1 ... 4)
                    .focused($commentFocused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            // Same send button as chat / track comments: accent-gradient circle with
            // an up-arrow that scale-fades in once there's something to post.
            if canPostComment || viewModel.isPostingComment {
                Button {
                    commentFocused = false
                    Task { await viewModel.postComment() }
                } label: {
                    Group {
                        if viewModel.isPostingComment {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    // Exactly the chat / track-comment send button (32pt circle).
                    .frame(width: 32, height: 32)
                    .background(LinearGradient.sendAccent, in: Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
                .padding(.bottom, 5) // optically centred against the pill's first line
            }
        }
    }

    /// Clearance for the floating tab bar (+ mini player when a track plays).
    var bottomChromeInset: CGFloat { 60 + playerController.miniPlayerAllowance }

    /// Signed-in user's 28pt avatar in the composer pill — identical styling
    /// to the player composer's (initial-letter fallback included).
    var myAvatar: some View {
        AvatarView(urlString: myAvatarUrl, name: myInitial, size: 28)
    }

    var canPostComment: Bool {
        !viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isPostingComment
    }

    func commentRow(_ comment: ApiListingComment, isReply: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { router.navigateToProfile(userId: comment.user.userId) } label: {
                avatar(comment.user, size: isReply ? 24 : 30)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button { router.navigateToProfile(userId: comment.user.userId) } label: {
                        Text("@\(comment.user.username)")
                            .font(.appLabel).foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    Text(MessageTime.agoLong(iso: comment.createdAt))
                        .font(.appCaption2).foregroundStyle(.white.opacity(0.3))
                }
                ExpandableText(comment.content)

                // Only top-level comments carry a reply affordance (one level
                // of nesting); tapping it aims the composer at this thread.
                if !isReply {
                    Button {
                        viewModel.startReply(to: comment)
                        commentFocused = true
                    } label: {
                        Text("Reply")
                            .font(.appCaption2Medium)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        // Lift the held comment while its options sheet is open (matches track comments).
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(commentOptions?.id == comment.id ? 0.09 : 0))
                .padding(.horizontal, -10)
                .padding(.vertical, -8)
        )
        .animation(.easeOut(duration: 0.05), value: commentOptions?.id)
        // Long-press to open options (report / delete your own) — same as track.
        .onLongPressGesture(minimumDuration: 0.35) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            commentOptions = comment
        }
    }

    func avatar(_ author: ApiListingAuthor, size: CGFloat) -> some View {
        AvatarView(urlString: author.profileImageUrl, name: author.username, size: size)
    }
}

// MARK: - Respond sheet

private extension ListingDetailScreen {
    var respondSheet: some View {
        RespondSheet(
            author: listing.author,
            listingTitle: listing.title,
            isSending: viewModel.isResponding
        ) { message in
            let result = await viewModel.respond(message: message)
            if let convoId = result.convoId {
                showRespond = false
                openConversation(convoId: convoId, with: listing.author)
            }
            return result.error
        }
    }

    /// Pushes a conversation with the given participant onto the nav stack.
    func openConversation(convoId: String, with person: ApiListingAuthor) {
        router.navigateToConversation(ActiveConversation(
            convoId: convoId,
            otherUserId: person.userId,
            username: person.username,
            avatarURL: person.profileImageUrl
        ))
    }
}

/// The "Respond to @author" composer sheet.
private struct RespondSheet: View {
    let author: ApiListingAuthor
    let listingTitle: String
    let isSending: Bool
    /// Returns an error string on failure, or nil on success.
    let onSend: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        // The app's standard sheet anatomy — same header/field/CTA as the
        // report and playlist/folder form sheets, sized to its rows.
        VStack(alignment: .leading, spacing: 0) {
            // The author's avatar as the leading tile (SheetHeader's
            // custom-leading form) instead of a glyph.
            SheetHeader(title: "Respond to @\(author.username)", subtitle: listingTitle, onClose: { dismiss() }) {
                authorAvatar
            }

            VStack(alignment: .leading, spacing: 14) {
                TextField(
                    "",
                    text: $message,
                    prompt: Text("Hey @\(author.username), I'd love to work on this…").foregroundColor(Color.vText3),
                    axis: .vertical
                )
                .font(.appBody)
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(4 ... 8)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vBorder))

                if let error {
                    ErrorBanner(error)
                }

                PrimaryButton("Send Message", busy: isSending, enabled: canSend) {
                    Task { error = await onSend(message) }
                }
                .disabled(!canSend)
                .animation(.easeOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
        // keyboardSafe: measured once at rest then grow-only — fits the content
        // exactly (no dead space) while keyboard compression can never re-target
        // the detent (the AttributeGraph-cycle hang this sheet used to hit).
        .selfSizedDetent(keyboardSafe: true)
        .sheetBackground()
        // Focus only after the present animation settles (the search-reveal
        // pattern) — raising the keyboard mid-presentation stacks two layout
        // storms into the same frames.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
    }

    var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// 36pt author avatar — the same tile size as the glyph headers use.
    private var authorAvatar: some View {
        AvatarView(urlString: author.profileImageUrl, name: author.username, size: 36)
    }
}

// MARK: - Reusable pieces

private extension ListingDetailScreen {

    /// Paragraph text in the app's standard body style (profile bio, legal docs).
    /// Description in the same size as the comment text here and in the
    /// expanded player (`appCalloutRegular`), so the page reads as one voice.
    func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.appCalloutRegular).foregroundStyle(Color.white.opacity(0.92))
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    func chipRow(_ items: [String]) -> some View {
        ChipFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { tag in
                Text(tag)
                    .font(.appLabel).foregroundStyle(.black)
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
            }
        }
    }

}

// MARK: - Comment options sheet

/// Options for a listing comment — the same `SheetHeader` + rows as the track
/// comment sheet (`CommentOptionsSheet`), so both read identically. (Reply is an
/// inline affordance on the row, not a sheet option.)
private struct ListingCommentOptionsSheet: View {
    let comment: ApiListingComment
    let isOwn: Bool
    let onReport: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: .messageCircle,
                title: comment.user.username,
                subtitle: comment.content
            ) { dismiss() }

            VStack(spacing: 0) {
                OptionSheetRow(icon: .copy, title: "Copy") {
                    UIPasteboard.general.string = comment.content
                    dismiss()
                }
                if isOwn {
                    OptionSheetRow(icon: .trash2, title: "Delete comment", tint: .vError) {
                        dismiss()
                        onDelete()
                    }
                } else {
                    OptionSheetRow(icon: .triangleAlert, title: "Report") {
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

