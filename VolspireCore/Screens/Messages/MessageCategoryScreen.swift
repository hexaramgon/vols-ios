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
    /// This page instance's list entrance (see `staggeredAppear`).
    @State private var entranceKey = "messageCategory-\(UUID().uuidString)"
    let title: String
    let bucket: MessageBucket
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @Environment(InboxStore.self) private var inboxStore

    private var bottomInset: CGFloat { playerController.contentBottomInset }

    private var items: [ConversationItem] { inboxStore.conversations.bucket(bucket) }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if items.isEmpty {
                    InboxEmptyState(title: "Nothing here yet", message: nil, compact: true)
                        .frame(maxWidth: .infinity, minHeight: UIScreen.size.height * 0.6)
                } else {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ConversationRow(item: item)
                            .staggeredAppear(index, in: entranceKey)
                    }
                }
            }
            .padding(.bottom, bottomInset)
            .animation(.easeInOut(duration: 0.25), value: items)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: title) { dismiss() }
    }
}
