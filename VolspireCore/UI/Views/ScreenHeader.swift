//
//  ScreenHeader.swift
//  Volspire
//
//  The shared tab-root header: a large title on the left, optional action
//  icons on the right, over a bar that's a hair lighter than the page with a
//  soft dark bottom shadow so it reads as distinct chrome floating over the
//  scrolling content. Used by Library, Inbox (Messages) and Marketplace so
//  they stay identical.
//

import DesignSystem
import SwiftUI

struct ScreenHeader<Trailing: View, Expansion: View>: View {
    let title: String
    let trailing: Trailing
    /// Optional row(s) rendered below the title INSIDE the header chrome — the
    /// bar background extends behind them and the bottom shadow falls below
    /// them. Used for the revealed search field so it reads as part of the
    /// header instead of floating over the page content.
    let expansion: Expansion

    init(
        _ title: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder expansion: () -> Expansion = { EmptyView() }
    ) {
        self.title = title
        self.trailing = trailing()
        self.expansion = expansion()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text(title)
                    .font(.appLargeTitle)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                HStack(spacing: 10) { trailing }
            }
            .padding(.horizontal, ViewConst.screenPaddings)
            .padding(.top, 0)
            .padding(.bottom, 7)
            expansion
        }
        .background(Color(white: 0.07).ignoresSafeArea(edges: .top))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 5)
    }
}
