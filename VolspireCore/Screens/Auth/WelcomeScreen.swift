//
//  WelcomeScreen.swift
//  Volspire
//
//  The unauthenticated root: the wordmark where the splash just left it, one
//  line of positioning, and the two ways in. Sign-in and register are both
//  pushed from here and cross-link to each other.
//

import DesignSystem
import SwiftUI

struct WelcomeScreen: View {
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Equal spacers park the wordmark dead centre of the space above
            // the buttons — the same place the splash fades out from, so the
            // handoff reads as one screen settling rather than two.
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                VolspireWordmark(height: 44)
                    .foregroundStyle(.white)

                Text("Share tracks. Find collaborators.")
                    .font(.appCalloutRegular)
                    .foregroundStyle(Color.vText2)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                AuthCTA(title: "Create account", action: onCreateAccount)
                AuthSecondaryCTA(title: "Sign in", action: onSignIn)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
    }
}
