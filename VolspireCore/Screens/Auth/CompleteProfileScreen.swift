//
//  CompleteProfileScreen.swift
//  Volspire
//
//  Shown for `AuthState.needsProfile`: a valid session whose auth user owns no
//  `public.users` row. Signing in with Google/Apple mints the auth row on the
//  spot and nothing server-side writes the profile, so a first-time social
//  sign-in lands here instead of in the app — where every write would have
//  failed a foreign key. It reuses the register wizard's profile + photos steps
//  and finishes with the same `create_user` call.
//

import Services
import SwiftUI

struct CompleteProfileScreen: View {
    @Environment(Dependencies.self) private var dependencies

    /// Built once the environment is available (the wizard needs the auth
    /// manager), mirroring how LoginScreen creates its own.
    @State private var viewModel: RegisterViewModel?

    var body: some View {
        Group {
            if let viewModel {
                // `onExit` is unreachable here: it fires only from step 0 and
                // the sign-in link, neither of which this mode renders. Backing
                // out goes through `abandonProfileSetup()` (signs out) instead.
                RegisterScreen(viewModel: viewModel) { _ in }
            } else {
                AuthCanvas()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let model = RegisterViewModel(
                authManager: dependencies.authManager,
                supabaseService: dependencies.supabaseService,
                mode: .completeProfile
            )
            viewModel = model
            // Hand the user a ready-made handle, so this step is a confirmation
            // rather than a required entry of information the provider already
            // supplied (App Store guideline 4).
            await model.prefillGeneratedUsername()
        }
    }
}
