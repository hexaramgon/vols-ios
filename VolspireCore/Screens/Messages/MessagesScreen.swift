//
//  MessagesScreen.swift
//  Volspire
//
//  Conversation inbox — the Messages tab. The shared tab-root header
//  ("Messages" + the notifications bell) with an always-visible search field
//  under it, then flat category folders, threads and the Archived section.
//  Category folders push a `MessageCategoryScreen` through the Router.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct MessagesScreen: View {
    @Environment(ConversationState.self) private var conversationState
    @Environment(Router.self) private var router
    @Environment(PlayerController.self) private var playerController
    @Environment(InboxStore.self) private var inboxStore
    @Environment(\.dismiss) private var dismiss
    @Environment(Dependencies.self) private var dependencies
    @State private var viewModel = MessagesScreenViewModel()
    @FocusState private var searchFocused: Bool
    /// The search field is open (from the header's search icon — Workspace's
    /// folder-search pattern).
    @State private var showSearch = false
    @State private var archivedOpen = false
    /// This page instance's list entrance (see `staggeredAppear`).
    @State private var entranceKey = "messages-\(UUID().uuidString)"

    private var bottomInset: CGFloat { playerController.contentBottomInset }


    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if showSearch {
                    MessagesSearchField(text: $viewModel.searchText, focus: $searchFocused) {
                        searchFocused = false
                        withAnimation(.smooth(duration: 0.22)) {
                            showSearch = false
                            viewModel.searchText = ""
                        }
                    }
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.bottom, 12)
                    .transition(.opacity)
                }
                content
                    .animation(.easeOut(duration: 0.25), value: inboxStore.loadState)
                    .animation(.easeOut(duration: 0.25), value: inboxStore.conversations.isEmpty)
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await inboxStore.refreshConversations() }
        // Pushed from Explore's header — back chevron + title, search far right.
        .appNavBar(title: "Messages", onBack: { dismiss() }) {
            if !inboxStore.conversations.isEmpty {
                HeaderIconButton(icon: .search) {
                    withAnimation(.smooth(duration: 0.22)) { showSearch = true }
                    searchFocused = true
                }
                .accessibilityLabel("Search messages")
            }
        }
        .task {
            viewModel.inbox = inboxStore
            await inboxStore.loadOrRevalidateConversations()
        }
        // Foregrounding + pushes arriving in-app refresh the list in
        // InboxStore itself (appBecameActive / .pushReceived).
    }

    // MARK: - Content

    private var isLoadError: Bool {
        if case .error = inboxStore.loadState { return true }
        return false
    }

    /// True until the first load resolves — covers `.idle` too so the skeleton
    /// shows from the very first frame instead of flashing the empty state.
    private var isInitialLoading: Bool {
        (inboxStore.loadState == .idle || inboxStore.loadState == .loading)
            && inboxStore.conversations.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if isInitialLoading {
            MessagesSkeleton()
        } else if isLoadError && inboxStore.conversations.isEmpty {
            LoadErrorView { Task { await inboxStore.refreshConversations() } }
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        } else if inboxStore.conversations.isEmpty {
            InboxEmptyState()
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                if viewModel.filtered.isEmpty {
                    // Quieter than the full empty state — this flashes while typing.
                    Text("No matches")
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    mainInbox
                }
            }
            .padding(.bottom, bottomInset)
        }
    }

    // MARK: - Main inbox (category folders + DMs) — web-style classification

    @ViewBuilder
    private var mainInbox: some View {
        categoryRow(.bell, .requests, viewModel.pendingRequests)
        // Orders / Inquiries only render when such threads exist (legacy
        // marketplace conversations) — never hide someone's messages.
        categoryRow(.shoppingCart, .orders, viewModel.orders)
        categoryRow(.briefcase, .inquiries, viewModel.inquiries)
        categoryRow(.megaphone, .listings, viewModel.listings)
        ForEach(Array(viewModel.directConvos.enumerated()), id: \.element.id) { index, item in
            ConversationRow(item: item)
                .staggeredAppear(index, in: entranceKey)
        }
        archivedSection
        InboxPageFooter()
    }

    /// A tappable "folder" row — pushes a `MessageCategoryScreen` via the Router,
    /// the same way Library/Marketplace push their detail pages.
    @ViewBuilder
    private func categoryRow(_ icon: LucideIcon.Name, _ bucket: MessageBucket, _ items: [ConversationItem]) -> some View {
        if !items.isEmpty {
            let unread = items.reduce(0) { $0 + $1.unreadCount }
            let label = bucket.rowLabel
            Button {
                searchFocused = false
                // Push the bucket KEY — the folder derives live rows from the
                // store, so acting inside it (or a poll) updates it in place.
                router.navigateToMessageCategory(title: bucket.folderTitle, bucket: bucket)
            } label: {
                HStack(spacing: 12) {
                    LucideIcon(icon, .lg)
                        .foregroundStyle(Color.vText2)
                        .frame(width: 48, height: 48)
                        .background(Color.vSurface, in: Circle())
                        .overlay(alignment: .topTrailing) {
                            if unread > 0 {
                                Text(unread > 9 ? "9+" : "\(unread)")
                                    .font(.appMicroBold)
                                    .foregroundStyle(Color.vOnColor)
                                    .monospacedDigit()
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 18, minHeight: 18)
                                    // The app's unread red (the unread dots'
                                    // colour), white count.
                                    .background(Color.vUnread, in: Capsule())
                                    .offset(x: 4, y: -4)
                            }
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(label)
                            .font(unread > 0 ? .appCalloutSemibold : .appCallout)
                            .foregroundStyle(unread > 0 ? Color.vText : Color.vTextRow)
                            .lineLimit(1)
                        Text(categorySubtitle(bucket, items))
                            .font(.appSubheadline)
                            .foregroundStyle(unread > 0 ? Color.vText : Color.vText3)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText3)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.vertical, 12)
                .contentShape(.rect)
            }
            .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
        }
    }

    private func categorySubtitle(_ bucket: MessageBucket, _ items: [ConversationItem]) -> String {
        let n = items.count
        if bucket == .requests {
            if let first = items.first {
                // Direction-aware: requests I sent read "Sent to @…", received "From @…".
                let prefix = first.lastMessageFromMe ? "Sent to" : "From"
                return "\(prefix) @\(first.username)" + (n > 1 ? " · +\(n - 1) more" : "")
            }
            return "\(n) request\(n == 1 ? "" : "s")"
        }
        let noun = n == 1 ? "thread" : "threads"
        return "\(n) \(noun) · \(MessageTime.ago(items.first?.lastMessageAt))"
    }

    /// Declined + manually-archived threads, collapsed under a tappable header.
    @ViewBuilder
    private var archivedSection: some View {
        if !viewModel.archivedConvos.isEmpty {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { archivedOpen.toggle() }
            } label: {
                HStack(spacing: 6) {
                    LucideIcon(.chevronRight, .sm)
                        .rotationEffect(.degrees(archivedOpen ? 90 : 0))
                    Text("Archived")
                    Text("\(viewModel.archivedConvos.count)").monospacedDigit()
                    Spacer(minLength: 0)
                }
                .font(.appLabel)
                .foregroundStyle(Color.vText3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if archivedOpen {
                ForEach(viewModel.archivedConvos) { item in
                    ConversationRow(item: item)
                }
            }
        }
    }
}

// MARK: - Category copy

extension MessageBucket {
    /// The folder row's label in the inbox list.
    var rowLabel: String {
        switch self {
        case .requests: "Message requests"
        case .orders: "Orders"
        case .inquiries: "Inquiries"
        case .listings: "Listings"
        default: ""
        }
    }

    /// The pushed folder's band title.
    var folderTitle: String {
        self == .requests ? "New message requests" : rowLabel
    }
}

// MARK: - Search field (always visible, web parity)

private struct MessagesSearchField: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    /// × closes the field (and clears the search).
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            LucideIcon(.search, .md).foregroundStyle(Color.vText3)
            TextField("", text: $text, prompt: Text("Search messages…").foregroundStyle(Color.vText3))
                .font(.appBody)
                .foregroundStyle(Color.vText)
                .tint(Color.vText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused(focus)
            Button(action: onClose) {
                LucideIcon(.x, .md)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 28, height: 28)
                    .minimumHitArea(for: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close search")
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(
            focus.wrappedValue ? Color.vFieldFocus : Color.vField,
            in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        )
    }
}

// MARK: - Empty inbox (ghost chat bubbles)

/// "No conversations yet" over a little ghost conversation: bubbles land in
/// a stagger (incoming left on `vSurface`, outgoing right on `vSurface2`),
/// then a typing bubble pulses its three dots.
struct InboxEmptyState: View {
    var title = "No conversations yet"
    var message: String? = "Messages, collab requests and orders land here."
    var compact = false

    @State private var shown = 0

    private let bubbles: [(outgoing: Bool, width: CGFloat)] = [
        (false, 132), (true, 168), (false, 104), (true, 120),
    ]

    var body: some View {
        VStack(spacing: compact ? 20 : 28) {
            VStack(spacing: 8) {
                ForEach(Array(bubbles.prefix(compact ? 2 : 4).enumerated()), id: \.offset) { index, bubble in
                    ghostBubble(outgoing: bubble.outgoing, width: bubble.width)
                        .opacity(shown > index ? 1 : 0)
                        .offset(y: shown > index ? 0 : 8)
                }
                TypingBubble()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(shown > (compact ? 2 : 4) ? 1 : 0)
            }
            .frame(width: 220)

            VStack(spacing: 6) {
                Text(title).font(.appSubheadlineSemibold).foregroundStyle(Color.vText)
                if let message {
                    Text(message)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.vText2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
            }
        }
        .padding(.horizontal, 40)
        .task {
            let total = (compact ? 2 : 4) + 1
            for step in 1 ... total {
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeOut(duration: 0.2)) { shown = step }
            }
        }
    }

    private func ghostBubble(outgoing: Bool, width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
            .fill(outgoing ? Color.vSurface2 : Color.vSurface)
            .frame(width: width, height: 30)
            .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
    }
}

/// An incoming bubble with three pulsing dots.
private struct TypingBubble: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0 ..< 3, id: \.self) { i in
                Circle()
                    .fill(Color.vText3)
                    .frame(width: 6, height: 6)
                    .opacity(pulse ? 1 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.2),
                        value: pulse
                    )
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 30)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        .onAppear { pulse = true }
    }
}

// MARK: - Pressed-state highlight (the web's hover equivalent)

struct RowHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.ink(configuration.isPressed ? 0.06 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Loading skeleton (rows, soft pulse)

private struct MessagesSkeleton: View {
    /// Stays invisible for a beat so fast loads swap straight to content —
    /// a skeleton that flashes for 100ms reads as a glitch.
    @State private var visible = false

    var body: some View {
        SkeletonRows(
            count: 6,
            thumb: .circle(size: 48),
            line1: CGSize(width: 140, height: 14),
            line2: CGSize(width: 210, height: 11),
            lineSpacing: 8,
            thumbSpacing: 12,
            verticalPadding: 12
        )
        .opacity(visible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeIn(duration: 0.3)) { visible = true }
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    MessagesScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
        .environment(dependencies.inboxStore)
        .environment(ConversationState())
}
