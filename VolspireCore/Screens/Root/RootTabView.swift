//
//  RootTabView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Services
import SwiftUI

/// Lightweight context for the conversation overlay shown over the tab bar.
struct ActiveConversation: Identifiable, Equatable, Hashable {
    let convoId: String
    let otherUserId: String?
    let username: String
    let avatarURL: String?
    var id: String { convoId }
}

@Observable
class ConversationState {
    // Set directly by ConversationScreen's onAppear/onDisappear; the tab bar and
    // mini-player observe it with their own scoped animations, so no withAnimation
    // is needed (or wanted — competing curves made the hide look janky).
    var activeConversation: ActiveConversation?
}

/// App-wide unread indicators: the Inbox tab dot (DMs) and the notifications
/// bell dot (activity). Backed by the same `get_unread_counts` RPC the web
/// uses; refreshed at the moments the counts can change (launch, foreground,
/// tab switches, closing a conversation).
@Observable @MainActor
final class UnreadCounts {
    private(set) var notifications = 0
    private(set) var messages = 0
    private let service = SupabaseService()

    func refresh() async {
        guard let counts = try? await service.getUnreadCounts() else { return }
        notifications = counts.notifications
        messages = counts.messages
    }

    /// Optimistic zero when the notifications screen opens (the server marks
    /// them read at the same moment).
    func clearNotifications() { notifications = 0 }
}

struct RootTabView: View {
    @State private var showNewPost = false
    @State private var selectedPostType: String?
    @State private var selectedTab: TabBarItem = .home
    @State private var profileAvatarImage: Image?
    @State private var visitedTabs: Set<TabBarItem> = [.home]
    @State private var unreadCounts = UnreadCounts()
    /// Measured height of the custom tab bar (varies with Dynamic Type).
    @State private var tabBarHeight: CGFloat = 52
    @Environment(\.scenePhase) private var scenePhase

    // One router (nav stack) per content tab, owned here so navigation can be
    // driven into whichever tab is currently active.
    @State private var homeRouter = Router()
    @State private var libraryRouter = Router()
    @State private var inboxRouter = Router()
    @State private var profileRouter = Router()

    private func router(for tab: TabBarItem) -> Router {
        switch tab {
        case .home, .newPost: homeRouter
        case .library: libraryRouter
        case .inbox: inboxRouter
        case .profile: profileRouter
        }
    }

    /// Logical screen name for analytics `page_view` events.
    private func analyticsName(_ tab: TabBarItem) -> String {
        switch tab {
        case .home: "home"
        case .library: "library"
        case .inbox: "inbox"
        case .profile: "profile"
        case .newPost: "new_post"
        }
    }

    /// Tabs that show a screen (everything except the New Post "+" which opens a sheet).
    private let contentTabs: [TabBarItem] = [.home, .library, .inbox, .profile]
    @Environment(ConversationState.self) var conversationState
    @Environment(Dependencies.self) var dependencies
    @Environment(PlayerController.self) private var playerController

    /// The collapsed mini-player floats above the tab bar, so content is padded to clear it.
    private var showMiniPlayer: Bool { !playerController.display.title.isEmpty }

    private var isConversationOpen: Bool { conversationState.activeConversation != nil }

    /// Bottom safe-area reservation: the tab bar plus clearance for the floating mini-player.
    private var bottomBarReservation: CGFloat {
        tabBarHeight + (showMiniPlayer ? ViewConst.compactNowPlayingHeight + 16 : 0)
    }

    init() {
        // Near-black chrome to match the app's dark theme; Geist nav-bar titles.
        // (The bottom bar is now a custom SwiftUI view, so no UITabBar appearance here.)
        let barColor = UIColor(white: 0.07, alpha: 1) // ~#121212

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = barColor
        navBarAppearance.titleTextAttributes = [.font: UIFont(name: "Geist-SemiBold", size: 17) ?? .systemFont(ofSize: 17, weight: .semibold)]
        navBarAppearance.largeTitleTextAttributes = [.font: UIFont(name: "Geist-Bold", size: 34) ?? .systemFont(ofSize: 34, weight: .bold)]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
    }

    var body: some View {
        ZStack {
            // Custom tab bar instead of SwiftUI's TabView: the system TabView cross-
            // dissolves between tabs on iOS 18+ with no way to disable it. Here each
            // visited tab is kept alive and the selected one is shown instantly.
            ZStack {
                ForEach(contentTabs, id: \.self) { tab in
                    if visitedTabs.contains(tab) {
                        tab.destinationView(router: router(for: tab))
                            .opacity(selectedTab == tab ? 1 : 0)
                            .allowsHitTesting(selectedTab == tab)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Invisible reservation that keeps tab content above the bar (and
                // the floating mini-player). Inside a conversation it collapses so
                // the chat is full-screen — with NO animation: animating a safe-area
                // change re-lays-out every kept-alive tab on every frame of the nav
                // push, which is what made the tab-bar hide look choppy. The one-off
                // jump happens behind the sliding bar / incoming chat, so it's
                // never visible.
                Color.clear
                    .frame(height: isConversationOpen ? 0 : bottomBarReservation)
                    .animation(nil, value: isConversationOpen)
            }
            .overlay(alignment: .bottom) {
                // The visible bar never unmounts — hiding is a pure offset, which
                // stays smooth while the push animation runs alongside it.
                customTabBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { tabBarHeight = $0 }
                    .offset(y: isConversationOpen ? tabBarHeight + ViewConst.safeAreaInsets.bottom : 0)
                    .animation(.smooth(duration: 0.35), value: isConversationOpen)
                    .allowsHitTesting(!isConversationOpen)
            }
            .sheet(isPresented: $showNewPost) {
                NewPostView { postType in
                    selectedPostType = postType
                }
            }
            .fullScreenCover(item: Binding(
                get: { selectedPostType.map { PostTypeID(id: $0) } },
                set: { selectedPostType = $0?.id }
            )) { wrapper in
                switch wrapper.id {
                case "listing":
                    CreateListingScreen(
                        viewModel: CreateListingViewModel(
                            supabaseService: dependencies.supabaseService,
                            authManager: dependencies.authManager
                        )
                    )
                case "sample_pack":
                    CreatePackScreen(
                        viewModel: CreatePackViewModel(
                            supabaseService: dependencies.supabaseService,
                            authManager: dependencies.authManager
                        )
                    )
                case "service":
                    NewServiceScreen(
                        viewModel: NewServiceViewModel(
                            supabaseService: dependencies.supabaseService,
                            authManager: dependencies.authManager
                        )
                    )
                default:
                    UploadTrackScreen(
                        viewModel: UploadTrackViewModel(
                            supabaseService: dependencies.supabaseService,
                            authManager: dependencies.authManager
                        )
                    )
                }
            }
            .ignoresSafeArea(.keyboard)
            .onReceive(NotificationCenter.default.publisher(for: .navigateToProfile)) { notification in
                if let userId = notification.userInfo?["userId"] as? String {
                    // Push onto whichever tab is currently active — no detour through Home.
                    visitedTabs.insert(selectedTab)
                    router(for: selectedTab).navigateToProfile(userId: userId)
                }
            }

        }
        .environment(conversationState)
        .environment(unreadCounts)
        // Unread dots refresh at every moment the counts can change.
        .task { await unreadCounts.refresh() }
        .onChange(of: selectedTab) { _, _ in
            Task { await unreadCounts.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await unreadCounts.refresh() } }
        }
        .onChange(of: conversationState.activeConversation) { _, convo in
            // Closing a conversation → its messages were just read.
            if convo == nil { Task { await unreadCounts.refresh() } }
        }
        .task { await loadProfileAvatar() }
        .task { AnalyticsService.shared?.log(.pageView, metadata: ["to": .string(analyticsName(selectedTab))]) }
    }

    /// Loads the signed-in user's avatar so the Profile tab shows their photo (like the web).
    /// The tab bar renders an icon at its *natural* size, so we pre-crop to a small circle
    /// rather than relying on SwiftUI `.frame`/`.clipShape` (which the tab bar ignores).
    private func loadProfileAvatar() async {
        guard let uid = dependencies.authManager.currentUserId else { return }
        let profile = try? await dependencies.supabaseService.getUserProfile(userId: uid)
        guard let urlString = profile?.profileImageUrl, let url = URL(string: urlString) else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let uiImage = UIImage(data: data) else { return }
        profileAvatarImage = Image(uiImage: circularThumbnail(uiImage, pointSize: 26))
    }

    /// Center-crops `image` into a circle sized for a tab icon.
    private func circularThumbnail(_ image: UIImage, pointSize: CGFloat) -> UIImage {
        let target = CGSize(width: pointSize, height: pointSize)
        let renderer = UIGraphicsImageRenderer(size: target)
        let result = renderer.image { _ in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: target)).addClip()
            let fill = max(target.width / image.size.width, target.height / image.size.height)
            let drawn = CGSize(width: image.size.width * fill, height: image.size.height * fill)
            image.draw(in: CGRect(
                x: (target.width - drawn.width) / 2,
                y: (target.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }
        return result.withRenderingMode(.alwaysOriginal)
    }

    /// Profile tab renders the user's avatar; every other tab uses its Lucide icon.
    @ViewBuilder
    private func tabIcon(for item: TabBarItem) -> some View {
        if item == .profile, let avatar = profileAvatarImage {
            avatar
                .renderingMode(.original)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(Circle())
        } else {
            item.image
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
        }
    }

    /// Custom bottom tab bar (replaces SwiftUI's TabView to avoid the system cross-dissolve).
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TabBarItem.allCases, id: \.self) { item in
                Button {
                    if item == .newPost {
                        showNewPost = true
                    } else if selectedTab == item {
                        // Re-tapping the active tab pops its nav stack back to
                        // the tab's root (e.g. Marketplace detail → Marketplace).
                        router(for: item).popToRoot()
                    } else {
                        selectedTab = item
                        visitedTabs.insert(item)
                        // Home always lands fully reset — root page, scrolled
                        // to the top (HomeScreen observes rootResetTick).
                        if item == .home { router(for: .home).popToRoot() }
                        AnalyticsService.shared?.log(.pageView, metadata: ["to": .string(analyticsName(item))])
                    }
                } label: {
                    VStack(spacing: 3) {
                        tabIcon(for: item)
                            // Unread-DM dot on the Inbox tab.
                            .overlay(alignment: .topTrailing) {
                                if item == .inbox, unreadCounts.messages > 0 {
                                    Circle()
                                        .fill(Color.vUnread)
                                        .frame(width: 8, height: 8)
                                        .offset(x: 3, y: -1)
                                }
                            }
                        Text(item.title)
                            .font(.appMicro)
                    }
                    .foregroundStyle(selectedTab == item ? .white : Color(white: 0.55))
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            Color(white: 0.07)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct PostTypeID: Identifiable {
    let id: String
}

private extension TabBarItem {
    @MainActor
    @ViewBuilder
    func destinationView(router: Router) -> some View {
        switch self {
        case .home:
            HomeScreen()
                .withRouter(router)
        case .library:
            LibraryScreen()
                .withRouter(router)
        case .newPost:
            EmptyView()
        case .inbox:
            MessagesScreen()
                .withRouter(router)
        case .profile:
            ProfileScreen()
                .withRouter(router)
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    RootTabView()
        .environment(playerController)
        .environment(dependencies)
}
