//
//  MessageCategoryScreen.swift
//  Volspire
//
//  A single inbox category (Orders, Inquiries, …) as a pushed page — the same
//  `appNavBar` + scrolling list pattern as every other pushed screen, so the
//  header chrome (bar, back chevron, title) comes from the shared AppNavBar.
//
//  Rows derive LIVE from the shared InboxStore by bucket key (the route used
//  to carry a value snapshot, which went stale the moment you acted on a
//  request inside the folder).
//

import DesignSystem
import SwiftUI

struct MessageCategoryScreen: View {
    let title: String
    let bucket: MessageBucket
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(InboxStore.self) private var inboxStore

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    private var items: [ConversationItem] { inboxStore.conversations.bucket(bucket) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if items.isEmpty {
                    EmptyStateView(icon: .messageCircle, title: "Nothing here")
                        .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
                } else {
                    ForEach(items) { ConversationRow(item: $0) }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, bottomInset)
            .animation(.easeInOut(duration: 0.25), value: items)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: title) { dismiss() }
    }
}
