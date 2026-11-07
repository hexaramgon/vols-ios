//
//  ConversationRow.swift
//  Volspire
//
//  A single conversation thread row — avatar, name, time, last-message
//  preview, unread dot. Shared by the inbox (MessagesScreen) and the
//  per-category list (MessageCategoryScreen). Tapping opens the conversation.
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
                AvatarView(url: item.avatarURL, name: item.username, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(item.username)
                            .font(item.hasUnread ? .appCalloutSemibold : .appCallout)
                            .foregroundStyle(item.hasUnread ? Color.vText : Color.vTextRow)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(MessageTime.ago(item.lastMessageAt))
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .monospacedDigit()
                    }
                    HStack(spacing: 6) {
                        Text(item.preview)
                            .font(.appSubheadline)
                            .foregroundStyle(item.hasUnread ? Color.vText : Color.vText3)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if item.hasUnread {
                            // Red unread dot (the app's shared unread colour).
                            Circle().fill(Color.vUnread).frame(width: 8, height: 8)
                        }
                    }
                }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(RowHighlightButtonStyle(cornerRadius: 0))
    }
}
