//
//  OverlaidRootView.swift
//  Volspire
//
//

import DesignSystem
import Foundation
import Kingfisher
import SwiftUI

struct OverlaidRootView: View {
    @State private var expandSheet: Bool = false
    @State private var conversationState = ConversationState()
    @State private var avatarPreview = AvatarPreviewState()
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
            .animation(.easeInOut(duration: 0.2), value: showMiniPlayer)
            .overlay {
                // Wrapper + scoped animation so the mini player's insert/remove
                // (when a track starts / clears) actually animates — the
                // `.animation` on RootTabView above doesn't reach into the overlay.
                ZStack {
                    if showMiniPlayer {
                        ExpandableNowPlaying(
                            show: .constant(true),
                            expanded: $expandSheet,
                            collapsedFrame: collapsedFrame
                        )
                        // Clear the mini-player inside a conversation — the chat is
                        // full-screen and its input bar owns the bottom.
                        .offset(y: isConversationActive ? 140 : 0)
                        .opacity(isConversationActive ? 0 : 1)
                        .allowsHitTesting(!isConversationActive)
                        .animation(.easeInOut(duration: 0.3), value: isConversationActive)
                        .toolbarColorScheme(colorScheme, for: .navigationBar)
                        // Slide up + fade in when a track starts (reverse on clear)
                        // instead of popping in/out.
                        .transition(.offset(y: 70).combined(with: .opacity))
                    }
                }
                .animation(.smooth(duration: 0.4), value: showMiniPlayer)
            }
            // Above the mini-player + tab bar so the avatar zoom covers everything.
            .overlay { avatarPreviewOverlay }
            .environment(conversationState)
            .environment(avatarPreview)
            .onChange(of: playerController.pendingProfileNavigation) { _, userId in
                guard let userId else { return }
                // Collapse the player
                withAnimation(.playerExpandAnimation) {
                    expandSheet = false
                }
                // Post notification so the active tab can navigate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .navigateToProfile,
                        object: nil,
                        userInfo: ["userId": userId]
                    )
                    playerController.pendingProfileNavigation = nil
                }
            }
            .onChange(of: playerController.pendingExpand) { _, expand in
                guard expand else { return }
                // Tapping a workspace file opens straight into the (comments) player.
                withAnimation(.playerExpandAnimation) { expandSheet = true }
                playerController.pendingExpand = false
            }
    }
}

private extension OverlaidRootView {
    /// The full-screen avatar zoom — one circular image grows from the tapped
    /// avatar's frame to a large centred circle over a dimmed app, and shrinks back.
    @ViewBuilder
    var avatarPreviewOverlay: some View {
        if avatarPreview.mounted, let url = avatarPreview.url {
            let f = avatarPreview.sourceFrame
            let circular = avatarPreview.circular
            // Expanded size: a square for the circular avatar; for an attachment,
            // fit the source's aspect ratio within the screen.
            let expanded: CGSize = {
                if circular {
                    let big = min(UIScreen.size.width - 56, 340)
                    return CGSize(width: big, height: big)
                }
                let aspect = max(f.width, 1) / max(f.height, 1)
                let maxW = UIScreen.size.width - 24
                let maxH = UIScreen.size.height * 0.72
                var w = maxW, h = maxW / aspect
                if h > maxH { h = maxH; w = maxH * aspect }
                return CGSize(width: w, height: h)
            }()
            let w = avatarPreview.zoomed ? expanded.width : f.width
            let h = avatarPreview.zoomed ? expanded.height : f.height
            let cx = avatarPreview.zoomed ? UIScreen.size.width / 2 : f.midX
            let cy = avatarPreview.zoomed ? UIScreen.size.height / 2 : f.midY
            let shape: AnyShape = circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            ZStack {
                Color.black.opacity(avatarPreview.zoomed ? 0.92 : 0).ignoresSafeArea()

                KFImage(url)
                    .resizable()
                    .scaledToFill()
                    .frame(width: w, height: h)
                    .clipShape(shape)
                    .shadow(color: .black.opacity(0.5), radius: avatarPreview.zoomed ? 28 : 14, y: avatarPreview.zoomed ? 12 : 6)
                    .position(x: cx, y: cy)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { avatarPreview.dismiss() }
        }
    }
}

extension Notification.Name {
    static let navigateToProfile = Notification.Name("navigateToProfile")
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    @Previewable @State var playerController = PlayerController.stub

    OverlaidRootView()
        .environment(playerController)
        .environment(dependencies)
}
