//
//  RootTabView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import MediaLibrary
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

    /// Set by a bottom-docked composer (e.g. the listing detail's comment field)
    /// while its keyboard is up, so the tab bar slides away instead of wedging
    /// between the composer and the keyboard — the same hide conversations use.
    var composerActive = false

    /// Set while Explore's full-screen search is open, so the tab bar and
    /// mini-player slide away instead of floating over it.
    var searchOpen = false
}

private struct IsActiveRootTabKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True when the enclosing root tab is the one currently shown. RootTabView keeps
    /// every visited tab mounted (at opacity 0), so views that run timers/animations
    /// use this to pause work while their tab is hidden. Defaults true (previews /
    /// standalone use).
    var isActiveRootTab: Bool {
        get { self[IsActiveRootTabKey.self] }
        set { self[IsActiveRootTabKey.self] = newValue }
    }
}

struct RootTabView: View {
    @State private var showNewPost = false
    @State private var selectedPostType: String?
    /// Picked in the New post sheet; presented once that sheet has dismissed
    /// (a full-screen cover can't present from a dismissing sheet).
    @State private var pendingPostType: String?
    /// A file to open the track upload with (Workspace "Post as track").
    @State private var trackPrefill: TrackFilePrefill?
    /// A Workspace folder's files for New Pack ("Publish as pack").
    @State private var packPrefill: PackPrefill?
    @State private var selectedTab: TabBarItem = .home
    @State private var profileAvatarImage: Image?
    @State private var visitedTabs: Set<TabBarItem> = [.home]
    /// Measured height of the custom tab bar (varies with Dynamic Type).
    @State private var tabBarHeight: CGFloat = 52
    @Environment(\.scenePhase) private var scenePhase

    // One router (nav stack) per content tab, owned here so navigation can be
    // driven into whichever tab is currently active.
    @State private var homeRouter = Router()
    @State private var libraryRouter = Router()
    @State private var workspaceRouter = Router()
    @State private var profileRouter = Router()

    private func router(for tab: TabBarItem) -> Router {
        switch tab {
        case .home, .newPost: homeRouter
        case .library: libraryRouter
        case .workspace: workspaceRouter
        case .profile: profileRouter
        }
    }

    /// Logical screen name for analytics `page_view` events.
    private func analyticsName(_ tab: TabBarItem) -> String {
        switch tab {
        case .home: "home"
        case .library: "library"
        case .workspace: "workspace"
        case .profile: "profile"
        case .newPost: "new_post"
        }
    }

    /// Tabs that show a screen (everything except the New Post "+" which opens a sheet).
    private let contentTabs: [TabBarItem] = [.home, .library, .workspace, .profile]
    @Environment(ConversationState.self) var conversationState
    @Environment(Dependencies.self) var dependencies
    @Environment(PlayerController.self) private var playerController

    /// The collapsed mini-player floats above the tab bar, so content is padded to clear it.
    private var showMiniPlayer: Bool { playerController.hasMedia }

    private var isConversationOpen: Bool { conversationState.activeConversation != nil }

    /// Tab bar slides away for a full-screen conversation OR while a bottom
    /// composer's keyboard is up (so it doesn't wedge above the keyboard).
    private var hideTabBar: Bool { isConversationOpen || conversationState.composerActive }

    /// Bottom safe-area reservation: the tab bar plus clearance for the floating mini-player.
    private var bottomBarReservation: CGFloat {
        tabBarHeight + (showMiniPlayer ? ViewConst.compactNowPlayingHeight + 16 : 0)
    }

    init() {
        // The app chrome tone — `UIColor.vBar`, the themed UIKit mirror of
        // `Color.vBar` (a plain dynamic UIColor: no SwiftUI Color→UIColor
        // bridging on the boot path).
        // (The bottom bar is now a custom SwiftUI view, so no UITabBar appearance here.)
        let barColor = UIColor.vBar

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
                            .environment(\.isActiveRootTab, selectedTab == tab)
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
                    .frame(height: hideTabBar ? 0 : bottomBarReservation)
                    .animation(nil, value: hideTabBar)
            }
            .overlay(alignment: .bottom) {
                // The visible bar never unmounts — hiding is a pure offset, which
                // stays smooth while the push animation runs alongside it.
                customTabBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        tabBarHeight = $0
                        // Publish for chrome consumers outside this view —
                        // contentBottomInset and the mini-player's collapsed
                        // frame (OverlaidRootView hardcoded 49pt before, which
                        // drifted from the real bar at larger Dynamic Type).
                        playerController.tabBarHeight = $0
                    }
                    // Search only moves the bar (not the reservation above),
                    // so Home's layout doesn't jump behind it.
                    .offset(y: hideTabBar || conversationState.searchOpen ? tabBarHeight + ViewConst.safeAreaInsets.bottom : 0)
                    // Conversation hide keeps its tuned spring. The composer hide
                    // uses a plain scoped ease — decoupled from the keyboard's
                    // system animation (never withAnimation'd in the keyboard
                    // handler) so it can't merge and overshoot.
                    .animation(.smooth(duration: 0.35), value: isConversationOpen)
                    .animation(.easeInOut(duration: 0.25), value: conversationState.composerActive)
                    .animation(.easeInOut(duration: 0.25), value: conversationState.searchOpen)
                    .allowsHitTesting(!hideTabBar && !conversationState.searchOpen)
            }
            // New post: the app's standard option sheet (header + icon rows).
            .sheet(isPresented: $showNewPost, onDismiss: {
                if let type = pendingPostType {
                    pendingPostType = nil
                    selectedPostType = type
                }
            }) {
                NewPostSheet { type in
                    pendingPostType = type
                    showNewPost = false
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
                case "release":
                    CreateReleaseScreen(
                        viewModel: CreateReleaseViewModel(
                            service: dependencies.supabaseService,
                            auth: dependencies.authManager
                        )
                    )
                case "sample_pack":
                    CreatePackScreen(
                        viewModel: CreatePackViewModel(
                            supabaseService: dependencies.supabaseService,
                            authManager: dependencies.authManager
                        ),
                        prefill: packPrefill
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
                        ),
                        prefill: trackPrefill
                    )
                }
            }
            .onChange(of: selectedPostType) { _, type in
                if type == nil { trackPrefill = nil; packPrefill = nil }
            }
            .ignoresSafeArea(.keyboard)
            // The Marketplace tab's Sell sheet opens a create flow by its
            // New post id ("sample_pack", "service", "track").
            .onReceive(NotificationCenter.default.publisher(for: .openNewPost)) { notification in
                trackPrefill = notification.userInfo?["trackPrefill"] as? TrackFilePrefill
                packPrefill = notification.userInfo?["packPrefill"] as? PackPrefill
                if let type = notification.object as? String { selectedPostType = type }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToProfile)) { notification in
                if let userId = notification.userInfo?["userId"] as? String {
                    // Push onto whichever tab is currently active — no detour through Home.
                    visitedTabs.insert(selectedTab)
                    router(for: selectedTab).navigateToProfile(userId: userId)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPushNotification)) { _ in
                routePendingPush()
            }
            // Fired when the post-publish confirmation card finishes: open what
            // the user just posted — their track in the expanded player, or
            // their listing's detail page.
            .onReceive(NotificationCenter.default.publisher(for: .openOwnPost)) { note in
                if let trackId = note.userInfo?["trackId"] as? String {
                    openTrackFromPush(trackId, fallbackToNotifications: false)
                } else if let listingId = note.userInfo?["listingId"] as? String {
                    openListingFromPush(listingId, fallbackToNotifications: false)
                }
            }

        }
        // Unread dots + app badge refresh at every moment the counts can
        // change — one pipeline in InboxStore.
        .task { await dependencies.inboxStore.refreshUnread() }
        // Warm the library store once per session so bookmark glyphs are
        // correct on every surface — not just after the Library tab loads.
        .task { await dependencies.libraryStore.loadIfNeeded() }
        // Cold launch: route a push tapped before the UI was ready to receive it.
        .task { routePendingPush() }
        // Push primer: once, a beat after the app settles, for anyone who
        // hasn't been asked yet. Its button shows the system prompt.
        .task {
            let push = PushNotificationManager.shared
            await push.refreshStatus()
            guard push.authorizationStatus == .notDetermined else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            IntroModalCenter.shared.present(.pushPrimer) {
                Task { await push.requestPermission() }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            Task { await dependencies.inboxStore.refreshUnread() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await dependencies.inboxStore.refreshUnread() } }
        }
        .task {
            await dependencies.socialStore.loadMyProfileIfNeeded()
            await rebuildProfileAvatar()
        }
        // Avatar edited (SocialStore refreshed) → re-crop the tab thumbnail.
        .onChange(of: dependencies.socialStore.myProfile?.profileImageUrl) { _, _ in
            Task { await rebuildProfileAvatar() }
        }
        .task { AnalyticsService.shared?.log(.pageView, metadata: ["to": .string(analyticsName(selectedTab))]) }
    }

    /// Deep-links a tapped push notification to the entity it references
    /// (message → conversation, folder share → folder, else → notifications).
    private func routePendingPush() {
        guard let info = PushInbox.pending else { return }
        PushInbox.pending = nil
        let r = router(for: selectedTab)
        visitedTabs.insert(selectedTab)
        switch info["type"] {
        case "message":
            guard let convoId = info["convo_id"] else { return }
            r.navigateToConversation(ActiveConversation(
                convoId: convoId,
                otherUserId: info["sender_id"],
                username: info["title"] ?? "Conversation",
                avatarURL: nil
            ))
        case "activity":
            if let type = info["object_type"], type.contains("folder"), let id = info["object_id"] {
                // Share / upload / add in a folder → open the folder itself.
                openFolderFromPush(id)
            } else if info["object_type"] == "track", let id = info["object_id"] {
                // Comment / like / save on a track → open the track itself.
                openTrackFromPush(id)
            } else if info["object_type"] == "listing", let id = info["object_id"] {
                // A response to your collab listing → open the listing.
                openListingFromPush(id)
            } else {
                r.navigateToNotifications()
            }
        default:
            break
        }
    }

    /// A listing push opens the listing detail — fetched fresh so responses
    /// and counts are current; notifications page as the fallback (own-post
    /// opens fail quietly instead — there's no sensible fallback screen).
    private func openListingFromPush(_ listingId: String, fallbackToNotifications: Bool = true) {
        Task {
            guard let listing = try? await dependencies.supabaseService.getListing(listingId: listingId) else {
                if fallbackToNotifications { router(for: selectedTab).navigateToNotifications() }
                return
            }
            router(for: selectedTab).navigateToCollabListing(listing)
        }
    }

    /// A folder push resolves the real folder first (its name — the screen
    /// header) instead of navigating with a "Folder" placeholder; the
    /// recipient is a member, so it's in their folder list.
    private func openFolderFromPush(_ folderId: String) {
        Task {
            let name = (try? await dependencies.supabaseService.getUserFolders())?
                .first { $0.folderId.lowercased() == folderId.lowercased() }?.name ?? "Folder"
            router(for: selectedTab).navigateToFolder(folderId: folderId, folderName: name)
        }
    }

    /// A track push opens the track: fetch it, start playback, and expand the
    /// player (that's the app's track view — comments included). Falls back to
    /// the notifications page if the track can't be loaded (deleted/offline);
    /// own-post opens fail quietly instead.
    private func openTrackFromPush(_ trackId: String, fallbackToNotifications: Bool = true) {
        Task {
            let storage = StorageService()
            guard let track = (try? await dependencies.supabaseService.getTracksByIds([trackId]))?.first,
                  let audioURL = storage.trackMediaURL(track.audioUrl)
            else {
                if fallbackToNotifications { router(for: selectedTab).navigateToNotifications() }
                return
            }
            let media = Media(
                id: MediaID(track.trackId),
                meta: MediaMeta(
                    artwork: storage.resolveTrackUrl(track.coverUrl).flatMap { URL(string: $0) },
                    title: track.title ?? "Track",
                    artist: track.artistUsername,
                    audioURL: audioURL
                )
            )
            playerController.playSingle(media)
            playerController.pendingExpand = true
        }
    }

    /// Builds the Profile tab's avatar from the shared SocialStore profile
    /// (so an avatar edit updates the tab without a relaunch). The tab bar
    /// renders an icon at its *natural* size, so we pre-crop to a small circle
    /// rather than relying on SwiftUI `.frame`/`.clipShape` (which the tab bar ignores).
    private func rebuildProfileAvatar() async {
        guard let urlString = dependencies.socialStore.myProfile?.profileImageUrl,
              let url = URL(string: urlString) else {
            profileAvatarImage = nil
            return
        }
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

    /// Every tab — Profile included, for now — uses its plain Lucide icon
    /// (Profile: the User glyph, not the avatar). The avatar crop below is kept
    /// so it can come back.
    private func tabIcon(for item: TabBarItem) -> some View {
        item.image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: IconSize.lg.rawValue, height: IconSize.lg.rawValue)
    }

    /// Custom bottom tab bar (replaces SwiftUI's TabView to avoid the system cross-dissolve).
    private var customTabBar: some View {
        HStack(spacing: 0) {
            ForEach(TabBarItem.allCases, id: \.self) { item in
                Button {
                    if item == .newPost {
                        showNewPost = true
                    } else if selectedTab == item {
                        // Re-tapping the ACTIVE tab: first pops its nav stack
                        // back to the tab's root (your place kept); a further
                        // tap at the root scrolls it to the top.
                        router(for: item).popToRoot()
                    } else {
                        // Arriving from another tab resumes this tab exactly
                        // where it was left — same page, same scroll. Home used
                        // to reset here too, which threw away the user's place
                        // for a gesture that only means "go to Home".
                        selectedTab = item
                        visitedTabs.insert(item)
                        AnalyticsService.shared?.log(.pageView, metadata: ["to": .string(analyticsName(item))])
                    }
                } label: {
                    if item == .newPost {
                        newPostTabButton
                    } else {
                        tabLabel(for: item)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            Color.vBar
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.vSurface2.opacity(0.8))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The center New-post action — a 44×36 ink capsule with a "+". It
    /// stays as-is while the New post sheet is up (the sheet is the feedback).
    private var newPostTabButton: some View {
        LucideIcon(.plus, .lg)
            .foregroundStyle(Color.vOnInverse)
            .frame(width: 44, height: 36)
            .background(Color.vInverse, in: Capsule())
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .accessibilityLabel(TabBarItem.newPost.title)
    }

    private func tabLabel(for item: TabBarItem) -> some View {
        VStack(spacing: 3) {
            tabIcon(for: item)
                // Unread dot on the Workspace tab — DMs OR notifications,
                // reached from its header's Messages button.
                .overlay(alignment: .topTrailing) {
                    if item == .workspace, dependencies.inboxStore.inboxHasUnread {
                        Circle()
                            .fill(Color.vUnread)
                            .frame(width: 8, height: 8)
                            .offset(x: 2, y: -2)
                    }
                }
            Text(item.title)
                .font(.appCaption2Medium)
        }
        .foregroundStyle(selectedTab == item ? Color.vText : Color.vText3)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
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
        case .workspace:
            WorkspaceScreen()
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
        .environment(dependencies.libraryStore)
        .environment(dependencies.workspaceStore)
        .environment(dependencies.socialStore)
        .environment(dependencies.inboxStore)
        .environment(dependencies.listingsStore)
        .environment(dependencies.feedStore)
        .environment(dependencies.packsStore)
}

// MARK: - New post sheet

/// The New post picker as the app's standard option sheet: shared header,
/// icon rows with a caption, sized to its rows. Service / Pack only with the
/// marketplace on.
private struct NewPostSheet: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private struct Option: Identifiable {
        let id: String
        let icon: LucideIcon.Name
        let title: String
        let caption: String
    }

    private var options: [Option] {
        var list: [Option] = [
            .init(id: "track", icon: .music2, title: "Track", caption: "Upload audio or video"),
            .init(id: "release", icon: .layers, title: "Release", caption: "Upload several tracks as one release"),
            .init(id: "listing", icon: .megaphone, title: "Listing", caption: "Post a collab call"),
        ]
        if FeatureFlags.marketplaceSurfaces {
            list.append(.init(id: "service", icon: .briefcase, title: "Service", caption: "Offer mixing, features and more"))
            list.append(.init(id: "sample_pack", icon: .package, title: "Pack",
                              caption: "Sell samples or presets from Files or iCloud Drive"))
        } else if FeatureFlags.freePacks {
            list.append(.init(id: "sample_pack", icon: .package, title: "Pack",
                              caption: "Free samples or presets from Files or iCloud Drive"))
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .plus, title: "New post", subtitle: "What are you sharing?", prominent: true) { dismiss() }
            VStack(spacing: 0) {
                ForEach(options) { o in
                    OptionSheetRow(icon: o.icon, title: o.title, subtitle: o.caption) { onSelect(o.id) }
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .selfSizedDetent()
        .sheetBackground()
    }
}
