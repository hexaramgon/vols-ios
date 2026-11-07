//
//  ListingDetailScreen.swift
//  Volspire
//
//  Collab-board listing detail — the web `listing-detail` post page: a 53pt
//  "‹ Listings" band (author controls as round icon buttons), the post
//  (byline, title, description, tags, clips, stat + action footer), then the
//  author-only Responses section and the Comments section with its inline
//  composer at the top.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI
import UIKit

struct ListingDetailScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(PlayerController.self) private var playerController
    @Environment(ListingsStore.self) private var listingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ListingDetailViewModel
    @State private var showRespond = false
    @State private var showAdminOptions = false
    /// An author "⋯" row that opens its own sheet / cover once the menu has
    /// closed (one presentation at a time).
    @State private var pendingAdmin: AdminAction?
    private enum AdminAction { case edit, toggleStatus, share }
    /// The confirm a "⋯" sheet staged (delete listing / block author) — handed to the confirm modal as the sheet closes.
    @State private var sheetConfirm: DestructiveConfirm?
    @State private var showEdit = false
    /// The comment whose options sheet is open (long-press: copy / delete / report).
    @State private var commentOptions: ApiListingComment?
    /// Staged report → presented after the options sheet dismisses.
    @State private var pendingReportComment: ApiListingComment?
    @State private var reportingComment: ApiListingComment?
    /// Close / Reopen asks first, then confirms what happened.
    @State private var showStatusConfirm = false
    /// Your own listing: Responses and Comments as two tabs under the post.
    @State private var threadTab: ThreadTab = .responses
    enum ThreadTab: Hashable { case responses, comments }
    @Namespace private var threadUnderline
    @FocusState private var focusedField: Field?
    @Environment(ConversationState.self) private var conversationState
    // Non-author viewer "…": report the listing / author, or block the author.
    @State private var showViewerOptions = false
    @State private var pendingViewer: ViewerAction?
    @State private var reportTarget: ReportTarget?
    /// Signed-in user's avatar for the composer.
    @State private var myAvatarUrl: String?
    @State private var myInitial: String = "?"
    /// Set when the page comes back on screen (a pop back to it). iOS
    /// restores the text field that was focused before it left, raising the
    /// keyboard over a collapsed composer — a focus arriving right after a
    /// return is that restore, and is undone.
    @State private var hasAppeared = false
    @State private var reappearedAt: Date?

    enum Field: Hashable { case comment }

    init(listing: ApiListing) {
        _viewModel = State(wrappedValue: ListingDetailViewModel(listing: listing))
    }

    private var listing: ApiListing { viewModel.listing }

    var body: some View {
        Group {
            if viewModel.notFound {
                notFoundState
            } else {
                content
            }
        }
        // The header names who posted it and what kind of listing it is.
        .backTitleBand(
            "Listings",
            title: viewModel.notFound ? nil : "@\(listing.author.username)",
            subtitle: viewModel.notFound ? nil : listing.categoryLabel
        ) {
            if !viewModel.notFound { bandActions }
        }
        .task {
            viewModel.listings = listingsStore
            await viewModel.load()
        }
        // Own avatar for the composer — cached profile fetch, cheap.
        .task {
            guard let uid = dependencies.authManager.currentUserId,
                  let profile = try? await dependencies.supabaseService.getUserProfile(userId: uid)
            else { return }
            myAvatarUrl = profile.profileImageUrl
            myInitial = (profile.username?.first).map { String($0).uppercased() } ?? "?"
        }
        .sheet(isPresented: $showRespond) { respondSheet }
        .sheet(isPresented: $showAdminOptions, onDismiss: {
            sheetDidDismiss()
            switch pendingAdmin {
            case .edit: showEdit = true
            case .toggleStatus: showStatusConfirm = true
            case .share: share()
            case nil: break
            }
            pendingAdmin = nil
        }) { adminOptionsSheet }
        .sheet(item: $commentOptions, onDismiss: {
            if let comment = pendingReportComment {
                pendingReportComment = nil
                reportingComment = comment
            }
        }) { comment in
            ListingCommentOptionsSheet(
                comment: comment,
                canDelete: viewModel.canDeleteComment(comment),
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
            case .respond: respond()
            case .share: share()
            case .reportListing: reportTarget = .listing
            case .reportAuthor: reportTarget = .author
            case nil: break
            }
            pendingViewer = nil
            sheetDidDismiss()
        }) { viewerOptionsSheet }
        .sheet(item: $reportTarget) { target in
            switch target {
            case .listing:
                ReportSheet(targetType: .listing, targetId: listing.listingId, subject: listing.title)
            case .author:
                ReportSheet(targetType: .user, targetId: listing.author.userId, subject: "@\(listing.author.username)")
            }
        }
        .fullScreenCover(isPresented: $showEdit, onDismiss: { Task { await viewModel.load() } }) {
            CreateListingScreen(viewModel: CreateListingViewModel(
                editing: listing,
                supabaseService: dependencies.supabaseService,
                authManager: dependencies.authManager
            ))
        }
        // Close / Reopen: one sheet that explains it, shows progress on its
        // button, and closes once it's done — the page then eases into the
        // new state (Closed pill, lock icon, Respond → Closed).
        .sheet(isPresented: $showStatusConfirm) {
            ListingStatusSheet(closing: !viewModel.isClosed) {
                await viewModel.toggleStatus()
            }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                post
                if viewModel.isAuthor {
                    // One at a time, not stacked into one long list.
                    threadTabs
                    Group {
                        if threadTab == .responses { responsesSection } else { commentsSection }
                    }
                    .transition(.opacity)
                    .id(threadTab)
                } else {
                    commentsSection
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 24)
        }
        // Replying (Instagram-style): once the keyboard is up, glide the
        // comment to sit just above the composer, so you can read what you're
        // answering right where you type.
        .onChange(of: viewModel.replyingTo?.commentId) { _, id in
            guard let id else { return }
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        }
        .scrollIndicators(.hidden)
        .refreshable { await viewModel.load() }
        .scrollDismissesKeyboard(.interactively)
        // The composer floats over the page wherever you are in the thread.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.currentUserId != nil {
                commentDock
            } else {
                Color.clear.frame(height: dockBottomPadding)
            }
        }
        // While typing, the tab bar + mini-player slide away (like a DM).
        .onChange(of: focusedField) { _, field in
            if field != nil, let back = reappearedAt, Date.now.timeIntervalSince(back) < 1.2 {
                focusedField = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                return
            }
            conversationState.composerActive = field != nil
            // Typing a comment on your own listing: show the Comments tab, so
            // what you post lands where you can see it.
            if field != nil, viewModel.isAuthor, threadTab != .comments {
                withAnimation(.smooth(duration: 0.25)) { threadTab = .comments }
            }
        }
        // Leaving the page (a profile pushed from a comment, back, a tab
        // switch): put the keyboard away with the composer, so returning
        // never finds the keyboard up over a collapsed input.
        .onAppear {
            guard hasAppeared else { hasAppeared = true; return }
            reappearedAt = .now
            // The restore can land without touching @FocusState — put the
            // keyboard away once the pop has settled, unless they've tapped in.
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                if focusedField == nil {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .onDisappear {
            focusedField = nil
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            conversationState.composerActive = false
        }
    }

    /// The band's trailing control — one ⋯ for everyone: author → Edit,
    /// Close/Reopen, Delete; visitor → report / block.
    @ViewBuilder
    private var bandActions: some View {
        if viewModel.isAuthor {
            HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize) { showAdminOptions = true }
        } else if viewModel.currentUserId != nil {
            HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize) { showViewerOptions = true }
        }
    }

    private var notFoundState: some View {
        VStack(spacing: 24) {
            EmptyStateView(
                icon: .megaphone,
                title: "Listing not found",
                message: "It may have been removed or set private."
            )
            SecondaryButton("Back home", size: .inline, expands: false) { dismiss() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private enum ViewerAction { case respond, share, reportListing, reportAuthor }
    private enum ReportTarget: Int, Identifiable { case listing, author; var id: Int { rawValue } }

    /// Viewer options as a slide-up sheet.
    private var viewerOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: listing.categoryIcon, title: listing.title, subtitle: "@\(listing.author.username)") {
                showViewerOptions = false
            }

            VStack(spacing: 0) {
                // The footer's actions too, so the ⋯ holds everything.
                if canRespond {
                    OptionSheetRow(icon: viewModel.existingConvoId != nil ? .messageSquare : .reply, title: respondLabel) {
                        pendingViewer = .respond
                        showViewerOptions = false
                    }
                }
                OptionSheetRow(icon: viewModel.isSaved ? .bookmarkFill : .bookmark,
                               title: viewModel.isSaved ? "Saved" : "Save") {
                    guard !viewModel.isSaving else { return }
                    Task { await viewModel.toggleSave() }
                    showViewerOptions = false
                }
                OptionSheetRow(icon: .share2, title: "Share") {
                    pendingViewer = .share
                    showViewerOptions = false
                }
                OptionSheetRow(icon: .flag, title: "Report listing") {
                    pendingViewer = .reportListing
                    showViewerOptions = false
                }
                OptionSheetRow(icon: .flag, title: "Report @\(listing.author.username)") {
                    pendingViewer = .reportAuthor
                    showViewerOptions = false
                }
                OptionSheetRow(icon: .ban, title: "Block @\(listing.author.username)", tint: .vError) {
                    sheetConfirm = .block(username: listing.author.username) {
                        dependencies.contentActions.block(userId: listing.author.userId, username: listing.author.username)
                        dismiss()
                    }
                }
            }
            .padding(.top, 6)
            .confirmModal($sheetConfirm)
        }
        .selfSizedDetent()
        .sheetBackground()
    }

    /// An options sheet closed: clear any confirm it staged (the confirm
    /// itself leaves the page on delete / block).
    private func sheetDidDismiss() {
        sheetConfirm = nil
    }

    /// Author "⋯" — Edit, Close / Reopen, Delete.
    private var adminOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: listing.categoryIcon, title: listing.title, subtitle: viewModel.isClosed ? "Closed" : "Open") {
                showAdminOptions = false
            }

            OptionSheetRow(icon: .pencil, title: "Edit listing") {
                pendingAdmin = .edit
                showAdminOptions = false
            }
            .padding(.top, 6)
            OptionSheetRow(icon: viewModel.isClosed ? .lockOpen : .lock,
                           title: viewModel.isClosed ? "Reopen listing" : "Close listing") {
                guard !viewModel.isTogglingStatus else { return }
                pendingAdmin = .toggleStatus
                showAdminOptions = false
            }
            OptionSheetRow(icon: .share2, title: "Share") {
                pendingAdmin = .share
                showAdminOptions = false
            }
            OptionSheetRow(icon: .trash2, title: "Delete listing", tint: .vError) {
                sheetConfirm = DestructiveConfirm(
                    title: "Delete this listing?",
                    message: "It's removed for everyone, with its comments. This can't be undone."
                ) {
                    dependencies.contentActions.deleteListing(listing)
                    dismiss()
                }
            }
            .confirmModal($sheetConfirm)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}

// MARK: - Post

private extension ListingDetailScreen {
    /// The home listing card, opened up: byline, the ask, the full pitch, then
    /// the card footer (counts left, actions right).
    var post: some View {
        VStack(alignment: .leading, spacing: 0) {
            byline

            Text(listing.title)
                .font(.appTitle2SemiboldCompact)
                .tracking(-0.4)
                .foregroundStyle(Color.vText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            if let desc = listing.description, !desc.isEmpty {
                Text(desc)
                    .font(.appSubheadline)
                    // Near-full ink (0.9): readable, a touch under the title.
                    .foregroundStyle(Color.vTextRow)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
            }

            if let tags = listing.tags, !tags.isEmpty {
                ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.appCaption)
                            .foregroundStyle(Color.vText2)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.ink(0.06), in: Capsule())
                    }
                }
                .padding(.top, 16)
            }

            if !listing.attachments.isEmpty {
                audioClips.padding(.top, 16)
            }

            footer.padding(.top, 20)

            // Author only: Listing Analytics, like Profile's Artist Dashboard.
            if viewModel.isAuthor {
                DashboardLinkCard(title: "Listing Analytics", subtitle: analyticsSubtitle, accentTile: true) {
                    router.navigateToListingAnalytics(listingId: listing.listingId, title: listing.title)
                }
                .padding(.top, 20)
            }
        }
        .padding(.top, 20)
        // Your own listing goes straight into its Responses | Comments tabs
        // (they carry the hairline); visitors get the divider before comments.
        .padding(.bottom, viewModel.isAuthor ? 8 : 20)
        .overlay(alignment: .bottom) { if !viewModel.isAuthor { hairline } }
    }

    /// "9 views" from the listing's own count, once it has any.
    var analyticsSubtitle: String {
        guard let views = listing.viewCount, views > 0 else { return "Views, responses & saves" }
        return "\(views.formatted()) \(views == 1 ? "view" : "views") so far"
    }

    var hairline: some View {
        Rectangle().fill(Color.vDivider).frame(height: 1)
    }

    var byline: some View {
        HStack(spacing: 12) {
            Button { router.navigateToProfile(userId: listing.author.userId) } label: {
                HStack(spacing: 12) {
                    AvatarView(urlString: listing.author.profileImageUrl, name: listing.author.username, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("@\(listing.author.username)")
                            .font(.appSubheadlineSemibold)
                            .foregroundStyle(Color.vText)
                            .lineLimit(1)
                        Text("\(listing.categoryLabel) · \(MessageTime.ago(MessageTime.parse(listing.createdAt)))")
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if viewModel.isClosed { closedPill }
        }
    }

    /// Grey, not red — closed is a state, not an error.
    var closedPill: some View {
        HStack(spacing: 4) {
            LucideIcon(.lock, .xs)
            Text("Closed").font(.appCaptionMedium)
        }
        .foregroundStyle(Color.vText2)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.vControl, in: Capsule())
    }

    /// Audio clips — the shared inline player (scrubber + time, one at a time).
    var audioClips: some View {
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

    /// Right-aligned actions: visitors get Save, Share and the white Respond capsule,
    /// the author Share only.
    var footer: some View {
        HStack(spacing: 20) {
            if viewModel.isAuthor, let views = listing.viewCount { ListingViewCount(count: views) }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                // Bare icons, like the listing cards.
                if !viewModel.isAuthor {
                    CardActionIcon(
                        icon: viewModel.isSaved ? .bookmarkFill : .bookmark,
                        active: viewModel.isSaved,
                        activeColor: .vSaved,
                        size: IconSize.xl.rawValue
                    ) {
                        guard !viewModel.isSaving else { return }
                        Task { await viewModel.toggleSave() }
                    }
                    .accessibilityLabel(viewModel.isSaved ? "Saved" : "Save")
                }
                CardActionIcon(icon: .share2, size: IconSize.xl.rawValue) { share() }
                .accessibilityLabel("Share")
                if !viewModel.isAuthor { respondButton.padding(.leading, 6) }
            }
        }
    }

    /// Respond (or open the existing chat) — the footer capsule and the ⋯ row.
    func respond() {
        if let convoId = viewModel.existingConvoId { openConversation(convoId: convoId, with: listing.author) }
        else { showRespond = true }
    }

    func share() {
        UIApplication.presentActivitySheet(["\(listing.title) \(viewModel.shareURL)"])
    }

    var respondButton: some View {
        Button { respond() } label: {
            HStack(spacing: 6) {
                LucideIcon(viewModel.existingConvoId != nil ? .messageSquare : .reply, .sm)
                Text(respondLabel).font(.appSubheadlineSemibold)
            }
            .foregroundStyle(Color.vOnInverse)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(Color.vInverse, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canRespond)
        .opacity(canRespond ? 1 : 0.3)
    }

    /// Respond/Open-chat is enabled unless the listing is closed with no thread.
    var canRespond: Bool { viewModel.existingConvoId != nil || !viewModel.isClosed }

    var respondLabel: String {
        if viewModel.existingConvoId != nil { return "Open chat" }
        return viewModel.isClosed ? "Closed" : "Respond"
    }
}

// MARK: - Responses (author only)

private extension ListingDetailScreen {
    var responsesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !viewModel.responsesLoaded {
                SkeletonRows(count: 2, thumb: .circle(size: 32), horizontalPadding: 0)
            } else if viewModel.responses.isEmpty {
                // Centred, like the comments' empty line.
                Text("No responses yet. Each one opens a DM with you.")
                    .font(.appCaption).foregroundStyle(Color.vText3)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.responses) { responseRow($0) }
                }
                .padding(.horizontal, -ViewConst.screenPaddings)
            }
        }
        .padding(.bottom, 8)
    }

    /// Responses · Comments tabs (the profile tab bar's look: active = ink
    /// semibold with a 48×4 ink bar on a hairline; counts in grey).
    var threadTabs: some View {
        HStack(spacing: 0) {
            threadTabButton(.responses, "Responses", count: listing.responseCount ?? viewModel.responses.count)
            threadTabButton(.comments, "Comments", count: listing.commentCount ?? viewModel.comments.count)
        }
        .background(alignment: .bottom) { hairline }
        .padding(.bottom, 16)
    }

    func threadTabButton(_ tab: ThreadTab, _ title: String, count: Int) -> some View {
        let active = threadTab == tab
        return Button {
            Haptics.selection()
            withAnimation(.smooth(duration: 0.25)) { threadTab = tab }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(active ? .appSubheadlineSemibold : .appSubheadlineMedium)
                    .foregroundStyle(active ? Color.vText : Color.vText3)
                if count > 0 {
                    Text(count.compactCount)
                        .font(.appCaptionMedium)
                        .monospacedDigit()
                        .foregroundStyle(Color.vText3)
                }
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if active {
                    Capsule().fill(Color.vInverse).frame(width: 48, height: 4)
                        .matchedGeometryEffect(id: "threadUnderline", in: threadUnderline)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    func responseRow(_ response: ApiListingResponse) -> some View {
        Button {
            if let convoId = response.convoId { openConversation(convoId: convoId, with: response.responder) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                AvatarView(urlString: response.responder.profileImageUrl, name: response.responder.username, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("@\(response.responder.username)")
                            .font(.appSubheadlineSemibold).foregroundStyle(Color.vText).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(MessageTime.ago(MessageTime.parse(response.createdAt)))
                            .font(.appCaption).foregroundStyle(Color.vText3).monospacedDigit()
                    }
                    if let preview = response.messagePreview, !preview.isEmpty {
                        Text(preview)
                            .font(.appCaption).foregroundStyle(Color.vText2)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(response.convoId == nil)
    }
}

// MARK: - Comments

private extension ListingDetailScreen {
    var commentsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // No heading — the thread follows the post's hairline directly.
            if !viewModel.commentsLoaded {
                SkeletonRows(count: 3, thumb: .circle(size: 32), horizontalPadding: 0)
            } else if viewModel.comments.isEmpty {
                Text(viewModel.currentUserId != nil ? "No comments yet. Be the first." : "No comments yet.")
                    .font(.appCaption).foregroundStyle(Color.vText3)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(viewModel.comments) { commentRow($0) }
                }
            }
        }
        .padding(.top, 20)
        .animation(.easeOut(duration: 0.18), value: viewModel.replyingTo?.id)
        .animation(.easeOut(duration: 0.18), value: viewModel.commentError)
    }

    /// Above the tab bar + mini-player at rest; just over the keyboard while
    /// typing (both slide away then). Keyed on `composerActive` — the SAME
    /// flag (and timing, below) that hides the tab bar — so the dock and the
    /// bar move together instead of the dock dropping behind the still-visible
    /// bar for a few frames.
    var dockBottomPadding: CGFloat {
        conversationState.composerActive ? 8 : playerController.contentBottomInset - ViewConst.safeAreaInsets.bottom + 8
    }

    /// The tab bar's hide/show animation (RootTabView) — the dock rides it.
    static let dockMotion: Animation = .easeInOut(duration: 0.25)

    /// The draft the dock edits — the reply's while replying, else the comment's.
    var dockText: Binding<String> {
        Binding(
            get: { viewModel.replyingTo == nil ? viewModel.commentText : viewModel.replyText },
            set: { new in
                let capped = String(new.prefix(1000))
                if viewModel.replyingTo == nil { viewModel.commentText = capped } else { viewModel.replyText = capped }
            }
        )
    }

    /// The floating comment dock, in the Now Playing composer's anatomy: one
    /// rounded input (28pt avatar + 16pt field, growing to 6 lines) that stays
    /// put while you scroll the thread, with the reply banner inside its top
    /// and the shared send button once there's text. Reply opens it rather
    /// than a field under the comment.
    var commentDock: some View {
        let focused = focusedField == .comment
        let replying = viewModel.replyingTo
        let canSend = !dockText.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let shape = RoundedRectangle(cornerRadius: focused ? 22 : 24, style: .continuous)

        return VStack(alignment: .leading, spacing: 8) {
            if let error = viewModel.commentError {
                ErrorBanner(error).transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                if let replying {
                    HStack(spacing: 6) {
                        Text("Replying to @\(replying.user.username)")
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                        Spacer(minLength: 0)
                        Button { withAnimation(Self.dockMotion) { viewModel.toggleReply(to: replying) } } label: {
                            // Same size as Now Playing's reply ×.
                            LucideIcon(.x, .md)
                                .foregroundStyle(Color.vText3)
                                .frame(width: 28, height: 28)
                                .minimumHitArea(for: 28)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Cancel reply")
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .padding(.top, 10)
                    // Fades in only once the dock has settled (dockMotion is
                    // 0.25s) — appearing at once, it rode the dock down as the
                    // tab bar slid away and read as sliding in from the top.
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.15).delay(0.25)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
                }

                HStack(alignment: .center, spacing: 10) {
                    AvatarView(urlString: myAvatarUrl, name: myInitial, size: 28)
                    TextField("", text: dockText,
                              prompt: Text(replying.map { "Reply to @\($0.user.username)…" } ?? "Add a comment…")
                                .foregroundColor(Color.vText3),
                              axis: .vertical)
                        .font(.appCalloutRegular)
                        .foregroundStyle(Color.vText)
                        .tint(Color.vText)
                        .focused($focusedField, equals: .comment)
                        .lineLimit(focused ? 1 ... 6 : 1 ... 1)
                    NearLimitCounter(count: dockText.wrappedValue.count, limit: 1000)
                    if canSend || viewModel.isPostingComment {
                        SendButton(busy: viewModel.isPostingComment) {
                            Task {
                                if viewModel.replyingTo == nil { await viewModel.postComment() } else { await viewModel.postReply() }
                                if dockText.wrappedValue.isEmpty { focusedField = nil }
                            }
                        }
                        .padding(.leading, 2)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            // Glass over the page's content, with a hairline edge.
            .background(.regularMaterial, in: shape)
            .overlay { shape.strokeBorder(Color.ink(0.08), lineWidth: 0.5) }
            .contentShape(shape)
            .onTapGesture { focusedField = .comment }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, dockBottomPadding)
        .animation(Self.dockMotion, value: conversationState.composerActive)
        .animation(.smooth(duration: 0.22), value: focused)
        .animation(.easeOut(duration: 0.15), value: canSend)
        .animation(.easeOut(duration: 0.18), value: replying?.commentId)
        .animation(.easeOut(duration: 0.18), value: viewModel.commentError)
    }

    /// `AnyView`: the row nests its replies by calling itself, which an opaque
    /// return type can't express.
    func commentRow(_ comment: ApiListingComment, isReply: Bool = false) -> AnyView {
        AnyView(HStack(alignment: .top, spacing: 12) {
            Button { router.navigateToProfile(userId: comment.user.userId) } label: {
                AvatarView(urlString: comment.user.profileImageUrl, name: comment.user.username, size: 32)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Button { router.navigateToProfile(userId: comment.user.userId) } label: {
                        Text("@\(comment.user.username)")
                            .font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                    }
                    .buttonStyle(.plain)
                    Text(MessageTime.ago(MessageTime.parse(comment.createdAt)))
                        .font(.appCaption).foregroundStyle(Color.vText3).monospacedDigit()
                }
                // Near-full ink (0.9), like the description.
                ExpandableText(comment.content, font: .appSubheadline, textColor: Color.vTextRow)
                    .padding(.top, 2)

                commentActions(comment, isReply: isReply)

                // Replies — one level, oldest first, under the text column.
                if !isReply, let replies = comment.replies, !replies.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(replies) { commentRow($0, isReply: true) }
                    }
                    .padding(.top, 16)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        // The comment being replied to lifts like a tapped comment in Now
        // Playing — a soft rounded wash behind it while the reply is open.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.ink(viewModel.replyingTo?.commentId == comment.commentId ? 0.08 : 0))
                // Only the wash animates — on the whole row this animation
                // also caught the reply's relayout and slid rows around.
                .animation(.easeOut(duration: 0.2), value: viewModel.replyingTo?.commentId)
                .padding(.horizontal, -10)
                .padding(.vertical, -8)
        )
        .id(comment.commentId)
        // Long-press for the options sheet (copy / delete / report).
        .onLongPressGesture(minimumDuration: 0.35) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            commentOptions = comment
        })
    }

    /// Just Reply (top-level, signed in). Copy / Delete / Report live behind
    /// the long-press options sheet, like track comments.
    @ViewBuilder
    func commentActions(_ comment: ApiListingComment, isReply: Bool) -> some View {
        if !isReply, viewModel.currentUserId != nil {
            Button {
                // The banner grows the dock (and the page's bottom inset) in
                // step with the tab bar sliding away — not a hard jump.
                withAnimation(Self.dockMotion) { viewModel.toggleReply(to: comment) }
                // Replies go through the docked composer.
                focusedField = viewModel.replyingTo != nil ? .comment : nil
            } label: {
                actionLabel(.reply, "Reply")
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
    }

    func actionLabel(_ icon: LucideIcon.Name, _ title: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(icon, .sm)
            Text(title).font(.appCaption.weight(.semibold))
        }
        .foregroundStyle(Color.vText2)
        .contentShape(.rect)
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

/// The "Respond to @author" composer sheet (web `ListingRespondModal`) — the
/// listing page's Respond, and the Home cards' reply icon.
struct RespondSheet: View {
    let author: ApiListingAuthor
    let listingTitle: String
    let isSending: Bool
    /// Returns an error string on failure, or nil on success.
    let onSend: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    private let maxLength = 2000

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(title: "Respond to @\(author.username)", onClose: { dismiss() }) {
                AvatarView(urlString: author.profileImageUrl, name: author.username, size: 36)
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(listingTitle)
                        .font(.appSubheadlineSemibold).foregroundStyle(Color.vText).lineLimit(1)
                    Text("Your message starts a DM with the poster. Introduce yourself and what you bring.")
                        .font(.appCaption).foregroundStyle(Color.vText3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField(
                    "",
                    text: $message,
                    prompt: Text("Hey @\(author.username), I'd love to work on this…").foregroundColor(Color.vText3),
                    axis: .vertical
                )
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .tint(Color.vText)
                .lineLimit(5, reservesSpace: true)
                .focused($focused)
                .disabled(isSending)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(focused ? Color.vFieldFocus : Color.vField,
                            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .onChange(of: message) { _, new in
                    if new.count > maxLength { message = String(new.prefix(maxLength)) }
                }

                HStack {
                    Text(error ?? "Share a link, your style, availability.")
                        .foregroundStyle(error == nil ? Color.vText3 : Color.vError)
                    Spacer(minLength: 8)
                    Text("\(message.count)/\(maxLength)").monospacedDigit().foregroundStyle(Color.vText3)
                }
                .font(.appCaption)

                CancelSendButtons(
                    canSend: canSend,
                    isSending: isSending,
                    onCancel: { dismiss() }
                ) { Task { error = await onSend(message) } }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .keyboardSafeForm()
        }
        // Fixed .large detent: a measured detent here hit the AttributeGraph-
        // cycle hang, and a short .height one got stretched + sprung to the
        // top when the keyboard opened. Full height doesn't move.
        .presentationDetents([.large])
        .sheetBackground()
        // Focus only after the present animation settles.
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
        }
    }

    var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
}

// MARK: - Comment options sheet

/// Long-press options for a listing comment — the same `SheetHeader` + rows as
/// the track comment sheet.
private struct ListingCommentOptionsSheet: View {
    let comment: ApiListingComment
    let canDelete: Bool
    let onReport: () -> Void
    /// Runs once the Delete confirm (the centered modal) is accepted.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingConfirm: DestructiveConfirm?

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
                if canDelete {
                    OptionSheetRow(icon: .trash2, title: "Delete comment", tint: .vError) {
                        pendingConfirm = DestructiveConfirm(
                            title: "Delete this comment?",
                            message: "Its replies go with it. This can't be undone."
                        ) { onDelete() }
                    }
                } else {
                    OptionSheetRow(icon: .flag, title: "Report") {
                        dismiss()
                        onReport()
                    }
                }
            }
            .padding(.top, 6)
            .confirmModal($pendingConfirm)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}

/// Close / Reopen confirmation: what it means, Cancel + the action. The
/// action button spins while the request runs; success closes the sheet
/// (with a success haptic), failure stays here with the reason.
private struct ListingStatusSheet: View {
    /// Captured when opened, so the copy can't flip mid-request.
    let closing: Bool
    let onConfirm: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(
                icon: closing ? .lock : .lockOpen,
                title: closing ? "Close this listing?" : "Reopen this listing?",
                subtitle: nil
            ) { dismiss() }

            VStack(alignment: .leading, spacing: 16) {
                Text(closing
                     ? "People won't be able to respond anymore. Existing conversations stay, and you can reopen it anytime."
                     : "It goes back on the board and people can respond to it again.")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .fixedSize(horizontal: false, vertical: true)

                if failed {
                    ErrorBanner(closing ? "Couldn't close the listing. Try again." : "Couldn't reopen the listing. Try again.")
                        .transition(.opacity)
                }

                // The app's sheet footer (Collab Request / Respond): Close is a
                // red action, Reopen the accent.
                CancelSendButtons(
                    sendTitle: closing ? "Close listing" : "Reopen listing",
                    destructive: closing,
                    canSend: true,
                    isSending: busy,
                    onCancel: { dismiss() },
                    onSend: confirm
                )
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .animation(.smooth(duration: 0.25), value: failed)
        .selfSizedDetent()
        .sheetBackground()
        .interactiveDismissDisabled(busy)
    }

    private func confirm() {
        guard !busy else { return }
        busy = true
        failed = false
        Task {
            let ok = await onConfirm()
            busy = false
            if ok {
                Haptics.success()
                dismiss()
            } else {
                failed = true
            }
        }
    }
}
