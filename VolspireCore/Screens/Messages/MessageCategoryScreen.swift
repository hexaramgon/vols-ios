//
//  MessageCategoryScreen.swift
//  Volspire
//
//  A single inbox category (Orders, Inquiries, …) as a pushed page — the same
//  `appNavBar` + scrolling list pattern as every other pushed screen, so the
//  header chrome (bar, back chevron, title) comes from the shared AppNavBar.
//

import DesignSystem
import SwiftUI

struct MessageCategoryScreen: View {
    let title: String
    let items: [ConversationItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController

    private var bottomInset: CGFloat { playerController.contentBottomInset }

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
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: title) { dismiss() }
    }
}
