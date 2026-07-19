//
//  ProfileMiniHeader.swift
//  Volspire
//
//  Solid bar + centred username that crossfade in as the hero scrolls past.
//  This is the ONLY view observing `ProfileScrollState`, so per-frame scroll
//  updates re-render just this bar — never the profile body (that full-body
//  re-render was the old scroll stutter). Never hit-testable: the system
//  toolbar's back/"…" buttons sit on top and must stay live.
//

import DesignSystem
import SwiftUI

struct ProfileMiniHeader: View {
    let state: ProfileScrollState
    let viewModel: ProfileScreenViewModel

    var body: some View {
        Color.vBar
            .frame(height: ViewConst.safeAreaInsets.top + 44)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color.vBorder).frame(height: 0.5)
            }
            .overlay(alignment: .bottom) {
                Text(viewModel.username)
                    .font(.appHeadline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    // Keep clear of the side toolbar buttons, like a system bar.
                    .padding(.horizontal, 64)
                    .frame(height: 44)
            }
            .opacity(state.miniOpacity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}
