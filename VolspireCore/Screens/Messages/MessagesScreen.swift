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
    @State private var viewModel = MessagesScreenViewModel()
    @FocusState private var searchFocused: Bool
    /// Home/Marketplace-style search: hidden by default, revealed (and focused)
    /// when the header search icon is tapped.
    @State private var showSearchField = false
    @State private var archivedOpen = false

    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1) // keep the header's bottom shadow above the content below
            if showSearchField {
                searchRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
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
        .task { await viewModel.load() }
        .onChange(of: conversationState.activeConversation) { _, convo in
            // Returning from a thread — refresh so unread + last-message update.
            if convo == nil { Task { await viewModel.load() } }
        }
    }

    // MARK: - Header + search (matches Library/Marketplace)

    private var header: some View {
        ScreenHeader("Messages") {
            HeaderIconButton(icon: .bell) { router.navigateToNotifications() }
            HeaderIconButton(icon: .search) {
                withAnimation(.easeInOut(duration: 0.2)) { showSearchField = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
            }
        }
    }

    /// Search field revealed by the header search icon. Cancel hides it + clears.
    private var searchRow: some View {
        HStack(spacing: 12) {
            searchField
            Button("Cancel") {
                searchFocused = false
                withAnimation(.easeInOut(duration: 0.2)) { showSearchField = false }
                viewModel.searchText = ""
            }
            .font(.appCallout)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.bottom, 12)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            LucideIcon(.search, .md).foregroundStyle(Color.vText3)
            TextField("", text: $viewModel.searchText, prompt: Text("Search messages…").foregroundColor(Color.vText3))
                .font(.appCallout)
                .foregroundStyle(.white)
                .tint(.white)
                .focused($searchFocused)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    LucideIcon(.circleX, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.vBorder, lineWidth: 1))
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
                    emptyState(title: "No matches", message: nil).padding(.top, 60)
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
            if let u = items.first?.username {
                return "From @\(u)" + (n > 1 ? " · +\(n - 1) more" : "")
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
        VStack(spacing: 10) {
            LucideIcon(.messageCircle, .hero).foregroundStyle(Color.vText3)
            Text(title).font(.appTitle3).foregroundStyle(.white)
            if let message {
                Text(message).font(.appSubheadline).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
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

            ForEach(0..<8, id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle().fill(bone).frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Capsule().fill(bone).frame(width: 130, height: 13)
                            Spacer()
                            Capsule().fill(bone).frame(width: 36, height: 10)
                        }
                        Capsule().fill(bone).frame(width: 200, height: 11)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .padding(.horizontal, 8)
            }
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
