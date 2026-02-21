//
//  OverlaidRootView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import SwiftUI

struct OverlaidRootView: View {
    @State private var expandSheet: Bool = false
    @State private var conversationState = ConversationState()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(PlayerController.self) var playerController

    private var showMiniPlayer: Bool {
        playerController.display.title.isEmpty == false
    }

    private var isConversationActive: Bool {
        conversationState.activeConversation != nil
    }

    private var collapsedFrame: CGRect {
        // Position the collapsed mini-player above the tab bar
        let tabBarHeight: CGFloat = 49
        let bottomPadding: CGFloat = 8
        let horizontalPadding: CGFloat = 8
        let height = ViewConst.compactNowPlayingHeight
        let screenWidth = UIScreen.size.width
        let screenHeight = UIScreen.size.height
        let safeAreaBottom = ViewConst.safeAreaInsets.bottom

        return CGRect(
            x: horizontalPadding,
            y: screenHeight - safeAreaBottom - tabBarHeight - bottomPadding - height,
            width: screenWidth - (horizontalPadding * 2),
            height: height
        )
    }

    var body: some View {
        RootTabView()
            .safeAreaPadding(.bottom, showMiniPlayer ? ViewConst.compactNowPlayingHeight + 16 : 0)
            .animation(.easeInOut(duration: 0.2), value: showMiniPlayer)
            .overlay {
                if showMiniPlayer {
                    ExpandableNowPlaying(
                        show: .constant(true),
                        expanded: $expandSheet,
                        collapsedFrame: collapsedFrame
                    )
                    .offset(y: isConversationActive ? (ViewConst.safeAreaInsets.bottom + 49) : 0)
                    .allowsHitTesting(!isConversationActive)
                    .animation(.easeInOut(duration: 0.3), value: isConversationActive)
                    .toolbarColorScheme(colorScheme, for: .navigationBar)
                }
            }
            .environment(conversationState)
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    OverlaidRootView()
        .environment(playerController)
        .environment(dependencies)
}
