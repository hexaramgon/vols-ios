//
//  ProfileTabBar.swift
//  Volspire
//
//  Icon tabs (so Tracks / Featured On / Listings / Marketplace fit), spread
//  evenly across the bar, styled like Home's band: the active one ink,
//  inactive vText3, and a 48×4 ink bar sitting on the hairline that slides to
//  the tapped tab while the glyphs fade. Each keeps its name for VoiceOver.
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
            LucideIcon(tab.icon, .xl)
                .foregroundStyle(active ? Color.vText : Color.vText3)
                .padding(.vertical, 14)
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
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected == tab ? .isSelected : [])
    }
}
