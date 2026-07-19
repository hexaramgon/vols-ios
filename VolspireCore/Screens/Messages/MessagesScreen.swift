//
//  MessagesScreen.swift
//  Volspire
//
//  Conversation inbox — the Inbox tab. Mirrors the Library/Marketplace tab-root
//  structure (custom header + reveal-search + gradient background). Category
//  folders push a `MessageCategoryScreen` through the Router, the same way
//  Library/Marketplace push their detail pages.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct MessagesScreen: View {
    @Environment(ConversationState.self) private var conversationState
    @Environment(Router.self) private var router
    @Environment(PlayerController.self) private var playerController
    @Environment(UnreadCounts.self) private var unreadCounts
    @Environment(Dependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = MessagesScreenViewModel()
    @FocusState private var searchFocused: Bool
    /// Home/Marketplace-style search: hidden by default, revealed (and focused)
    /// when the header search icon is tapped.
    @State private var showSearchField = false
    @State private var archivedOpen = false

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1) // keep the header (and its sliding search reveal) above the content below
            ScrollView {
                content
                    .animation(.easeOut(duration: 0.25), value: viewModel.loadingState)
                    .animation(.easeOut(duration: 0.25), value: viewModel.conversations.isEmpty)
            }
            .scrollIndicators(.hidden)
            .refreshable { await viewModel.load() }
        }
        .animation(.easeInOut(duration: 0.2), value: showSearchField)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationBarHidden(true)
        .gradientBackground()
        .task {
            viewModel.currentUserId = dependencies.authManager.currentUserId
            await viewModel.load()
        }
        .onChange(of: conversationState.activeConversation) { _, convo in
            // Returning from a thread — refresh so unread + last-message update.
            if convo == nil { Task { await viewModel.load() } }
        }
        .onChange(of: scenePhase) { _, phase in
            // Foregrounding (e.g. opening the app from a message push) — refresh the
            // list so the new conversation / message shows without a manual reload.
            if phase == .active { Task { await viewModel.load() } }
        }
    }

    // MARK: - Header + search (matches Library/Marketplace)

    private var header: some View {
        ScreenHeader("Inbox") {
            HeaderIconButton(icon: .bell, showDot: unreadCounts.notifications > 0) {
                router.navigateToNotifications()
            }
            HeaderIconButton(icon: .search) {
                withAnimation(.easeInOut(duration: 0.2)) { showSearchField = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
            }
        } expansion: {
            // Inside the header chrome so the bar background sits behind the
            // field — not floating over the page content.
            if showSearchField {
                HeaderSearchField(
                    prompt: "Search messages…",
                    text: $viewModel.searchText,
                    isRevealed: $showSearchField,
                    focus: $searchFocused
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Content

    private var isLoadError: Bool {
        if case .error = viewModel.loadingState { return true }
        return false
    }

    /// True until the first load resolves — covers `.idle` too so the skeleton
    /// shows from the very first frame instead of flashing the empty state.
    private var isInitialLoading: Bool {
        (viewModel.loadingState == .idle || viewModel.loadingState == .loading)
            && viewModel.conversations.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if isInitialLoading {
            MessagesSkeleton()
        } else if isLoadError && viewModel.conversations.isEmpty {
            LoadErrorView { Task { await viewModel.load() } }
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        } else if viewModel.conversations.isEmpty {
            emptyState(title: "No messages yet", message: "Conversations with collaborators and buyers show up here.")
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        } else {
            LazyVStack(alignment: .leading, spacing: 2) {
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
            .padding(.top, 8)
            .padding(.bottom, bottomInset)
        }
    }

    // MARK: - Main inbox (category folders + DMs) — web-style classification

    @ViewBuilder
    private var mainInbox: some View {
        categoryRow(.bell, "Message requests", viewModel.pendingRequests)
        categoryRow(.shoppingCart, "Orders", viewModel.orders)
        categoryRow(.briefcase, "Inquiries", viewModel.inquiries)
        categoryRow(.handshake, "Listings", viewModel.listings)
        ForEach(viewModel.directConvos) { item in
            ConversationRow(item: item)
        }
        archivedSection
    }

    /// A tappable "folder" row — pushes a `MessageCategoryScreen` via the Router,
    /// the same way Library/Marketplace push their detail pages.
    @ViewBuilder
    private func categoryRow(_ icon: LucideIcon.Name, _ label: String, _ items: [ConversationItem]) -> some View {
        if !items.isEmpty {
            let unread = items.reduce(0) { $0 + $1.unreadCount }
            Button {
                searchFocused = false
                router.navigateToMessageCategory(title: label, items: items)
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(Color.vSurface)
                        LucideIcon(icon, .lg).foregroundStyle(.white)
                    }
                    .frame(width: 46, height: 46)
                    .overlay(Circle().strokeBorder(Color.vBorder))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(label)
                            .font(unread > 0 ? .appCalloutSemibold : .appCallout)
                            .foregroundStyle(.white).lineLimit(1)
                        Text(categorySubtitle(label, items))
                            .font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if unread > 0 {
                        Text("\(unread)")
                            .font(.appCaption2Bold).foregroundStyle(.black).monospacedDigit()
                            .frame(minWidth: 18, minHeight: 18)
                            .padding(.horizontal, 5)
                            .background(.white, in: Capsule())
                    }
                    LucideIcon(.chevronRight, .md).foregroundStyle(Color.vText3)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .contentShape(.rect)
            }
            .buttonStyle(RowHighlightButtonStyle())
        }
    }

    private func categorySubtitle(_ label: String, _ items: [ConversationItem]) -> String {
        let n = items.count
        if label == "Message requests" {
            if let first = items.first {
                // Direction-aware: requests I sent read "To @…", received "From @…".
                let prefix = first.lastMessageFromMe ? "To" : "From"
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
                    Text("ARCHIVED")
                        .font(.appCaption2Bold).tracking(0.8).foregroundStyle(Color.vText3)
                    Text("\(viewModel.archivedConvos.count)")
                        .font(.appCaption2Semibold).foregroundStyle(Color.vText3).monospacedDigit()
                    Spacer(minLength: 0)
                    LucideIcon(.chevronDown, .sm)
                        .foregroundStyle(Color.vText3)
                        .rotationEffect(.degrees(archivedOpen ? 180 : 0))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 6)
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

    private func emptyState(title: String, message: String?) -> some View {
        EmptyStateView(icon: .messageCircle, title: title, message: message)
    }
}

// MARK: - Pressed-state highlight (the web's hover equivalent)

struct RowHighlightButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 14

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Loading skeleton (search bar + rows, soft pulse)

private struct MessagesSkeleton: View {
    /// Stays invisible for a beat so fast loads swap straight to content —
    /// a skeleton that flashes for 100ms reads as a glitch.
    @State private var visible = false
    private let bone = Color.white.opacity(0.08)

    var body: some View {
        skeletonRows
            .opacity(visible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeIn(duration: 0.3)) { visible = true }
            }
    }

    private var skeletonRows: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 12)
                .fill(bone)
                .frame(height: 42)
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.bottom, 10)

            SkeletonRows(
                count: 8,
                thumb: .circle(size: 46),
                line1: CGSize(width: 130, height: 13),
                line2: CGSize(width: 200, height: 11),
                line1Trailing: CGSize(width: 36, height: 10),
                lineSpacing: 7,
                thumbSpacing: 12,
                rowSpacing: 2,
                horizontalPadding: 20,
                verticalPadding: 11,
                boneOpacity: 0.08,
                shimmers: false
            )
        }
        .shimmering()
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    MessagesScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
        .environment(ConversationState())
}
