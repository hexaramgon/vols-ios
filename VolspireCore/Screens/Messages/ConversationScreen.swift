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
    @Environment(\.scenePhase) private var scenePhase
    /// False while this thread's tab isn't the selected one (tabs stay mounted).
    @Environment(\.isActiveRootTab) private var isActiveRootTab
    /// Between onAppear and onDisappear (a page pushed over it disappears it).
    @State private var isOnScreen = false

    let conversation: ActiveConversation

    @State private var viewModel: ConversationViewModel?
    /// Report / Block the other participant (App Store 1.2 UGC safety).
    @State private var showReportUser = false
    @State private var showUserOptions = false
    @State private var pendingReport = false
    /// LIVE collaborator state — the thread's request card keeps its historical
    /// "accepted" after a removal, so the menu option can't be gated on it.
    @State private var isActiveCollaborator = false
    /// The other participant's profile (roles, location, collaborator status)
    /// for the header subtitle — `get_user_profile`, cached.
    @State private var otherProfile: ApiUserProfile?

    /// On screen AND its tab is the active one — the thread reads incoming
    /// messages, and pushes/banners for it are suppressed. Off either way
    /// (pushed over, or another tab), it's an ordinary unread thread.
    private func syncVisibility() {
        let visible = isOnScreen && isActiveRootTab
        viewModel?.isVisible = visible
        let push = PushNotificationManager.shared
        if visible {
            push.visibleConversationId = conversation.convoId
        } else if push.visibleConversationId == conversation.convoId {
            push.visibleConversationId = nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let viewModel {
                // Context strip for threads born from a Collab Board listing —
                // shows which listing this conversation is about, tap to open.
                if let listing = viewModel.linkedListing {
                    listingBanner(listing)
                }
                // An incoming collab request — answered from a strip of its
                // own under the header (same band as the listing strip).
                if let request = pendingCollabRequest {
                    collabRequestBanner(request)
                }
                ChatThread(viewModel: viewModel, otherUsername: conversation.username)
            } else {
                Color.clear
            }
        }
        .animation(.smooth(duration: 0.3), value: viewModel?.linkedListing?.listingId)
        .animation(.smooth(duration: 0.3), value: pendingCollabRequest?.id)
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
            syncVisibility()
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
        // Realtime: a new message in this thread merges at once (the poll in
        // .task is only the fallback now).
        .onChange(of: inboxStore.liveMessageCount(for: conversation.convoId)) { _, _ in
            Task { await viewModel?.mergeLatestNow() }
        }
        // The realtime socket is closed while backgrounded — catch up on return
        // instead of waiting for the fallback poll.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await viewModel?.mergeLatestNow() } }
        }
        .onChange(of: isActiveRootTab) { _, _ in syncVisibility() }
        .onAppear {
            isOnScreen = true
            syncVisibility()
            conversationState.activeConversation = conversation
        }
        .onDisappear {
            isOnScreen = false
            syncVisibility()
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
        }) {
            UserOptionsSheet(
                username: conversation.username,
                onRemoveCollaborator: (isActiveCollaborator && conversation.otherUserId != nil)
                    ? {
                        // The DM moves to Archived — leave it.
                        if let otherId = conversation.otherUserId {
                            dependencies.contentActions.removeCollaborator(userId: otherId, username: conversation.username)
                        }
                        isActiveCollaborator = false
                        leaveThread()
                    }
                    : nil,
                onWithdrawRequest: awaitingCollabRequest.map { request in
                    {
                        Task {
                            if await viewModel?.withdrawRequest(request) == true {
                                Haptics.success()
                                ToastCenter.shared.show("Collab request withdrawn")
                            } else {
                                ToastCenter.shared.show("Couldn't withdraw the request. Try again.", style: .error)
                            }
                        }
                    }
                },
                onReport: { pendingReport = true; showUserOptions = false },
                onBlock: {
                    if let otherId = conversation.otherUserId {
                        dependencies.contentActions.block(userId: otherId, username: conversation.username)
                    }
                    leaveThread()
                }
            )
        }
        .sheet(isPresented: $showReportUser) {
            if let otherId = conversation.otherUserId {
                ReportSheet(targetType: .user, targetId: otherId, subject: "@\(conversation.username)")
            }
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
                    .minimumHitArea(for: 36)
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

    /// Leave the thread after a confirmed block / collaborator removal.
    private func leaveThread() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        dismiss()
    }

    /// The one pending collab request the other user sent me (rate-limited to one
    /// per week, so at most one), drives the request strip's accept/decline.
    /// Also closed once the shared SocialStore says the pair's status moved on
    /// (answered from Notifications or a profile while this thread was loaded).
    private var pendingCollabRequest: ChatMessage? {
        guard let request = viewModel?.messages.first(where: { $0.isCollabRequest && !$0.isFromMe && $0.isPendingRequest })
        else { return nil }
        // Answered from the notification row since it was sent (the thread's
        // own copy catches up on the next poll).
        if let otherId = conversation.otherUserId,
           socialStore.collabAnswer(from: otherId, after: request.createdAt) != nil {
            return nil
        }
        return request
    }

    /// The mirror case — a request I sent that the other party hasn't answered.
    private var awaitingCollabRequest: ChatMessage? {
        viewModel?.messages.first { $0.isCollabRequest && $0.isFromMe && $0.isPendingRequest }
    }

    /// The incoming-request strip — the listing strip's band holding a
    /// handshake glyph + one line of copy over equal-width Decline / Accept,
    /// the notifications row's text buttons.
    private func collabRequestBanner(_ request: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                LucideIcon(.handshake, .md)
                    .foregroundStyle(Color.vText2)
                let name = Text("@\(conversation.username)").font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                let rest = Text(" wants to collaborate").font(.appSubheadline).foregroundStyle(Color.vText2)
                Text("\(name)\(rest)")
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                SecondaryButton("Decline", icon: .x, size: .inline) {
                    Task { await viewModel?.respondToRequest(request, accept: false) }
                }
                PrimaryButton("Accept", icon: .check, size: .inline) {
                    Task { await viewModel?.respondToRequest(request, accept: true) }
                }
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 12)
        .background(Color.vCardSolid)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
        .transition(.opacity)
    }

    private var avatar: some View {
        AvatarView(urlString: conversation.avatarURL, name: conversation.username, size: 40)
    }
}

/// The listing strip's band: `vCardSolid`, highlighting to `vSurface` on press.
/// The full-width context strip's fill + press state (the listing strip here,
/// the Analytics "Followers & collaborators" strip).
struct ListingStripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.vSurface : Color.vCardSolid)
    }
}
