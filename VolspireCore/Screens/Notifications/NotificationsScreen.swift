//
//  NotificationsScreen.swift
//  Volspire
//
//  Activity feed — mirrors the web app's notifications panel (actor avatar +
//  action badge, rich "@user did X" copy, unread highlight), pushed as a page.
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct NotificationsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(UnreadCounts.self) private var unreadCounts
    @State private var viewModel = NotificationsScreenViewModel()

    /// Clears the tab bar + (when present) the floating mini-player.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: "Notifications") { dismiss() }
        .refreshable { await viewModel.refresh() }
        .task {
            // Opening this screen reads everything (`load` marks all read
            // server-side) — clear the bell dot optimistically.
            unreadCounts.clearNotifications()
            await viewModel.load()
        }
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
            emptyState(icon: .bell, title: "No notifications yet", message: "You're all caught up")
                .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
        case .loaded:
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(viewModel.groups) { group in
                    sectionHeader(group.title)
                    ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                        row(item, isLast: idx == group.items.count - 1)
                    }
                }
            }
            .padding(.bottom, bottomInset)
        }
    }

    /// Shimmering placeholder that mirrors the notification row (avatar + two
    /// text lines + trailing time) — consistent with the app's other skeletons.
    private var loadingSkeleton: some View {
        let bone = Color.white.opacity(0.08)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0 ..< 8, id: \.self) { _ in
                HStack(alignment: .top, spacing: 12) {
                    Circle().fill(bone).frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        Capsule().fill(bone).frame(width: 210, height: 13)
                        Capsule().fill(bone).frame(width: 120, height: 11)
                    }
                    Spacer(minLength: 8)
                    Capsule().fill(bone).frame(width: 30, height: 10)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .shimmering()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.appFont.sectionLabel)
            .tracking(0.6)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    // MARK: Row

    private func row(_ item: ApiNotification, isLast: Bool) -> some View {
        let m = meta(for: item.action ?? "")
        let isUnread = viewModel.unreadSnapshot.contains(item.id)

        return HStack(alignment: .top, spacing: 12) {
            avatar(item, meta: m)

            VStack(alignment: .leading, spacing: 3) {
                messageText(item, meta: m)
                    .fixedSize(horizontal: false, vertical: true)

                if let preview = item.contextPreview, !preview.isEmpty {
                    Text("“\(preview)”")
                        .font(.appCaption)
                        .foregroundStyle(Color.vText3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 7) {
                Text(viewModel.timeAgo(item.createdAt))
                    .font(.appCaption2Medium)
                    .foregroundStyle(Color.vText3)
                    .fixedSize()
                if isUnread {
                    Circle().fill(Color.vUnread).frame(width: 8, height: 8)
                }
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 14)
        .background(isUnread ? Color.white.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 0.5)
                    .padding(.leading, ViewConst.screenPaddings + 56) // under the message (avatar 44 + spacing 12)
            }
        }
        .contentShape(.rect)
        .onTapGesture { navigate(item) }
    }

    @ViewBuilder
    private func avatar(_ item: ApiNotification, meta: ActionMeta) -> some View {
        if item.actor?.username == nil, item.actor?.profileImageUrl == nil {
            // System notice (moderation): no actor — the action icon is the avatar.
            ZStack {
                Circle().fill(Color.vSurface)
                Circle().fill(meta.tint.opacity(0.16))
                LucideIcon(meta.icon, .lg).foregroundStyle(meta.tint)
            }
            .frame(width: 44, height: 44)
        } else {
            ZStack(alignment: .bottomTrailing) {
                AvatarView(urlString: item.actor?.profileImageUrl, name: item.actor?.username, size: 44)

                ZStack {
                    Circle().fill(Color.vBase)
                    Circle().fill(meta.tint.opacity(0.30))
                    LucideIcon(meta.icon, .xs).foregroundStyle(meta.tint)
                }
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.vBase, lineWidth: 2))
                .offset(x: 4, y: 4)
            }
        }
    }

    /// "@user [and N others] did X [object]" — composed like the web's row copy.
    private func messageText(_ item: ApiNotification, meta: ActionMeta) -> Text {
        func run(_ string: String, _ font: Font, _ color: Color) -> AttributedString {
            var run = AttributedString(string)
            run.font = font
            run.foregroundColor = color
            return run
        }

        var result = AttributedString()
        if let username = item.actor?.username {
            result += run("@\(username)", .appFootnoteSemibold, .white)
            let count = item.actionCount ?? 1
            if count > 1 {
                result += run(" and \(count - 1) \(count == 2 ? "other" : "others")", .appFootnote, Color.vText2)
            }
            result += run(" ", .appFootnote, Color.vText2)
        }
        result += run(displayLabel(item, meta: meta), .appFootnote, Color.vText2)
        if let title = item.objectTitle, !title.isEmpty {
            result += run(" \(title)", .appFootnoteMedium, .white)
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
        case "saved":                    return .init(label: "saved your track", icon: .bookmark, tint: Color(white: 0.6))
        case "commented":                return .init(label: "commented on", icon: .messageCircle, tint: .purple)
        case "shared":                   return .init(label: "shared your track", icon: .share2, tint: .green)
        case "purchased":                return .init(label: "purchased your track", icon: .shoppingCart, tint: .orange)
        case "uploaded":                 return .init(label: "uploaded a new track", icon: .music, tint: Color(white: 0.6))
        case "requested collaboration":  return .init(label: "requested to collaborate", icon: .handshake, tint: .cyan)
        case "accepted collaboration":   return .init(label: "accepted your collaboration request", icon: .circleCheck, tint: .green)
        case "credited":                 return .init(label: "credited you on", icon: .users, tint: .cyan)
        case "shared folder":            return .init(label: "shared a folder with you:", icon: .folder, tint: .orange)
        case "added to folder":          return .init(label: "added a track to", icon: .music, tint: .cyan)
        case "uploaded file":            return .init(label: "uploaded a file to", icon: .music, tint: .cyan)
        case "commented on file":        return .init(label: "commented on a file in", icon: .messageCircle, tint: .purple)
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
        default:                         return .init(label: action.replacingOccurrences(of: "_", with: " "), icon: .bell, tint: Color(white: 0.6))
        }
    }

    /// "track under review" → "track" (the content noun of a moderation action).
    private static func noun(_ action: String) -> String {
        action.split(separator: " ").first.map(String.init) ?? "content"
    }

    /// Purchases carry the real product type in `object_type`; relabel so packs
    /// and services don't read as "purchased your track".
    private func displayLabel(_ item: ApiNotification, meta: ActionMeta) -> String {
        guard item.action == "purchased" else { return meta.label }
        switch item.objectType {
        case "pack":    return "purchased your pack"
        case "service": return "booked your service"
        default:        return "purchased your track"
        }
    }

    // MARK: Navigation

    private func navigate(_ item: ApiNotification) {
        if item.objectType == "folder", let folderId = item.objectId {
            router.navigateToFolder(folderId: folderId, folderName: item.objectTitle ?? "Folder")
        } else if let userId = item.actor?.userId {
            router.navigateToProfile(userId: userId)
        } else if item.objectType == "track", let id = item.objectId {
            // System notice (moderation) — open your own track in the player
            // (same machinery as the post-publish reveal).
            NotificationCenter.default.post(name: .openOwnPost, object: nil, userInfo: ["trackId": id])
        } else if item.objectType == "listing", let id = item.objectId {
            NotificationCenter.default.post(name: .openOwnPost, object: nil, userInfo: ["listingId": id])
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
}
