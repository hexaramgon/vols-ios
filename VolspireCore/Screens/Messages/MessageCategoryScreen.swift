//
//  MessageCategoryScreen.swift
//  Volspire
//
//  A single inbox category (Orders, Inquiries, …) as a pushed page — the same
//  `appNavBar` + scrolling list pattern as every other pushed screen, so the
//  grey header, back chevron and slide animation are all system-handled.
//

import DesignSystem
import SwiftUI

struct MessageCategoryScreen: View {
    let title: String
    let items: [ConversationItem]
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController

    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if items.isEmpty {
                    VStack(spacing: 10) {
                        LucideIcon(.messageCircle, .hero).foregroundStyle(Color.vText3)
                        Text("Nothing here").font(.appTitle3).foregroundStyle(.white)
                    }
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
