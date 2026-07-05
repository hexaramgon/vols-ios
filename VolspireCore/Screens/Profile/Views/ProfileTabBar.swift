//
//  ProfileTabBar.swift
//  Volspire
//
//  Equal-width text tabs with a label-width underline that slides + resizes
//  between tabs via matchedGeometry.
//

import DesignSystem
import SwiftUI

struct ProfileTabBar: View {
    let tabs: [ProfileTab]
    let selected: ProfileTab
    let onSelect: (ProfileTab) -> Void

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.top, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }
        .background(Color.vBase)
    }

    private func tabButton(_ tab: ProfileTab) -> some View {
        let active = selected == tab
        return Button { onSelect(tab) } label: {
            VStack(spacing: 10) {
                LucideIcon(icon(for: tab), .xl)
                    .foregroundStyle(active ? .white : Color.vText3)
                    .frame(maxWidth: .infinity)
                ZStack {
                    Capsule().fill(.clear).frame(height: 2.5)
                    if active {
                        Capsule().fill(.white).frame(height: 2.5)
                            .matchedGeometryEffect(id: "profileTabUnderline", in: ns)
                    }
                }
                .padding(.horizontal, 14)
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(tab))
    }

    private func icon(for tab: ProfileTab) -> LucideIcon.Name {
        switch tab {
        case .tracks: .music
        case .featuredOn: .sparkles
        case .market: .handshake // only collab listings surface here right now
        }
    }

    private func label(_ tab: ProfileTab) -> String {
        tab == .featuredOn ? "Featured On" : tab.rawValue
    }
}
