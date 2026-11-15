//
//  NotificationsScreen.swift
//  Volspire
//
//  Activity feed — mirrors the web app's notifications panel: a filter-chip
//  row, "New / Today / …" groups, flat rows (32pt actor avatar, the "@user
//  did X" sentence, quote / attachment previews, inline collab Accept /
//  Decline) with an unread dot in the left gutter. Pushed as a page.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct NotificationsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(InboxStore.self) private var inboxStore
    @Environment(SocialStore.self) private var socialStore
    @State private var viewModel = NotificationsScreenViewModel()
    @Environment(\.isActiveRootTab) private var isActiveRootTab
    /// Not covered by a pushed page (a row's destination) — reloading marks
    /// everything read, so it only happens while the list is actually seen.
    @State private var isOnScreen = false
    /// Activity arrived while covered / on another tab — reload on return.
    @State private var missedActivity = false
    private var isVisible: Bool { isOnScreen && isActiveRootTab }

    /// Clears the tab bar + (when present) the floating mini-player.
    private var bottomInset: CGFloat { playerController.contentBottomInset }

    /// This page instance's list entrance (see `staggeredAppear`).
    @State private var entranceKey = "notifications-\(UUID().uuidString)"

    var body: some View {
        ScrollView {
            content
                .loadingCrossfade(viewModel.loadingState)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: "Notifications", subtitle: newCaption) { dismiss() }
        .refreshable { await viewModel.refresh() }
        .task {
            // Opening this screen reads everything (`load` marks all read
            // server-side) — clear the bell dot (and badge share) optimistically.
            inboxStore.clearNotificationsDot()
            await viewModel.load()
        }
        // An activity push while this page is open — show the new row (load
        // marks it read) and keep the bell dot off.
        .onReceive(NotificationCenter.default.publisher(for: .pushReceived)) { note in
            guard note.userInfo?["convo_id"] == nil else { return }
            missedActivity = true
            catchUp()
        }
        .onAppear { isOnScreen = true; catchUp() }
        .onDisappear { isOnScreen = false }
        .onChange(of: isActiveRootTab) { _, _ in catchUp() }
    }

    /// Reloads (marking read) for activity that arrived — only while seen.
    private func catchUp() {
        guard isVisible, missedActivity else { return }
        missedActivity = false
        Task {
            await viewModel.load()
            inboxStore.clearNotificationsDot()
        }
    }

    /// "N new" under the title — the open-time unread snapshot.
    private var newCaption: String? {
        let n = viewModel.unreadSnapshot.count
        return n > 0 ? "\(n) new" : nil
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadingState {
        case .idle, .loading:
            loadingSkeleton
        case .error:
            LoadErrorView { Task { await viewModel.refresh() } }
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        case .loaded where viewModel.notifications.isEmpty:
            // My Network / Messages' empty treatment: animated ghost rows.
            HomeEmpty(title: "Nothing here yet", message: "Likes, follows, and comments will show up here.") {
                GhostNotificationRows()
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        case .loaded:
            LazyVStack(alignment: .leading, spacing: 0) {
                chipRow
                if let error = viewModel.respondError {
                    ErrorBanner(error)
                        .padding(.horizontal, ViewConst.screenPaddings)
                        .padding(.top, 8)
                }
                if viewModel.filtered.isEmpty {
                    VStack(spacing: 24) {
                        EmptyStateView(icon: .bell, title: "Nothing in this filter")
                        SecondaryButton("Show all", size: .inline, expands: false) { viewModel.filter = nil }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    ForEach(Array(viewModel.groups.enumerated()), id: \.element.id) { g, group in
                        sectionHeader(group.title)
                            .staggeredAppear(g, in: entranceKey)
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { i, item in
                            row(item)
                                .staggeredAppear(g + i + 1, in: entranceKey)
                        }
                    }
                }
            }
            .padding(.bottom, bottomInset)
        }
    }

    /// One scrolling chip row — All plus each category; tapping the active
    /// chip returns to All.
    private var chipRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                FilterChip("All", isOn: viewModel.filter == nil) { viewModel.filter = nil }
                ForEach(NotificationCategory.visible) { category in
                    FilterChip(category.label, isOn: viewModel.filter == category) {
                        viewModel.filter = viewModel.filter == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
        }
        .scrollIndicators(.hidden)
        .padding(.vertical, 8)
    }

    /// Shimmering placeholder that mirrors the notification row (avatar + two
    /// text lines + trailing time) — consistent with the app's other skeletons.
    private var loadingSkeleton: some View {
        SkeletonRows(
            count: 7,
            thumb: .circle(size: 32),
            line1: CGSize(width: 210, height: 12),
            line2: CGSize(width: 120, height: 10),
            trailing: CGSize(width: 30, height: 10),
            rowAlignment: .top,
            thumbSpacing: 12,
            horizontalPadding: 20,
            verticalPadding: 12
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.appLabel)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    // MARK: Row

    private func row(_ item: ApiNotification) -> some View {
        let m = meta(for: item.action ?? "")
        let isUnread = viewModel.unreadSnapshot.contains(item.id)
        let sessionAnswer = item.actor?.userId.flatMap {
            socialStore.collabAnswer(from: $0, after: MessageTime.parse(item.createdAt))
        }
        let pendingRequest = viewModel.isPendingCollabRequest(item, sessionAnswer: sessionAnswer)

        return HStack(alignment: .top, spacing: 12) {
            avatar(item, meta: m)
                // The row routes to the OBJECT (track/folder/listing); the
                // avatar keeps the actor's profile reachable.
                .onTapGesture {
                    if let userId = item.actor?.userId {
                        router.navigateToProfile(userId: userId)
                    } else {
                        navigate(item)
                    }
                }

            VStack(alignment: .leading, spacing: 0) {
                messageText(item, meta: m, isUnread: isUnread)
                    .fixedSize(horizontal: false, vertical: true)

                if let preview = item.contextPreview, !preview.isEmpty {
                    previewLine(item, text: preview)
                        .padding(.top, 6)
                }

                if pendingRequest {
                    HStack(spacing: 8) {
                        SecondaryButton("Decline", icon: .x, size: .inline, expands: false) {
                            respond(item, accept: false)
                        }
                        .disabled(viewModel.isResponding(item))
                        PrimaryButton("Accept", icon: .check, size: .inline, expands: false, busy: viewModel.isResponding(item)) {
                            respond(item, accept: true)
                        }
                    }
                    .padding(.top, 10)
                } else if let result = viewModel.collabResult(item, sessionAnswer: sessionAnswer) {
                    Text(result == "accepted" ? "Accepted" : result == "declined" ? "Declined" : "Already answered")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .padding(.top, 8)
                }
            }

            Spacer(minLength: 8)

            Text(viewModel.timeAgo(item.createdAt))
                .font(.appCaption)
                .foregroundStyle(Color.vText3)
                .monospacedDigit()
                .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        // Unread: a dot in the left gutter — no row tint.
        .overlay(alignment: .topLeading) {
            if isUnread {
                Circle().fill(Color.vUnread).frame(width: 6, height: 6)
                    .offset(x: 8, y: 17)
            }
        }
        .contentShape(.rect)
        // Accept / Decline are buttons and keep their own taps.
        .onTapGesture { navigate(item) }
    }

    private func respond(_ item: ApiNotification, accept: Bool) {
        Task {
            guard await viewModel.respond(to: item, accept: accept),
                  let actorId = item.actor?.userId else { return }
            // Keep any mounted profile / thread / inbox bucket in step.
            socialStore.recordCollabAnswer(accepted: accept, from: actorId)
            let convo = await inboxStore.dmConversation(with: actorId)
            if let convo {
                inboxStore.requestStatusChanged(convoId: convo.id, status: accept ? "accepted" : "rejected")
            }
            socialStore.setCollabStatus(accept ? "accepted" : "none", userId: actorId, convoId: accept ? convo?.id : nil)
        }
    }

    /// What someone wrote reads as a quote (2pt rule, italic); anything else
    /// is the name of the thing acted on, as a small attachment line.
    @ViewBuilder
    private func previewLine(_ item: ApiNotification, text: String) -> some View {
        let quoteActions: Set<String> = ["commented", "commented on file", "listing_response", "requested collaboration"]
        if quoteActions.contains(item.action ?? "") {
            Text(text)
                .font(.appSubheadline)
                .italic()
                .foregroundStyle(Color.vText2)
                .lineLimit(2)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.ink(0.12)).frame(width: 2)
                }
        } else {
            HStack(spacing: 8) {
                LucideIcon(item.action == "uploaded file" ? .fileText : .music2, .sm)
                    .foregroundStyle(Color.vText3)
                Text(text)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.vText2)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func avatar(_ item: ApiNotification, meta: ActionMeta) -> some View {
        if item.actor?.username == nil, item.actor?.profileImageUrl == nil {
            // System notice (moderation): no actor — a neutral glyph puck.
            LucideIcon(meta.icon, .md)
                .foregroundStyle(Color.vText2)
                .frame(width: 32, height: 32)
                .background(Color.vSurface, in: Circle())
        } else {
            AvatarView(urlString: item.actor?.profileImageUrl, name: item.actor?.username, size: 32)
        }
    }

    /// "@user [and N others] did X [object]" — composed like the web's row copy.
    private func messageText(_ item: ApiNotification, meta: ActionMeta, isUnread: Bool) -> Text {
        func run(_ string: String, _ font: Font, _ color: Color) -> AttributedString {
            var run = AttributedString(string)
            run.font = font
            run.foregroundColor = color
            return run
        }

        let strong = isUnread ? Color.vText : Color.vTextRow
        var result = AttributedString()
        if let username = item.actor?.username {
            result += run("@\(username)", .appSubheadlineSemibold, strong)
            let count = item.actionCount ?? 1
            if count > 1 {
                result += run(" and \(count - 1) \(count == 2 ? "other" : "others")", .appSubheadline, Color.vText2)
            }
            result += run(" ", .appSubheadline, Color.vText2)
        }
        result += run(displayLabel(item, meta: meta), .appSubheadline, Color.vText2)
        if let title = item.objectTitle, !title.isEmpty {
            result += run(" \(title)", .appSubheadlineMedium, strong)
        }
        return Text(result)
    }

    // MARK: Action metadata (mirrors the web's actionMeta map)

    private struct ActionMeta {
        let label: String
        let icon: LucideIcon.Name
        let tint: Color
    }

    private func meta(for action: String) -> ActionMeta {
        switch action {
        case "followed":                 return .init(label: "followed you", icon: .userCheck, tint: .blue)
        case "liked":                    return .init(label: "liked your track", icon: .heart, tint: .pink)
        case "saved":                    return .init(label: "saved your track", icon: .bookmark, tint: Color.vText3)
        case "commented":                return .init(label: "commented on", icon: .messageCircle, tint: .purple)
        case "shared":                   return .init(label: "shared your track", icon: .share2, tint: .green)
        case "purchased":                return .init(label: "purchased your track", icon: .shoppingCart, tint: .orange)
        case "uploaded":                 return .init(label: "uploaded a new track", icon: .music, tint: Color.vText3)
        case "requested collaboration":  return .init(label: "requested to collaborate", icon: .handshake, tint: .cyan)
        case "accepted collaboration":   return .init(label: "accepted your collaboration request", icon: .circleCheck, tint: .green)
        case "credited":                 return .init(label: "credited you on", icon: .users, tint: .cyan)
        case "shared folder":            return .init(label: "shared a folder with you:", icon: .folder, tint: .orange)
        case "added to folder":          return .init(label: "added a track to", icon: .music, tint: .cyan)
        case "uploaded file":            return .init(label: "uploaded a file to", icon: .music, tint: .cyan)
        case "commented on file":        return .init(label: "commented on a file in", icon: .messageCircle, tint: .purple)
        case "listing_response":         return .init(label: "responded to your listing", icon: .megaphone, tint: .cyan)
        // Moderation notices ("track under review" / "listing hidden" / …) —
        // actor-less system rows; the label reads as a full sentence since
        // there's no "@name" prefix, and the object title follows in white.
        case let a where a.hasSuffix(" under review"):
            return .init(label: "Your \(Self.noun(a)) is under review:", icon: .flag, tint: .orange)
        case let a where a.hasSuffix(" hidden"):
            return .init(label: "Your \(Self.noun(a)) was hidden for violating our guidelines:", icon: .ban, tint: .orange)
        case let a where a.hasSuffix(" removed"):
            return .init(label: "Your \(Self.noun(a)) was removed for violating our guidelines:", icon: .ban, tint: .red)
        case let a where a.hasSuffix(" restored"):
            return .init(label: "Your \(Self.noun(a)) is back up:", icon: .circleCheck, tint: .green)
        default:                         return .init(label: action.replacingOccurrences(of: "_", with: " "), icon: .bell, tint: Color.vText3)
        }
    }

    /// "track under review" → "track" (the content noun of a moderation action).
    private static func noun(_ action: String) -> String {
        action.split(separator: " ").first.map(String.init) ?? "content"
    }

    /// The liked/saved/shared/purchased labels name the content — resolve the
    /// noun from `object_type` so an action on a listing/pack/service doesn't
    /// read as "your track" (the meta table's labels are track-flavored defaults).
    private func displayLabel(_ item: ApiNotification, meta: ActionMeta) -> String {
        let noun: String
        switch item.objectType {
        case "listing": noun = "listing"
        case "pack":    noun = "pack"
        case "service": noun = "service"
        case "folder":  noun = "folder"
        default:        noun = "track"
        }
        switch item.action {
        case "purchased":
            return item.objectType == "service" ? "booked your service" : "purchased your \(noun)"
        case "liked":  return "liked your \(noun)"
        case "saved":  return "saved your \(noun)"
        case "shared": return "shared your \(noun)"
        default:       return meta.label
        }
    }

    // MARK: Navigation

    /// Routes by the notification's OBJECT first — a track notification opens
    /// the track, not the liker's profile (the actor's profile stays reachable
    /// via the avatar). Actor-profile is the fallback for object-less rows
    /// (e.g. "followed you").
    private func navigate(_ item: ApiNotification) {
        if Self.collabActions.contains(item.action ?? ""), let actorId = item.actor?.userId {
            openCollabThread(with: actorId)
        } else if item.objectType == "folder", let folderId = item.objectId {
            // Point at the item the activity is about, like a tapped comment.
            let highlight: FolderHighlight? = item.contextId.flatMap { id in
                switch item.contextType {
                case "file": .file(id)
                case "track": .track(id)
                case "file_comment": .fileComment(id)
                default: nil
                }
            }
            router.navigateToFolder(folderId: folderId, folderName: item.objectTitle ?? "Folder", highlight: highlight)
        } else if item.objectType == "track", let id = item.objectId {
            // Notifications are about YOUR OWN content — open the track in the
            // player (same machinery as the post-publish reveal / push taps).
            NotificationCenter.default.post(name: .openOwnPost, object: nil, userInfo: ["trackId": id])
        } else if item.objectType == "listing", let id = item.objectId {
            NotificationCenter.default.post(name: .openOwnPost, object: nil, userInfo: ["listingId": id])
        } else if let userId = item.actor?.userId {
            router.navigateToProfile(userId: userId)
        }
    }

    /// Collab request / acceptance rows open the pair's DM, where the
    /// request card lives.
    private static let collabActions: Set<String> = ["requested collaboration", "accepted collaboration"]

    private func openCollabThread(with userId: String) {
        Task {
            if let convo = await inboxStore.dmConversation(with: userId) {
                router.navigateToConversation(ActiveConversation(
                    convoId: convo.id,
                    otherUserId: convo.otherUserId,
                    username: convo.username,
                    avatarURL: convo.avatarURL?.absoluteString
                ))
            } else {
                router.navigateToProfile(userId: userId)
            }
        }
    }

    private func emptyState(icon: LucideIcon.Name, title: String, message: String) -> some View {
        EmptyStateView(icon: icon, title: title, message: message)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    NotificationsScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
        .environment(dependencies.inboxStore)
        .environment(dependencies.socialStore)
}
