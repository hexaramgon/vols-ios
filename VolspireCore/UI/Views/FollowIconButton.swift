//
//  FollowIconButton.swift
//  Volspire
//
//  Follow as a round icon button (the web's `ArtistIconActions` follow half):
//  primary UserPlus → accent UserCheck with the toggle-on pop. Reads/writes
//  the shared SocialStore overlay, so a follow made anywhere shows here live.
//  Taps while a request is in flight are ignored (no busy dim — it would flash
//  on every optimistic tap).
//

import DesignSystem
import SwiftUI

struct FollowIconButton: View {
    let userId: String
    var fallback: Bool = false
    var size: CircleIconButton.Size = .sm
    @Environment(SocialStore.self) private var social
    @State private var inFlight = false

    var body: some View {
        let following = social.isFollowing(userId, fallback: fallback)
        CircleIconButton(
            icon: following ? .userCheck : .userPlus,
            size: size,
            variant: following ? .send : .primary,
            popOn: following
        ) {
            guard !inFlight else { return }
            inFlight = true
            Haptics.impact(.soft)
            Task {
                await social.toggleFollow(userId: userId, currentlyFollowing: following)
                inFlight = false
            }
        }
        .accessibilityLabel(following ? "Following" : "Follow")
    }
}
