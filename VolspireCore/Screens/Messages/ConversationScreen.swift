//
//  ConversationScreen.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct ChatMessage: Identifiable {
    let id: String
    let text: String
    let isFromMe: Bool
    let time: String
}

struct ConversationScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""

    let contactName: String
    var onBack: (() -> Void)? = nil

    private let messages: [ChatMessage] = [
        ChatMessage(id: "1", text: "Hey! I just heard your new track", isFromMe: false, time: "10:30 AM"),
        ChatMessage(id: "2", text: "Thanks! Been working on it for weeks", isFromMe: true, time: "10:32 AM"),
        ChatMessage(id: "3", text: "The bass on it is insane 🔥", isFromMe: false, time: "10:33 AM"),
        ChatMessage(id: "4", text: "Would you be down to collab on something?", isFromMe: false, time: "10:33 AM"),
        ChatMessage(id: "5", text: "For sure! I've been wanting to try a new style", isFromMe: true, time: "10:35 AM"),
        ChatMessage(id: "6", text: "I can send you some stems to work with", isFromMe: true, time: "10:35 AM"),
        ChatMessage(id: "7", text: "That would be perfect", isFromMe: false, time: "10:36 AM"),
        ChatMessage(id: "8", text: "Let me know what BPM you're thinking", isFromMe: false, time: "10:36 AM"),
        ChatMessage(id: "9", text: "Probably around 140, trap-ish vibe", isFromMe: true, time: "10:38 AM"),
        ChatMessage(id: "10", text: "I love that, let's do it 💪", isFromMe: false, time: "10:39 AM"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(contactName)
                        .font(.system(size: 17, weight: .semibold))
                    Text("Online")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                }

                Spacer()

                Button {
                    // Call action
                } label: {
                    Image(systemName: "phone")
                        .font(.system(size: 18))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            // Messages
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        messageBubble(message)
                    }
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            Divider()

            // Input bar
            HStack(spacing: 12) {
                Button {
                    // Attach
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                TextField("Message...", text: $messageText)
                    .font(.system(size: 15))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Capsule())

                Button {
                    // Send
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(messageText.isEmpty ? Color(.systemGray3) : Color.brand)
                }
                .buttonStyle(.plain)
                .disabled(messageText.isEmpty)
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 8)
        }
        .gradientBackground()
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.isFromMe { Spacer(minLength: 60) }

            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 3) {
                Text(message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.isFromMe ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(message.isFromMe ? Color.brand : Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Text(message.time)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !message.isFromMe { Spacer(minLength: 60) }
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub
    ConversationScreen(contactName: "DJ Shadow")
        .withRouter()
        .environment(dependencies)
        .environment(playerController)
}
