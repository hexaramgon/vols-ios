//
//  ConversationScreen.swift
//  Volspire
//
//  A single chat thread — header (avatar, name, context subtitle, request
//  actions, "…"), the listing strip for listing threads, grouped bubbles
//  (outgoing vSurface2, incoming vSurface) with time dividers, and the
//  capsule composer with photo/file attachments.
//

import AVFoundation
import DesignSystem
import Kingfisher
import MediaLibrary
import PhotosUI
import Services
import SwiftUI
import UniformTypeIdentifiers

/// Stable Kingfisher cache key for a signed attachment URL: drops the volatile
/// token/expiry query so a re-signed URL (a new token is minted on every load and
/// poll) reuses the cached image instead of re-downloading it every time.
func attachmentCacheKey(_ url: URL) -> String {
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    comps?.query = nil
    return comps?.string ?? url.absoluteString
}

struct ConversationScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(Router.self) private var router
    @Environment(ConversationState.self) private var conversationState
    @Environment(InboxStore.self) private var inboxStore
    @Environment(SocialStore.self) private var socialStore

    let conversation: ActiveConversation

    @State private var viewModel: ConversationViewModel?
    /// Report / Block the other participant (App Store 1.2 UGC safety).
    @State private var showReportUser = false
    @State private var showBlockConfirm = false
    @State private var showUserOptions = false
    @State private var pendingReport = false
    @State private var pendingBlock = false
    @State private var pendingRemoveCollab = false
    @State private var showRemoveCollabConfirm = false
    /// LIVE collaborator state — the thread's request card keeps its historical
    /// "accepted" after a removal, so the menu option can't be gated on it.
    @State private var isActiveCollaborator = false
    /// The other participant's profile (roles, location, collaborator status)
    /// for the header subtitle — `get_user_profile`, cached.
    @State private var otherProfile: ApiUserProfile?

    var body: some View {
        VStack(spacing: 0) {
            header

            if let viewModel {
                // Context strip for threads born from a Collab Board listing —
                // shows which listing this conversation is about, tap to open.
                if let listing = viewModel.linkedListing {
                    listingBanner(listing)
                }
                ChatThread(viewModel: viewModel, otherUsername: conversation.username)
            } else {
                Color.clear
            }
        }
        .animation(.smooth(duration: 0.3), value: viewModel?.linkedListing?.listingId)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vBase.ignoresSafeArea())
        .task {
            let vm = viewModel ?? ConversationViewModel(
                convoId: conversation.convoId,
                currentUserId: dependencies.authManager.currentUserId
            )
            vm.inbox = inboxStore
            vm.social = socialStore
            vm.otherUserId = conversation.otherUserId
            // Restore a draft left behind last time this thread was open.
            if vm.draft.isEmpty {
                vm.draft = inboxStore.draft(for: conversation.convoId)
            }
            viewModel = vm
            if otherProfile == nil, let otherId = conversation.otherUserId {
                Task { otherProfile = try? await dependencies.supabaseService.getUserProfile(userId: otherId) }
            }
            // Opening reads the thread — zero the list row immediately.
            inboxStore.conversationOpened(conversation.convoId)
            // Fetch runs concurrently with the push; the thread renders only
            // once the transition has settled (see load(settleDelay:)).
            await vm.load(settleDelay: .seconds(0.45))
            // Before polling (which never returns): resolve the LIVE collab
            // state for the Remove Collaborator option.
            if vm.hasAcceptedCollabRequest, let otherId = conversation.otherUserId {
                isActiveCollaborator =
                    (try? await dependencies.supabaseService.getCollabStatus(otherUserId: otherId)) == "accepted"
            }
            await vm.startPolling()
        }
        // Custom header — hide the system bar; re-enable the native edge-swipe
        // pop (a hidden bar disables it) so back behaves like every other screen.
        .toolbar(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .onAppear { conversationState.activeConversation = conversation }
        .onDisappear {
            // Keep whatever was typed — restored on the next open of this thread.
            if let viewModel {
                inboxStore.setDraft(viewModel.draft, for: conversation.convoId)
            }
            if conversationState.activeConversation == conversation {
                conversationState.activeConversation = nil
            }
        }
        .sheet(isPresented: $showUserOptions, onDismiss: {
            if pendingReport { pendingReport = false; showReportUser = true }
            if pendingBlock { pendingBlock = false; showBlockConfirm = true }
            if pendingRemoveCollab { pendingRemoveCollab = false; showRemoveCollabConfirm = true }
        }) {
            UserOptionsSheet(
                username: conversation.username,
                onRemoveCollaborator: (isActiveCollaborator && conversation.otherUserId != nil)
                    ? { pendingRemoveCollab = true; showUserOptions = false }
                    : nil,
                onReport: { pendingReport = true; showUserOptions = false },
                onBlock: { pendingBlock = true; showUserOptions = false }
            )
        }
        .destructiveConfirm(
            "Remove @\(conversation.username) as a collaborator?",
            isPresented: $showRemoveCollabConfirm,
            actionLabel: "Remove",
            message: "You'll no longer be collaborators, and this conversation moves to your inbox's Archived section. You can send a new collab request anytime."
        ) {
            removeCollaborator()
        }
        .sheet(isPresented: $showReportUser) {
            if let otherId = conversation.otherUserId {
                ReportSheet(targetType: .user, targetId: otherId, subject: "@\(conversation.username)")
            }
        }
        .blockUserDialog(username: conversation.username, isPresented: $showBlockConfirm) {
            blockOtherUser()
        }
    }

    // MARK: Listing context banner


    /// The listing strip — which Collab Board listing this thread came from:
    /// an accent tile with the category glyph, the title, "Category · N
    /// responses" (or "· Closed"), and a chevron. The whole band opens it.
    private func listingBanner(_ listing: ApiListing) -> some View {
        Button { router.navigateToCollabListing(listing) } label: {
            HStack(spacing: 12) {
                LucideIcon(listing.categoryIcon, .lg)
                    .foregroundStyle(Color.vOnColor)
                    .frame(width: 40, height: 40)
                    .background(Color.vAccent, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(listing.title)
                        .font(.appSubheadlineSemibold)
                        .foregroundStyle(Color.vText)
                        .lineLimit(1)
                    Text(listingMeta(listing))
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText3)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(ListingStripButtonStyle())
        .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
        .transition(.opacity)
    }

    private func listingMeta(_ listing: ApiListing) -> String {
        if (listing.status ?? "open") != "open" { return "\(listing.categoryLabel) · Closed" }
        let n = listing.responseCount ?? 0
        return "\(listing.categoryLabel) · \(n) response\(n == 1 ? "" : "s")"
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                // Drop the keyboard first so the input bar doesn't strand mid-screen
                // during the pop animation (matches the swipe-back behaviour).
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                dismiss()
            } label: {
                // Same Lucide glyph + token as the shared BackButton, so every
                // screen's chevron reads identically (the old SF symbol rendered
                // ~25% larger at the same point size).
                LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
                    .foregroundStyle(Color.vText)
                    .frame(width: 36, height: 40)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)

            // Avatar + name open the sender's profile (slides in on the nav stack).
            Button {
                guard let otherUserId = conversation.otherUserId else { return }
                router.navigateToProfile(userId: otherUserId)
            } label: {
                HStack(spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.username)
                            .font(.appSubheadlineSemibold)
                            .foregroundStyle(Color.vText)
                            .lineLimit(1)
                        headerSubtitle
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
            // (A request I sent needs no chip — the subtitle already says so.)
            if let request = pendingCollabRequest {
                collabResponseButtons(request)
            }
            if conversation.otherUserId != nil {
                conversationMenu
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, ViewConst.screenPaddings)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background {
            Color.vBase
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.vDivider).frame(height: 1)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    /// The header's context line: a pending request's state, otherwise
    /// "⑂ Collaborator · Producer, Vocalist · Austin, TX" from the profile.
    @ViewBuilder
    private var headerSubtitle: some View {
        if pendingCollabRequest != nil {
            subtitleText("Wants to collaborate")
        } else if awaitingCollabRequest != nil {
            subtitleText("Collab request sent")
        } else if let profile = otherProfile {
            let tags = (profile.tags ?? []).prefix(2).joined(separator: ", ")
            let location = profile.location ?? ""
            let rest = [tags, location].filter { !$0.isEmpty }.joined(separator: " · ")
            let isCollaborator = socialStore.collabStatus(
                conversation.otherUserId ?? "", fallback: profile.collaboratorStatus
            ) == "accepted"
            if isCollaborator || !rest.isEmpty {
                HStack(spacing: 4) {
                    if isCollaborator {
                        LucideIcon(.gitMerge, .xs)
                        Text("Collaborator")
                        if !rest.isEmpty { Text("·").foregroundStyle(Color.vText3) }
                    }
                    if !rest.isEmpty {
                        Text(rest).foregroundStyle(Color.vText3)
                    }
                }
                .font(.appCaption)
                .foregroundStyle(Color.vText2)
                .lineLimit(1)
            }
        }
    }

    private func subtitleText(_ text: String) -> some View {
        Text(text)
            .font(.appCaption)
            .foregroundStyle(Color.vText3)
            .lineLimit(1)
    }

    /// Trailing "…" — report or block the other participant.
    /// The plain, larger header "…", matching the folder / profile / listing headers.
    private var conversationMenu: some View {
        HeaderIconButton(icon: .ellipsis, size: ViewConst.heroOverlayIconSize) { showUserOptions = true }
            .accessibilityLabel("Conversation options")
    }

    /// Blocks the other participant, then pops back to the message list.
    private func blockOtherUser() {
        guard let otherId = conversation.otherUserId else { return }
        Task {
            try? await dependencies.supabaseService.blockUser(otherId)
            dismiss()
        }
    }

    /// Ends the collaboration — the backend archives this DM for us, so pop
    /// back to the inbox. The archived flag is server-computed, so refetch the
    /// list (one call) to regroup the thread under Archived, and reset the
    /// shared collab overlay for any mounted profile.
    private func removeCollaborator() {
        guard let otherId = conversation.otherUserId else { return }
        Task {
            try? await dependencies.supabaseService.removeCollaborator(userId: otherId)
            isActiveCollaborator = false
            socialStore.setCollabStatus("none", userId: otherId)
            await inboxStore.refreshConversations()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            dismiss()
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

    private func collabResponseButtons(_ request: ChatMessage) -> some View {
        HStack(spacing: 8) {
            Button { Task { await viewModel?.respondToRequest(request, accept: false) } } label: {
                LucideIcon(.x, .md)
                    .foregroundStyle(Color.vControlLabel)
                    .frame(width: 32, height: 32)
                    .background(Color.vControl, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Decline")

            Button { Task { await viewModel?.respondToRequest(request, accept: true) } } label: {
                LucideIcon(.check, .md)
                    .foregroundStyle(Color.vOnInverse)
                    .frame(width: 32, height: 32)
                    .background(Color.vInverse, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Accept")
        }
        .transition(.scale.combined(with: .opacity))
    }

    private var avatar: some View {
        AvatarView(urlString: conversation.avatarURL, name: conversation.username, size: 40)
    }
}

/// The listing strip's band: `vCardSolid`, highlighting to `vSurface` on press.
private struct ListingStripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.vSurface : Color.vCardSolid)
    }
}
