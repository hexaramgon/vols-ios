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
func attachmentCacheKey(_ url: URL) -> String {
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    comps?.query = nil
    return comps?.string ?? url.absoluteString
}

/// Accent fill for the current user's bubbles + send button — the shared
/// send-accent gradient, so chat and player comments match.
let accentGradient = LinearGradient.sendAccent

struct ConversationScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @Environment(Router.self) private var router
    @Environment(ConversationState.self) private var conversationState

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
            } else if conversation.otherUserId != nil {
                conversationMenu
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

    /// Trailing "…" — report or block the other participant.
    private var conversationMenu: some View {
        Button { showUserOptions = true } label: {
            LucideIcon(.ellipsis, size: ViewConst.headerIconSize)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
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
    /// back to the inbox (which reloads on return and regroups the thread
    /// under Archived).
    private func removeCollaborator() {
        guard let otherId = conversation.otherUserId else { return }
        Task {
            try? await dependencies.supabaseService.removeCollaborator(userId: otherId)
            isActiveCollaborator = false
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
        AvatarView(urlString: conversation.avatarURL, name: conversation.username, size: 40)
    }
}

