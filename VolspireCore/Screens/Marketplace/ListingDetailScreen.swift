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
    @State private var showDeleteConfirm = false
    @State private var showAdminOptions = false
    @State private var pendingAdminDelete = false
    @State private var showEdit = false
    /// The comment whose options sheet is open (long-press: copy / delete / report).
    @State private var commentOptions: ApiListingComment?
    /// Staged report → presented after the options sheet dismisses.
    @State private var pendingReportComment: ApiListingComment?
    @State private var reportingComment: ApiListingComment?
    /// The comment awaiting the "Delete comment" confirm.
    @State private var deletingComment: ApiListingComment?
    /// Close / Reopen asks first, then confirms what happened.
    @State private var showStatusConfirm = false
    /// Staged by the long-press sheet's Delete; confirmed once it dismisses.
    @State private var pendingDeleteComment: ApiListingComment?
    @FocusState private var focusedField: Field?
    // Non-author viewer "…": report the listing / author, or block the author.
    @State private var showViewerOptions = false
    @State private var pendingViewer: ViewerAction?
    @State private var reportTarget: ReportTarget?
    @State private var showBlockAuthor = false
    /// Signed-in user's avatar for the composer.
    @State private var myAvatarUrl: String?
    @State private var myInitial: String = "?"

    enum Field: Hashable { case comment, reply }

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
        .backTitleBand("Listings") {
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
            if pendingAdminDelete { pendingAdminDelete = false; showDeleteConfirm = true }
        }) { adminOptionsSheet }
        .sheet(item: $commentOptions, onDismiss: {
            if let comment = pendingReportComment {
                pendingReportComment = nil
                reportingComment = comment
            }
            // Delete confirms once the options sheet has gone.
            if let comment = pendingDeleteComment {
                pendingDeleteComment = nil
                deletingComment = comment
            }
        }) { comment in
            ListingCommentOptionsSheet(
                comment: comment,
                canDelete: viewModel.canDeleteComment(comment),
                onReport: { pendingReportComment = comment },
                onDelete: { pendingDeleteComment = comment }
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
            "Delete listing",
            isPresented: $showDeleteConfirm,
            message: "It will be permanently deleted. This cannot be undone."
        ) {
            Task { if await viewModel.deleteListing() { dismiss() } }
        }
        .destructiveConfirm(
            "Delete comment",
            isPresented: Binding(get: { deletingComment != nil }, set: { if !$0 { deletingComment = nil } }),
            message: "This can't be undone."
        ) {
            if let comment = deletingComment { Task { await viewModel.deleteComment(comment) } }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                post
                if viewModel.isAuthor { responsesSection }
                commentsSection
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.bottom, 40 + playerController.contentBottomInset)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    /// The band's trailing controls: author → Edit, Close/Reopen, ⋯ (delete);
    /// visitor → ⋯ (report / block).
    @ViewBuilder
    private var bandActions: some View {
        if viewModel.isAuthor {
            // Same bare icon as the listing's Save / Share.
            CardActionIcon(icon: .pencil) { showEdit = true }
                .accessibilityLabel("Edit listing")
            CardActionIcon(icon: viewModel.isClosed ? .lockOpen : .lock) {
                guard !viewModel.isTogglingStatus else { return }
                showStatusConfirm = true
            }
            .opacity(viewModel.isTogglingStatus ? 0.5 : 1)
            .accessibilityLabel(viewModel.isClosed ? "Reopen listing" : "Close listing")
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

    private enum ViewerAction { case reportListing, reportAuthor, block }
    private enum ReportTarget: Int, Identifiable { case listing, author; var id: Int { rawValue } }

    /// Viewer options as a slide-up sheet.
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
                OptionSheetRow(icon: .ban, title: "Block @\(listing.author.username)", tint: .vError) {
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

    /// Author "⋯" — Edit and Close/Reopen live in the band; the menu holds Delete.
    private var adminOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: listing.categoryIcon, title: listing.title, subtitle: viewModel.isClosed ? "Closed" : "Open") {
                showAdminOptions = false
            }

            OptionSheetRow(icon: .trash2, title: "Delete listing", tint: .vError) {
                pendingAdminDelete = true
                showAdminOptions = false
            }
            .padding(.top, 6)
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
                .font(.appLargeTitle)
                .tracking(-0.4)
                .foregroundStyle(Color.vText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)

            if let desc = listing.description, !desc.isEmpty {
                Text(desc)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
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
        }
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) { hairline }
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

    /// Stats left; visitors get Save, Share and the white Respond capsule,
    /// the author Share only.
    var footer: some View {
        HStack(spacing: 20) {
            StatCount(icon: .users, value: listing.responseCount ?? 0)
            StatCount(icon: .messageCircle, value: listing.commentCount ?? 0)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                // Bare icons, like the listing cards.
                if !viewModel.isAuthor {
                    CardActionIcon(
                        icon: viewModel.isSaved ? .bookmarkFill : .bookmark,
                        active: viewModel.isSaved,
                        popOn: viewModel.isSaved
                    ) {
                        guard !viewModel.isSaving else { return }
                        Task { await viewModel.toggleSave() }
                    }
                    .accessibilityLabel(viewModel.isSaved ? "Saved" : "Save")
                }
                CardActionIcon(icon: .share2) {
                    UIApplication.presentActivitySheet(["\(listing.title) \(viewModel.shareURL)"])
                }
                .accessibilityLabel("Share")
                if !viewModel.isAuthor { respondButton.padding(.leading, 6) }
            }
        }
    }

    var respondButton: some View {
        Button {
            if let convoId = viewModel.existingConvoId { openConversation(convoId: convoId, with: listing.author) }
            else { showRespond = true }
        } label: {
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

    /// "7 Comments" / "1 Response" — one semibold line, like the player's
    /// comments header; just the noun while there are none.
    func sectionHeading(_ title: String, count: Int) -> some View {
        let singular = String(title.dropLast())
        let text = count == 0 ? title : "\(count) \(count == 1 ? singular : title)"
        return Text(text)
            .font(.appSubheadlineSemibold)
            .foregroundStyle(Color.vText)
            .monospacedDigit()
    }
}

// MARK: - Responses (author only)

private extension ListingDetailScreen {
    var responsesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeading("Responses", count: listing.responseCount ?? viewModel.responses.count)

            if !viewModel.responsesLoaded {
                SkeletonRows(count: 2, thumb: .circle(size: 32), horizontalPadding: 0)
            } else if viewModel.responses.isEmpty {
                Text("No responses yet. Each one opens a DM with you.")
                    .font(.appCaption).foregroundStyle(Color.vText3)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.responses) { responseRow($0) }
                }
                .padding(.horizontal, -ViewConst.screenPaddings)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) { hairline }
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
            sectionHeading("Comments", count: listing.commentCount ?? viewModel.comments.count)
                .padding(.bottom, -8)

            if viewModel.currentUserId != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        AvatarView(urlString: myAvatarUrl, name: myInitial, size: 32)
                        composerCapsule(
                            text: $viewModel.commentText,
                            placeholder: "Add a comment",
                            field: .comment
                        ) { Task { await viewModel.postComment() } }
                    }
                    if viewModel.replyingTo == nil, let error = viewModel.commentError {
                        ErrorBanner(error)
                    }
                }
            }

            if !viewModel.commentsLoaded {
                SkeletonRows(count: 3, thumb: .circle(size: 32), horizontalPadding: 0)
            } else if viewModel.comments.isEmpty {
                Text(viewModel.currentUserId != nil ? "No comments yet. Be the first." : "No comments yet.")
                    .font(.appCaption).foregroundStyle(Color.vText3)
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

    /// The 40pt field capsule with the send button inside it — grey until
    /// there's text, then the send accent.
    func composerCapsule(
        text: Binding<String>,
        placeholder: String,
        field: Field,
        onCancel: (() -> Void)? = nil,
        onSend: @escaping () -> Void
    ) -> some View {
        let hasText = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let focused = focusedField == field
        return HStack(spacing: 6) {
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.vText3))
                .font(.appSubheadline)
                .foregroundStyle(Color.vText)
                .tint(Color.vText)
                .focused($focusedField, equals: field)
                .submitLabel(.send)
                .onSubmit { if hasText { onSend() } }
                .onChange(of: text.wrappedValue) { _, new in
                    if new.count > 1000 { text.wrappedValue = String(new.prefix(1000)) }
                }
            if let onCancel {
                Button(action: onCancel) {
                    LucideIcon(.x, .sm)
                        .foregroundStyle(Color.vText4)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            CircleIconButton(
                icon: .send,
                variant: hasText ? .send : .secondary,
                busy: viewModel.isPostingComment && focused
            ) {
                guard hasText else { return }
                onSend()
            }
            .opacity(hasText ? 1 : 0.6)
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(height: 40)
        .background(focused ? Color.vFieldFocus : Color.vField, in: Capsule())
        .animation(.easeOut(duration: 0.15), value: hasText)
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
                ExpandableText(comment.content, font: .appSubheadline, textColor: .vText2)
                    .padding(.top, 2)

                commentActions(comment, isReply: isReply)

                if !isReply, viewModel.replyingTo?.commentId == comment.commentId {
                    VStack(alignment: .leading, spacing: 10) {
                        composerCapsule(
                            text: $viewModel.replyText,
                            placeholder: "Reply to @\(comment.user.username)",
                            field: .reply,
                            onCancel: { viewModel.toggleReply(to: comment) }
                        ) { Task { await viewModel.postReply() } }
                        if let error = viewModel.commentError { ErrorBanner(error) }
                    }
                    .padding(.top, 12)
                    .transition(.opacity)
                }

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
                viewModel.toggleReply(to: comment)
                if viewModel.replyingTo != nil { focusedField = .reply }
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
                .font(.appSubheadline)
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

                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button("Cancel") { dismiss() }
                        .font(.appSubheadlineMedium)
                        .foregroundStyle(Color.vText2)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .buttonStyle(.plain)
                        .disabled(isSending)
                    Button { Task { error = await onSend(message) } } label: {
                        HStack(spacing: 8) {
                            if isSending {
                                ProgressView().tint(Color.vOnColor).controlSize(.small)
                            } else {
                                LucideIcon(.messageSquare, .sm)
                            }
                            Text("Send").font(.appSubheadlineSemibold)
                        }
                        .foregroundStyle(Color.vOnColor)
                        .padding(.horizontal, 20)
                        .frame(height: 36)
                        .background(Color.vAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .opacity(canSend ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            Spacer(minLength: 0)
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
                if canDelete {
                    OptionSheetRow(icon: .trash2, title: "Delete comment", tint: .vError) {
                        dismiss()
                        onDelete()
                    }
                } else {
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
                    Text(closing ? "Couldn't close the listing. Try again." : "Couldn't reopen the listing. Try again.")
                        .font(.appFootnoteMedium)
                        .foregroundStyle(Color.vError)
                        .transition(.opacity)
                }

                HStack(spacing: 10) {
                    SecondaryButton("Cancel", size: .inline) { dismiss() }
                        .disabled(busy)
                    actionButton
                }
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

    /// Close = danger-soft red; Reopen = the ink primary.
    private var actionButton: some View {
        Button {
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
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().tint(closing ? Color.vError : Color.vOnInverse).controlSize(.small)
                } else {
                    LucideIcon(closing ? .lock : .lockOpen, .sm)
                }
                Text(closing ? "Close listing" : "Reopen listing").font(.appSubheadlineSemibold)
            }
            .foregroundStyle(closing ? Color.vError : Color.vOnInverse)
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(closing ? Color.vDangerSoft : Color.vInverse, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
