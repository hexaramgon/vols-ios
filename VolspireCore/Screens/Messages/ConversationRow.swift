//
//  ConversationRow.swift
//  Volspire
//
//  A single conversation thread row — avatar, name, last-message preview, unread
//  dot. Shared by the inbox (MessagesScreen) and the per-category list
//  (MessageCategoryScreen). Tapping opens the conversation.
//

import DesignSystem
import Kingfisher
import SwiftUI

struct ConversationRow: View {
    let item: ConversationItem
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.navigateToConversation(ActiveConversation(
                convoId: item.id,
                otherUserId: item.otherUserId,
                username: item.username,
                avatarURL: item.avatarURL?.absoluteString
            ))
        } label: {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(item.username)
                            .font(item.hasUnread ? .appCalloutSemibold : .appCallout)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(MessageTime.ago(item.lastMessageAt))
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .monospacedDigit()
                    }
                    HStack(spacing: 6) {
                        Text(item.preview)
                            .font(.appFootnote)
                            .foregroundStyle(item.hasUnread ? .white.opacity(0.9) : Color.vText3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if item.hasUnread {
                            // One dot color app-wide (the web's row dots are white,
                            // but iOS standardizes every unread dot on vUnread).
                            Circle().fill(Color.vUnread).frame(width: 7, height: 7)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle())
    }

    private var avatar: some View {
        Group {
            if let url = item.avatarURL {
                KFImage(url).downsampled(to: 46).resizable().scaledToFill()
            } else {
                Text(String(item.username.first ?? "?").uppercased())
                    .font(.appBodyLargeSemibold)
                    .foregroundStyle(Color.vText2)
            }
        }
        .frame(width: 46, height: 46)
        .background(Color.vSurface)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.vBorder))
    }
}
