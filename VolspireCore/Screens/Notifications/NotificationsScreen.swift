//
//  NotificationsScreen.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct NotificationItem: Identifiable {
    let id: String
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let time: String
    let isUnread: Bool
}

struct NotificationsScreen: View {
    @Environment(Router.self) var router

    @Environment(\.dismiss) private var dismiss

    private let notifications: [NotificationItem] = [
        NotificationItem(id: "1", icon: "person.fill.badge.plus", iconColor: .blue, title: "New Follower", subtitle: "DJ Shadow started following you", time: "2m ago", isUnread: true),
        NotificationItem(id: "2", icon: "heart.fill", iconColor: .pink, title: "Track Liked", subtitle: "Midnight Drive was liked by 12 people", time: "15m ago", isUnread: true),
        NotificationItem(id: "3", icon: "bubble.left.fill", iconColor: .green, title: "New Comment", subtitle: "\"Fire beat! Can I use this?\" on Lo-Fi Session", time: "1h ago", isUnread: true),
        NotificationItem(id: "4", icon: "arrow.down.circle.fill", iconColor: .purple, title: "Download Complete", subtitle: "Summer EP - Master.wav is ready", time: "2h ago", isUnread: false),
        NotificationItem(id: "5", icon: "music.note", iconColor: .orange, title: "New Release", subtitle: "An artist you follow dropped a new track", time: "3h ago", isUnread: false),
        NotificationItem(id: "6", icon: "star.fill", iconColor: .yellow, title: "Featured", subtitle: "Your track was added to Trending Now", time: "5h ago", isUnread: false),
        NotificationItem(id: "7", icon: "person.2.fill", iconColor: .blue, title: "Collab Request", subtitle: "ProducerX wants to collaborate with you", time: "8h ago", isUnread: false),
        NotificationItem(id: "8", icon: "heart.fill", iconColor: .pink, title: "Track Liked", subtitle: "Beat Sketch 17 was liked by 5 people", time: "1d ago", isUnread: false),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: 14) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Text("Notifications")
                        .font(.system(size: 26, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 8)
                .padding(.bottom, 16)

                ForEach(notifications) { item in
                    notificationRow(item)
                    if item.id != notifications.last?.id {
                        Divider()
                            .padding(.leading, 68)
                            .padding(.horizontal, ViewConst.screenPaddings)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .gradientBackground()
    }

    private func notificationRow(_ item: NotificationItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(item.iconColor.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: item.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(item.iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.title)
                        .font(.system(size: 15, weight: item.isUnread ? .semibold : .regular))
                    Spacer()
                    Text(item.time)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text(item.subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if item.isUnread {
                Circle()
                    .fill(Color.brand)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 12)
        .background(item.isUnread ? Color.brand.opacity(0.04) : Color.clear)
        .contentShape(.rect)
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
