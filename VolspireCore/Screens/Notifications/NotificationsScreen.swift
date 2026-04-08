//
//  NotificationsScreen.swift
//  Volspire
//
//

import DesignSystem
import Kingfisher
import Services
import SwiftUI

struct NotificationsScreen: View {
    @Environment(Router.self) var router
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = NotificationsScreenViewModel()

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

                switch viewModel.loadingState {
                case .idle, .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                case .error(let message):
                    ContentUnavailableView(
                        "Something went wrong",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                case .loaded where viewModel.notifications.isEmpty:
                    ContentUnavailableView(
                        "No Notifications",
                        systemImage: "bell.slash",
                        description: Text("You're all caught up")
                    )
                case .loaded:
                    ForEach(viewModel.notifications) { item in
                        notificationRow(item)
                        if item.id != viewModel.notifications.last?.id {
                            Divider()
                                .padding(.leading, 68)
                                .padding(.horizontal, ViewConst.screenPaddings)
                        }
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .gradientBackground()
        .task {
            await viewModel.loadNotifications()
        }
    }

    private func notificationRow(_ item: ApiNotification) -> some View {
        let iconName = viewModel.icon(for: item)
        let color = colorFor(item)

        return HStack(alignment: .top, spacing: 14) {
            if let imageUrl = item.actor?.profileImageUrl, let url = URL(string: imageUrl) {
                KFImage(url)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
            } else {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 40, height: 40)

                    Image(systemName: iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(viewModel.title(for: item))
                        .font(.system(size: 15, weight: item.isRead ? .regular : .semibold))
                    Spacer()
                    Text(viewModel.relativeTime(from: item.createdAt))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text(viewModel.subtitle(for: item))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !item.isRead {
                Circle()
                    .fill(Color.brand)
                    .frame(width: 8, height: 8)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 12)
        .background(item.isRead ? Color.clear : Color.brand.opacity(0.04))
        .contentShape(.rect)
    }

    private func colorFor(_ item: ApiNotification) -> Color {
        switch viewModel.iconColor(for: item) {
        case "blue": return .blue
        case "pink": return .pink
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "yellow": return .yellow
        default: return .gray
        }
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
