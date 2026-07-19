//
//  ProfileTabContent.swift
//  Volspire
//
//  Switches the selected tab's content, sliding left/right with the tab order.
//

import DesignSystem
import SwiftUI

struct ProfileTabContent: View {
    @Environment(PlayerController.self) private var playerController
    let viewModel: ProfileScreenViewModel
    let selected: ProfileTab
    let isOwnProfile: Bool

    /// Base tab-bar clearance plus the floating mini-player when a track is playing.
    private var bottomInset: CGFloat { 110 + playerController.miniPlayerAllowance }

    var body: some View {
        Group {
            switch selected {
            case .tracks:
                ProfileTracksTab(viewModel: viewModel, isOwnProfile: isOwnProfile)
            case .featuredOn:
                ProfileFeaturedTab(viewModel: viewModel)
            case .market:
                ProfileMarketTab(viewModel: viewModel, isOwnProfile: isOwnProfile)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 14)
        .padding(.bottom, bottomInset)
        // Plain crossfade — same as the Home tab switch, which has never had a
        // hit-testing or image-lag complaint. Anything that MOVES this content
        // during the swap (`.push`, offset transitions, geometryGroup) has
        // repeatedly produced either drifted tap targets or covers visibly
        // trailing the motion (async images mounting mid-animation don't
        // animate). No movement → nothing to lag, nothing to drift.
        .id(selected)
        .transition(.opacity)
    }
}
