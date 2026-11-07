//
//  ScreenHeader.swift
//  Volspire
//
//  The tab-root header bar (Library, Workspace): Settings' bar look — the
//  title centred in headline weight in a 44pt row under the status bar, on
//  the page colour, pinned while the page scrolls under it, with the
//  hairline appearing once it has scrolled — plus an optional trailing
//  icon action (the "+" for New).
//

import DesignSystem
import SwiftUI

struct ScreenHeader<Trailing: View>: View {
    let title: String
    /// Show the hairline (the page has scrolled under the bar).
    var scrolled = false
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, scrolled: Bool = false, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.scrolled = scrolled
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(Color.vText)
                .lineLimit(1)
                .padding(.horizontal, 64)
                .accessibilityAddTraits(.isHeader)
            // Icons sit close (their 42pt tap targets already space them).
            HStack(spacing: 2) {
                Spacer(minLength: 0)
                trailing()
            }
            .padding(.horizontal, ViewConst.screenPaddings - 9)
        }
        .frame(height: 44)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Color.vBase
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.vDivider).frame(height: 0.5)
                        .opacity(scrolled ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: scrolled)
                }
        }
    }
}

extension View {
    /// Reports whether the scroll has left the top (for the header hairline);
    /// writes only on change.
    func trackScrolledPastTop(_ scrolled: Binding<Bool>) -> some View {
        onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, value in
            if scrolled.wrappedValue != value { scrolled.wrappedValue = value }
        }
    }
}
