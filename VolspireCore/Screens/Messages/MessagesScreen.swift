//
//  MessagesScreen.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct MessageThread: Identifiable {
    let id: String
    let name: String
    let avatarInitials: String
    let avatarColor: Color
    let lastMessage: String
    let time: String
    let unreadCount: Int
    let isOnline: Bool
}

struct MessagesScreen: View {
    @Environment(Router.self) var router
    @Environment(ConversationState.self) var conversationState
    @Environment(\.dismiss) private var dismiss

    private let threads: [MessageThread] = [
        MessageThread(id: "1", name: "DJ Shadow", avatarInitials: "DS", avatarColor: .purple, lastMessage: "Yo that beat is crazy, can we collab?", time: "2m", unreadCount: 3, isOnline: true),
        MessageThread(id: "2", name: "ProducerX", avatarInitials: "PX", avatarColor: .blue, lastMessage: "Sent you the stems for the remix", time: "15m", unreadCount: 1, isOnline: true),
        MessageThread(id: "3", name: "Aria Keys", avatarInitials: "AK", avatarColor: .pink, lastMessage: "Love the new track! When's it dropping?", time: "1h", unreadCount: 0, isOnline: false),
        MessageThread(id: "4", name: "BeatSmith", avatarInitials: "BS", avatarColor: .orange, lastMessage: "Check out this sample pack I made", time: "3h", unreadCount: 0, isOnline: true),
        MessageThread(id: "5", name: "Vox Studio", avatarInitials: "VS", avatarColor: .green, lastMessage: "Session booked for Thursday at 4pm", time: "5h", unreadCount: 0, isOnline: false),
        MessageThread(id: "6", name: "Luna Waves", avatarInitials: "LW", avatarColor: .teal, lastMessage: "Thanks for the feedback on the mix!", time: "8h", unreadCount: 0, isOnline: false),
        MessageThread(id: "7", name: "Mike Masters", avatarInitials: "MM", avatarColor: .red, lastMessage: "Mastering is done, sending it over now", time: "1d", unreadCount: 0, isOnline: false),
        MessageThread(id: "8", name: "Rhythm Lab", avatarInitials: "RL", avatarColor: .indigo, lastMessage: "New drum kit just dropped 🔥", time: "2d", unreadCount: 0, isOnline: false),
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

                    Text("Messages")
                        .font(.system(size: 26, weight: .semibold))
                    Spacer()

                    Button {
                        // New message
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 8)
                .padding(.bottom, 16)

                ForEach(threads) { thread in
                    threadRow(thread)
                    if thread.id != threads.last?.id {
                        Divider()
                            .padding(.leading, 76)
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

    private func threadRow(_ thread: MessageThread) -> some View {
        Button {
            conversationState.open(name: thread.name)
        } label: {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(thread.avatarColor)
                        .frame(width: 50, height: 50)

                    Text(thread.avatarInitials)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                if thread.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(thread.name)
                        .font(.system(size: 15, weight: thread.unreadCount > 0 ? .semibold : .regular))
                    Spacer()
                    Text(thread.time)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Text(thread.lastMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(thread.unreadCount > 0 ? .primary : .secondary)
                    .lineLimit(1)
            }

            if thread.unreadCount > 0 {
                Text("\(thread.unreadCount)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Color.brand)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.vertical, 10)
        .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    MessagesScreen()
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
