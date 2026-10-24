//
//  ProfileTabBar.swift
//  Volspire
//
//  Text tabs without counts, spread evenly across the bar, styled like Home's
//  Collab / Listings / My Network band: the active one ink + bold, inactive
//  medium @ vText3, and a 48×4 ink bar sitting on the hairline that slides to
//  the tapped tab while the labels fade.
//
//  The content below crossfades (opacity only); the bar keeps its own copy of
//  the selection so the underline slides however the switch is triggered.
//

import DesignSystem
import SwiftUI

struct ProfileTabBar: View {
    let tabs: [ProfileTab]
    let selected: ProfileTab
    let onSelect: (ProfileTab) -> Void

    @Namespace private var underline
    /// The bar's own copy of `selected`, moved inside an animation so the
    /// underline slides even though the screen switches without one.
    @State private var shown: ProfileTab?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .background(alignment: .bottom) { Rectangle().fill(Color.vDivider).frame(height: 1) }
        .background(Color.vBase)
        .onAppear { shown = selected }
        .onChange(of: selected) { _, tab in
            withAnimation(.smooth(duration: 0.3)) { shown = tab }
        }
    }

    private func tabButton(_ tab: ProfileTab) -> some View {
        let active = (shown ?? selected) == tab
        return Button { onSelect(tab) } label: {
            Text(tab.title)
                .font(active ? .appSubheadlineBold : .appSubheadlineMedium)
                .foregroundStyle(active ? Color.vText : Color.vText3)
                .lineLimit(1)
                .padding(.vertical, 16)
                // Evenly spaced: each tab takes an equal share of the bar.
                .frame(maxWidth: .infinity)
                .overlay(alignment: .bottom) {
                    if active {
                        Capsule().fill(Color.vInverse).frame(width: 48, height: 4)
                            .matchedGeometryEffect(id: "underline", in: underline)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == tab ? .isSelected : [])
    }
}
