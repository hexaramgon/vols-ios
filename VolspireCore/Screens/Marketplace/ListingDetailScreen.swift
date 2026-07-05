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

struct ListingDetailScreen: View {
    @Environment(Router.self) private var router
    @Environment(Dependencies.self) private var dependencies
    @Environment(ConversationState.self) private var conversationState
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: ListingDetailViewModel
    @State private var showRespond = false
    @State private var showDeleteConfirm = false
    @State private var showAdminOptions = false
    @State private var pendingAdminDelete = false
    @State private var pendingEdit = false
    @State private var showEdit = false
    @FocusState private var commentFocused: Bool

    init(listing: ApiListing) {
        _viewModel = State(wrappedValue: ListingDetailViewModel(listing: listing))
    }

    private var listing: ApiListing { viewModel.listing }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerBlock
                // Respond + Save are for visitors only — authors manage via the "…" menu.
                if !viewModel.isAuthor { actionRow }
                if !listing.attachments.isEmpty {
                    section("Audio · \(listing.attachments.count)") { attachmentsList }
                }
                if viewModel.isAuthor { responsesSection }
                commentsSection
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 6)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .appNavBar(
            title: "\(categoryLabel) Listing",
            subtitle: "@\(listing.author.username)",
            collapsing: true
        ) { dismiss() }
        .toolbar {
            if viewModel.isAuthor {
                ToolbarItem(placement: .topBarTrailing) { adminButton }
            }
        }
        .task { await viewModel.load() }
        .onDisappear { viewModel.stopClip() }
        .sheet(isPresented: $showRespond) { respondSheet }
        .sheet(isPresented: $showAdminOptions, onDismiss: {
            if pendingAdminDelete { pendingAdminDelete = false; showDeleteConfirm = true }
            if pendingEdit { pendingEdit = false; showEdit = true }
        }) { adminOptionsSheet }
        .fullScreenCover(isPresented: $showEdit, onDismiss: { Task { await viewModel.load() } }) {
            CreateListingScreen(viewModel: CreateListingViewModel(
                editing: listing,
                supabaseService: dependencies.supabaseService,
                authManager: dependencies.authManager
            ))
        }
        .confirmationDialog("Delete this listing?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { if await viewModel.deleteListing() { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the listing and its responses.")
        }
    }

    /// Author-only "…" — opens a slide-up sheet to open/close or delete.
    private var adminButton: some View {
        Button { showAdminOptions = true } label: {
            LucideIcon(.ellipsis, .xl)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Author options as a slide-up sheet (matches the workspace file sheet).
    private var adminOptionsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 13) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(0.08))
                    LucideIcon(categoryIcon, .lg).foregroundStyle(.white)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.title).font(.appTitle3Bold).foregroundStyle(.white).lineLimit(1)
                    Text(viewModel.isClosed ? "Closed" : "Open").font(.appFootnote).foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 2)

            VStack(spacing: 2) {
                adminRow(systemImage: "pencil", title: "Edit listing") {
                    pendingEdit = true
                    showAdminOptions = false
                }
                adminRow(systemImage: viewModel.isClosed ? "lock.open" : "lock",
                         title: viewModel.isClosed ? "Reopen listing" : "Close listing") {
                    showAdminOptions = false
                    Task { await viewModel.toggleStatus() }
                }
                adminRow(systemImage: "trash", title: "Delete listing",
                         tint: Color(red: 1, green: 0.37, blue: 0.37)) {
                    pendingAdminDelete = true
                    showAdminOptions = false
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

    private func adminRow(systemImage: String, title: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 18)).foregroundStyle(tint)
                    .frame(width: 26, alignment: .center)
                Text(title).font(.appBodyLargeMedium).foregroundStyle(tint)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).padding(.vertical, 15)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header + actions

private extension ListingDetailScreen {
    var headerBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Author avatar next to the title + @username · time.
            HStack(alignment: .top, spacing: 12) {
                Button { router.navigateToProfile(userId: listing.author.userId) } label: {
                    avatar(listing.author, size: 44)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    Text(listing.title)
                        .font(.appTitle2).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Text("@\(listing.author.username)").font(.appFootnoteMedium).foregroundStyle(Color.vText2)
                        Text("·").foregroundStyle(Color.vText3)
                        Text(timeAgo(listing.createdAt)).font(.appFootnote).foregroundStyle(Color.vText3)
                    }
                }
            }

            // Description + tags sit directly under the title (no section labels).
            if let desc = listing.description, !desc.isEmpty {
                bodyText(desc)
            }
            if let tags = listing.tags, !tags.isEmpty {
                chipRow(tags.map { "#\($0)" })
            }

            HStack(spacing: 14) {
                metric(.users, "\(listing.responseCount ?? 0) responses")
                metric(.messageCircle, "\(viewModel.comments.count)")
                metric(.bookmark, "\(viewModel.saveCount)")
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var actionRow: some View {
        HStack(spacing: 10) {
            // Standard app primary button (white, rounded-14, h44).
            Button {
                if let convoId = viewModel.existingConvoId { openConversation(convoId: convoId, with: listing.author) }
                else { showRespond = true }
            } label: {
                Text(respondLabel)
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(!canRespond)
            .opacity(canRespond ? 1 : 0.3)

            // Save is a pure icon — no background, just the bookmark glyph.
            Button { Task { await viewModel.toggleSave() } } label: {
                LucideIcon(viewModel.isSaved ? .bookmarkFill : .bookmark, .lg)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
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

    func metric(_ icon: LucideIcon.Name, _ text: String) -> some View {
        HStack(spacing: 5) {
            LucideIcon(icon, .xs)
            Text(text).font(.appFootnote)
        }
        .foregroundStyle(Color.vText3)
    }
}

// MARK: - Audio

private extension ListingDetailScreen {
    var attachmentsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(listing.attachments.enumerated()), id: \.offset) { idx, clip in
                let playing = viewModel.playingClip == clip.fileUrl && clip.fileUrl != nil
                Button { viewModel.toggleClip(clip) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(playing ? Color.brand : Color.white.opacity(0.08))
                            LucideIcon(playing ? .pause : .playFill, .sm).foregroundStyle(.white)
                        }
                        .frame(width: 36, height: 36)
                        Text(clip.title ?? "Clip \(idx + 1)")
                            .font(.appSubheadlineMedium).foregroundStyle(.white).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 9)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(clip.fileUrl == nil)
                if idx < listing.attachments.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                }
            }
        }
    }
}

// MARK: - Author + Comments

private extension ListingDetailScreen {
    /// Author-only: who's responded, tap to open that chat.
    var responsesSection: some View {
        section("Responses · \(viewModel.responses.count)") {
            if !viewModel.responsesLoaded {
                responsesSkeleton
            } else if viewModel.responses.isEmpty {
                Text("No one has responded yet.")
                    .font(.appFootnote).foregroundStyle(Color.vText3)
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

    /// Placeholder rows shown while comments load.
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

    var commentsSection: some View {
        section("Comments · \(viewModel.comments.count)") {
            VStack(alignment: .leading, spacing: 16) {
                commentComposer
                if !viewModel.commentsLoaded {
                    commentsSkeleton
                } else {
                    ForEach(viewModel.comments) { commentRow($0) }
                }
            }
        }
    }

    var commentComposer: some View {
        HStack(spacing: 10) {
            TextField("", text: $viewModel.commentText, prompt: Text("Add a comment…").foregroundColor(Color.vText3), axis: .vertical)
                .font(.appSubheadline)
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(1 ... 4)
                .focused($commentFocused)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.vBorder, lineWidth: 1))

            Button {
                commentFocused = false
                Task { await viewModel.postComment() }
            } label: {
                Group {
                    if viewModel.isPostingComment {
                        ProgressView().tint(.black).controlSize(.small)
                    } else {
                        LucideIcon(.arrowUpRight, .lg).foregroundStyle(.black)
                    }
                }
                .frame(width: 38, height: 38)
                .background(canPostComment ? Color.white : Color.white.opacity(0.3), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canPostComment)
        }
    }

    var canPostComment: Bool {
        !viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !viewModel.isPostingComment
    }

    func commentRow(_ comment: ApiListingComment) -> some View {
        HStack(alignment: .top, spacing: 11) {
            avatar(comment.user, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text("@\(comment.user.username)").font(.appFootnoteSemibold).foregroundStyle(.white)
                    Text(timeAgo(comment.createdAt)).font(.appCaption2).foregroundStyle(Color.vText3)
                    Spacer(minLength: 0)
                    if viewModel.isOwnComment(comment) {
                        Menu {
                            Button(role: .destructive) {
                                Task { await viewModel.deleteComment(comment) }
                            } label: { Label("Delete", systemImage: "trash") }
                        } label: {
                            LucideIcon(.ellipsis, .lg)
                                .foregroundStyle(Color.vText2)
                                .frame(width: 32, height: 28).contentShape(.rect)
                        }
                    }
                }
                Text(comment.content)
                    .font(.appSubheadline).foregroundStyle(Color.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func avatar(_ author: ApiListingAuthor, size: CGFloat) -> some View {
        Group {
            if let s = author.profileImageUrl, let url = URL(string: s) {
                KFImage(url).downsampled(to: size).resizable().scaledToFill()
            } else {
                Text(String(author.username.first ?? "?").uppercased())
                    .font(.geist(size * 0.36, weight: .bold)).foregroundStyle(Color.vText2)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.08))
        .clipShape(Circle())
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
        VStack(alignment: .leading, spacing: 18) {
            // Header: avatar + "Respond to @user" over the listing, with a close chip.
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text("Respond to @\(author.username)")
                        .font(.appTitle3Bold).foregroundStyle(.white).lineLimit(1)
                    Text(listingTitle)
                        .font(.appFootnote).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    LucideIcon(.x, .md)
                        .foregroundStyle(Color.vText2)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            TextField("", text: $message, prompt: Text("Hey @\(author.username), I'd love to work on this…").foregroundColor(Color.vText3), axis: .vertical)
                .font(.appCalloutRegular)
                .foregroundStyle(.white)
                .tint(.white)
                .lineLimit(4 ... 8)
                .focused($focused)
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(focused ? 0.18 : 0.08), lineWidth: 1)
                )

            if let error {
                ErrorBanner(error)
            }

            Button {
                Task { error = await onSend(message) }
            } label: {
                Group {
                    if isSending { ProgressView().tint(.black) }
                    else { Text("Send message").font(.appHeadline).foregroundStyle(.black) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(canSend ? Color.white : Color.white.opacity(0.25), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .animation(.easeOut(duration: 0.15), value: canSend)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
        .sheetBackground()
        .onAppear { focused = true }
    }

    private var avatar: some View {
        Group {
            if let s = author.profileImageUrl, let url = URL(string: s) {
                KFImage(url).downsampled(to: 48).resizable().scaledToFill()
            } else {
                Text(String(author.username.first ?? "?").uppercased())
                    .font(.appTitle3Bold).foregroundStyle(Color.vText2)
            }
        }
        .frame(width: 48, height: 48)
        .background(Color.white.opacity(0.08))
        .clipShape(Circle())
    }

    var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
}

// MARK: - Reusable pieces

private extension ListingDetailScreen {
    func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.appCaptionBold).tracking(0.8)
                .foregroundStyle(Color.vText3)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.appBody).foregroundStyle(Color.white.opacity(0.92))
            .lineSpacing(2)
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

    var categoryLabel: String {
        listingCategories.first { $0.id == listing.category }?.label ?? listing.category.capitalized
    }

    var categoryIcon: LucideIcon.Name {
        listingCategories.first { $0.id == listing.category }?.icon ?? .music
    }

    func timeAgo(_ iso: String?) -> String {
        guard let iso, let date = isoDate(iso) else { return "" }
        let s = Date().timeIntervalSince(date)
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(s / 60))m ago"
        case ..<86400: return "\(Int(s / 3600))h ago"
        case ..<604800: return "\(Int(s / 86400))d ago"
        default: return "\(Int(s / 604800))w ago"
        }
    }

    func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
