//
//  WelcomeScreen.swift
//  Volspire
//
//  The unauthenticated root, on a mesh that runs from the brand blue (the
//  splash's colour, behind the white lockup) into the page colour — white in
//  light mode, black in dark — behind the two ways in. Sign-in and
//  register are both pushed from here and cross-link to each other.
//

import DesignSystem
import SwiftUI

struct WelcomeScreen: View {
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Equal spacers park the lockup dead centre of the space above
            // the buttons — the same place the splash fades out from, so the
            // handoff reads as one screen settling rather than two.
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                VolspireAppMark(size: 96, color: .volspireMark)
                    .padding(.bottom, 12)

                VolspireWordmark(height: 46)
                    .foregroundStyle(Color.volspireMark)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                // They sit on the page-colour end of the mesh: the app's own
                // ink / control capsules.
                AuthCTA(title: "Create account", action: onCreateAccount)
                SecondaryButton("Sign in", action: onSignIn)
                    .buttonStyle(CardPress())
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .background(WelcomeMesh().ignoresSafeArea())
    }

}

/// Brand blue at the top melting into the page colour (white / black) at the
/// bottom — a soft 3×3 mesh, deeper and lighter blues mixed in so it reads as
/// light rather than a flat gradient.
private struct WelcomeMesh: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Dark mode: the same brand blue sunk toward navy, so it sits with a
        // black page instead of glowing over it.
        let dark = colorScheme == .dark
        let blue = dark ? Color(red: 0 / 255, green: 56 / 255, blue: 150 / 255) : .volspireBlue
        let deep = dark ? Color(red: 2 / 255, green: 22 / 255, blue: 72 / 255) : Color(red: 0 / 255, green: 72 / 255, blue: 196 / 255)
        let light = dark ? Color(red: 18 / 255, green: 84 / 255, blue: 196 / 255) : Color(red: 74 / 255, green: 148 / 255, blue: 255 / 255)
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.55], [0.55, 0.5], [1, 0.6],
                [0, 1], [0.5, 1], [1, 1],
            ],
            colors: [
                deep, blue, light,
                blue, light, deep,
                .vBase, .vBase, .vBase,
            ]
        )
    }
}

/// The Volspire spear mark on its own (no tile) — the same vector artwork
/// the splash draws. Ink by default, so it follows light / dark mode.
struct VolspireAppMark: View {
    var size: CGFloat
    var color: Color = .vText

    var body: some View {
        ZStack {
            VolspirePartShape(base: VolspireLogo.bodyAndArrow, pivot: .zero, dx: 0, dy: 0,
                              scale: 1, logoSize: size)
            VolspirePartShape(base: VolspireLogo.wand, pivot: .zero, dx: 0, dy: 0,
                              scale: 1, logoSize: size)
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
