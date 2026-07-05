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
    let slideForward: Bool
    let isOwnProfile: Bool

    /// Base tab-bar clearance plus the floating mini-player when a track is playing.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return 110 + mini
    }

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
        // Flatten the tab's layout into one geometric unit so the whole subtree
        // slides together during the push. Without this, image-backed rows
        // (ArtworkView composites in its own layer) resolve their frames
        // independently and visibly lag/drift behind the text mid-transition.
        .geometryGroup()
        .id(selected)
        // Slide left/right with the tab order — covers are prefetched on profile
        // load so they're cached and slide with the page (no mid-slide pop).
        .transition(.push(from: slideForward ? .trailing : .leading))
    }
}
