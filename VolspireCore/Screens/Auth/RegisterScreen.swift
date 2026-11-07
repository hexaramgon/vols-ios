//
//  RegisterScreen.swift
//  Volspire
//
//  Signup, v2: flat canvas, back chevron top-left, each step one page
//  (left-aligned heading, grouped input cards, inline gradient CTA) sliding
//  like a pager. Password rules, username availability with inline status,
//  segmented OTP boxes, and the photos step.
//

import AuthenticationServices
import DesignSystem
import MapKit
import PhotosUI
import Services
import SwiftUI

struct RegisterScreen: View {
    /// Which way the wizard was left. The chevron unwinds to wherever the
    /// wizard was opened from; the "Already have an account?" link means
    /// something more specific and should land on sign-in itself.
    /// `existingAccount` lands on sign-in with that email filled in and a
    /// "Welcome back" heading — the email already has an account.
    enum Exit { case back, signIn, existingAccount(email: String) }

    @Environment(Dependencies.self) private var dependencies

    /// Injected fully-formed so the slide-in transition animates real content
    /// (a lazily-created view model would insert an empty frame that pops).
    @State var viewModel: RegisterViewModel
    /// Hands the container the screen to swap to (it swaps them in place).
    let onExit: (Exit) -> Void

    /// MapKit city/region autocomplete for the location field (same completer
    /// as Edit Profile).
    @State private var locationCompleter = LocationCompleter()
    @FocusState private var locationFocused: Bool
    @FocusState private var usernameFocused: Bool

    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var showAvatarPicker = false
    @State private var showBannerPicker = false
    /// The picked banner, awaiting the 16:9 crop (shared with Edit Profile + web).
    @State private var bannerCropTarget: CropTarget?
    /// Legal docs presented from the signup agreement checkbox.
    @State private var showTermsDoc = false
    @State private var showPrivacyDoc = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            ZStack {
                Group {
                    switch viewModel.step {
                    case 0: stepPage(0) { emailStep(viewModel) }
                    case 1: stepPage(1) { passwordStep(viewModel) }
                    case 2: stepPage(2) { profileStep(viewModel) }
                    case 3: stepPage(3) { verifyStep(viewModel) }
                    case 4: stepPage(4) { photosStep(viewModel) }
                    default: stepPage(RegisterViewModel.totalSteps) { EmptyView() }
                    }
                }
                .transition(.push(from: viewModel.slideForward ? .trailing : .leading))
            }
        }
        .background(AuthCanvas())
        .authSwipeBack(isEnabled: canSwipeBack, action: goBack)
        .sheet(isPresented: $showTermsDoc) { SettingsDocScreen(doc: .terms, inSheet: true) }
        .sheet(isPresented: $showPrivacyDoc) { SettingsDocScreen(doc: .privacy, inSheet: true) }
        // Step 0 found an existing account for this email → Sign in, prefilled.
        .onChange(of: viewModel.existingAccountEmail) { _, email in
            if let email { leaveWizard(to: .existingAccount(email: email)) }
        }
    }

    // MARK: - Top bar (back chevron)

    /// Hidden mid-verification (the verify step has its own "start over") and on
    /// the done step.
    private var canGoBack: Bool {
        viewModel.step != 3 && viewModel.step < RegisterViewModel.totalSteps
    }

    /// In `.completeProfile` the only way back is out of the account entirely,
    /// which is too destructive to hang off a gesture — that one stays a
    /// deliberate tap on the chevron.
    private var canSwipeBack: Bool {
        canGoBack && !viewModel.loading && !isProfileSetupRoot
    }

    private var isProfileSetupRoot: Bool {
        viewModel.mode == .completeProfile && viewModel.step == 2
    }

    /// Back steps the wizard; on the first step it returns to the landing.
    private var topBar: some View {
        VStack(spacing: 0) {
            AuthWizardBackBar(canGoBack: canGoBack, disabled: viewModel.loading, onBack: goBack)
            // How far through sign-up you are (onboarding = chevron + slim
            // line); full on the done step.
            AuthProgressLine(progress: CGFloat(min(viewModel.step + 1, RegisterViewModel.totalSteps))
                / CGFloat(RegisterViewModel.totalSteps))
                .padding(.horizontal, 24)
                .padding(.top, 2)
        }
    }

    private func goBack() {
        if isProfileSetupRoot {
            // Nothing sits behind the profile step in this mode — backing out
            // means ending the session, not returning to login.
            Task { await viewModel.abandonProfileSetup() }
        } else if viewModel.step == 0 {
            leaveWizard(to: .back)
        } else {
            viewModel.goBack()
        }
    }

    /// Shared scroll shell for a step: left-aligned heading, the step's
    /// fields, error state, then its inline CTA.
    private func stepPage(_ step: Int, @ViewBuilder content: () -> some View) -> some View {
        AuthStepPage(
            title: RegisterViewModel.stepTitles[step],
            subtitle: viewModel.subtitle(for: step),
            // The existing-account notice replaces the raw error message.
            error: viewModel.existingAccount ? nil : viewModel.error
        ) {
            content()
        } footer: {
            if viewModel.existingAccount {
                existingAccountNotice(viewModel)
                    .padding(.top, 14)
            }

            stepPrimaryButton(step)
                .padding(.top, 24)

            // Only the first step offers the swap to sign-in; past it there's a
            // half-made account behind you.
            if step == 0 {
                AuthBottomLink(prompt: "Already have an account?", action: "Sign in") {
                    leaveWizard(to: .signIn)
                }
                .padding(.top, 8)
            }
        }
    }

    /// The step's inline CTA. The verify step auto-submits when the sixth
    /// digit lands, so its button doubles as a manual retry.
    @ViewBuilder
    private func stepPrimaryButton(_ step: Int) -> some View {
        switch step {
        case 0, 1, 2:
            AuthCTA(
                title: "Continue",
                isLoading: viewModel.loading,
                isDisabled: !viewModel.canContinue
            ) {
                Task { await viewModel.goNext() }
            }
        case 3:
            AuthCTA(
                title: "Verify",
                isLoading: viewModel.loading,
                isDisabled: viewModel.otpCode.count != 6
            ) {
                Task { await viewModel.verifyOtp() }
            }
        case 4:
            AuthCTA(
                title: viewModel.finishButtonTitle,
                isLoading: viewModel.loading
            ) {
                Task { await viewModel.finish() }
            }
        default:
            AuthCTA(title: "Continue to Profile") {
                Task { await viewModel.enterApp() }
            }
        }
    }

    /// Closes the wizard. If a held session exists (user verified but bailed
    /// early), release it — the profile gate decides where they actually land.
    private func leaveWizard(to exit: Exit) {
        Task {
            await dependencies.authManager.finishOnboarding()
            onExit(exit)
        }
    }

    // ── Step 0: email ──

    @ViewBuilder
    private func emailStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(spacing: 0) {
            // No EULA gate here: consent is taken once the user has actually
            // committed to a path — on the password step for email, and on the
            // profile step after a social sign-in. Both land before the account
            // is created (App Store 1.2), which is what the requirement is about.
            VStack(spacing: 10) {
                AppleAuthButton(label: "Continue with Apple") { credential, nonce in
                    Task { await dependencies.authManager.signInWithApple(credential: credential, nonce: nonce) }
                } onError: { error in
                    dependencies.authManager.setError(from: error)
                }

                GoogleAuthButton(label: "Continue with Google") {
                    Task { await dependencies.authManager.signInWithGoogle() }
                }
            }

            AuthOrDivider()
                .padding(.vertical, 22)

            AuthFieldGroup {
                AuthRow(
                    icon: .mail,
                    placeholder: "Email address",
                    text: Binding(get: { viewModel.email }, set: { viewModel.email = $0 }),
                    keyboard: .emailAddress,
                    contentType: .emailAddress
                )
            }
        }
    }

    /// Age/Terms + Privacy acceptance — SEPARATE checkboxes, each with its
    /// legal link flowing inline with the copy to the row's full width.
    private func termsAgreement(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            agreementRow(checked: viewModel.agreedToTerms, text: Self.termsString) {
                viewModel.agreedToTerms.toggle()
            }
            agreementRow(checked: viewModel.agreedToPrivacy, text: Self.privacyString) {
                viewModel.agreedToPrivacy.toggle()
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            switch url.absoluteString {
            case "volspire://terms": showTermsDoc = true
            case "volspire://privacy": showPrivacyDoc = true
            default: break
            }
            return .handled
        })
    }

    private func agreementRow(
        checked: Bool, text: AttributedString, toggle: @escaping () -> Void
    ) -> some View {
        // Centre-aligned: the box sits on the row's vertical middle (between
        // the lines when the sentence wraps), not hanging off the first line.
        HStack(alignment: .center, spacing: 11) {
            Button {
                withAnimation(.snappy(duration: 0.15)) { toggle() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .fill(checked ? Color.vInverse : Color.ink(0.06))
                    RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                        .strokeBorder(Color.ink(checked ? 0 : 0.25), lineWidth: 1.5)
                    if checked {
                        LucideIcon(.check, .sm).foregroundStyle(Color.vOnInverse)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.vertical, 2) // hit comfort without changing the row height
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            Text(text)
                .fixedSize(horizontal: false, vertical: true)
                .tint(Color.vText)
            Spacer(minLength: 0)
        }
    }

    private static var termsString: AttributedString {
        var lead = AttributedString("I'm 13 or older and agree to Volspire's ")
        lead.font = .appFootnote
        lead.foregroundColor = Color.vText2
        var terms = AttributedString("Terms of Service")
        terms.font = .appFootnoteMedium
        terms.link = URL(string: "volspire://terms")
        return lead + terms
    }

    private static var privacyString: AttributedString {
        var lead = AttributedString("I have read and agree to the ")
        lead.font = .appFootnote
        lead.foregroundColor = Color.vText2
        var privacy = AttributedString("Privacy Policy")
        privacy.font = .appFootnoteMedium
        privacy.link = URL(string: "volspire://privacy")
        return lead + privacy
    }

    // ── Step 1: password + rules ──

    @ViewBuilder
    private func passwordStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            // EULA gate for the email path — the last step before `handleSignUp`
            // creates the account. Social sign-ins never reach this step and
            // take the same consent on the profile step instead.
            termsAgreement(viewModel)
                .padding(.bottom, 4)

            AuthFieldGroup {
                AuthSecureRow(
                    placeholder: "Password",
                    text: Binding(get: { viewModel.password }, set: { viewModel.password = $0 }),
                    contentType: .newPassword
                )
                AuthRowDivider()
                AuthSecureRow(
                    placeholder: "Confirm password",
                    text: Binding(get: { viewModel.confirmPassword }, set: { viewModel.confirmPassword = $0 }),
                    contentType: .newPassword
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.passwordChecks, id: \.label) { rule in
                    HStack(spacing: 9) {
                        // The app's pop mark (same as the playlist / workspace
                        // pickers): a soft dot until the rule passes.
                        PopMark(isOn: rule.ok, rest: .dot, size: 17)
                        Text(rule.label)
                            .font(.appFootnote)
                            .foregroundStyle(rule.ok ? Color.vText2 : Color.vText3)
                            .animation(.popMark, value: rule.ok)
                    }
                }

                if !viewModel.confirmPassword.isEmpty, !viewModel.passwordsMatch {
                    AuthPasswordMismatchLabel()
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.popMark, value: !viewModel.confirmPassword.isEmpty && !viewModel.passwordsMatch)
            .padding(.leading, 4)
        }
    }

    // ── Step 2: username + location + roles ──

    @ViewBuilder
    private func profileStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                AuthFieldGroup {
                    HStack(spacing: 12) {
                        LucideIcon(.user, .md)
                            .foregroundStyle(Color.vText3)
                        TextField(
                            "",
                            text: Binding(
                                get: { viewModel.username },
                                set: { viewModel.usernameChanged($0) }
                            ),
                            prompt: Text("Username").foregroundStyle(Color.vText3)
                        )
                        .font(.appBody)
                        .foregroundStyle(Color.vText)
                        .tint(Color.vText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($usernameFocused)

                        // Available / taken pop in like the pickers' check;
                        // the spinner shows while it's checking.
                        ZStack {
                            if viewModel.usernameStatus == .checking {
                                ProgressView().controlSize(.small).tint(Color.vText3)
                            }
                            PopMark(isOn: viewModel.usernameStatus == .available, rest: .none, size: 20)
                            PopMark(isOn: viewModel.usernameStatus == .taken, mark: .cross, rest: .none,
                                    tint: Color.vError, size: 20)
                        }
                        .frame(width: 22, height: 22)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .authFieldFocus(usernameFocused)
                }

                Group {
                    if viewModel.usernameStatus == .taken {
                        Text("That username is already taken.")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vError)
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    } else if viewModel.usernameStatus == .available {
                        Text("Username is available.")
                            .font(.appFootnote)
                            .foregroundStyle(Color.vSuccessText)
                            .padding(.leading, 4)
                            .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
                .animation(.popMark, value: viewModel.usernameStatus)
            }

            locationField(viewModel)

            // Collab-map opt-in (web register step 2). Off by default; applied
            // with `set_open_to_collab` once the profile row exists.
            Toggle(isOn: Binding(get: { viewModel.openToCollab }, set: { viewModel.openToCollab = $0 })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Open to collaboration?")
                        .font(.appCalloutSemibold)
                        .foregroundStyle(Color.vText)
                    Text("Your city and your music will be shown on the Collab map so other artists can find you. You can change this any time in Settings.")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(.ink)

            VStack(alignment: .leading, spacing: 10) {
                Text("Your roles")
                    .font(.appCalloutSemibold)
                    .foregroundStyle(Color.vText)
                Text("Optional — helps people find your work. Pick up to \(ProfileRoles.max).")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)

                RolePicker(selection: Binding(
                    get: { viewModel.tags },
                    set: { viewModel.tags = $0 }
                ))
            }

            // Social sign-in never sees the password step, where the email path
            // takes the EULA — so it's collected here, before `create_user` runs.
            if viewModel.mode == .completeProfile {
                termsAgreement(viewModel)
            }
        }
    }

    /// Location with MapKit autocomplete — suggestions drop down inside the
    /// same grouped card.
    private func locationField(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.appCalloutSemibold)
                .foregroundStyle(Color.vText)

            AuthFieldGroup {
                HStack(spacing: 12) {
                    LucideIcon(.mapPin, .md)
                        .foregroundStyle(locationFocused ? Color.vText : Color.vText3)
                    TextField(
                        "",
                        text: Binding(get: { viewModel.location }, set: { viewModel.location = $0 }),
                        prompt: Text("City, Country (optional)").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(Color.vText)
                    .tint(Color.vText)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($locationFocused)
                    .onChange(of: viewModel.location) { _, newValue in
                        locationCompleter.update(newValue)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .authFieldFocus(locationFocused)

                if locationFocused, !locationCompleter.suggestions.isEmpty {
                    ForEach(locationCompleter.suggestions, id: \.self) { suggestion in
                        AuthRowDivider()
                        Button {
                            viewModel.location = Self.formattedLocation(suggestion)
                            locationCompleter.clear()
                            locationFocused = false
                        } label: {
                            HStack(spacing: 12) {
                                LucideIcon(.mapPin, .sm)
                                    .foregroundStyle(Color.vText3)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(suggestion.title)
                                        .font(.appCallout).foregroundStyle(Color.vText).lineLimit(1)
                                    if !suggestion.subtitle.isEmpty {
                                        Text(suggestion.subtitle)
                                            .font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: locationFocused)
            .animation(.easeInOut(duration: 0.15), value: locationCompleter.suggestions.isEmpty)
        }
    }

    /// Condenses a completion into "City, Region" (drops the trailing country
    /// when a state/region is present) — same rule as Edit Profile.
    private static func formattedLocation(_ suggestion: MKLocalSearchCompletion) -> String {
        let region = suggestion.subtitle
            .split(separator: ",").first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return region.isEmpty ? suggestion.title : "\(suggestion.title), \(region)"
    }

    // ── Step 3: verify email (segmented code boxes) ──

    @ViewBuilder
    private func verifyStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(spacing: 24) {
            Text("We sent a 6-digit code to \(Text(viewModel.email).foregroundStyle(Color.vText)).")
                .foregroundStyle(Color.vText2)
                .font(.appCalloutRegular)
                .frame(maxWidth: .infinity, alignment: .leading)

            AuthCodeField(
                code: Binding(get: { viewModel.otpCode }, set: { viewModel.otpCode = $0 }),
                disabled: viewModel.loading,
                onEdit: { viewModel.verifyError = nil },
                onFilled: { Task { await viewModel.verifyOtp() } }
            )

            if let verifyError = viewModel.verifyError {
                ErrorBanner(verifyError)
            }

            VStack(spacing: 14) {
                AuthResendButton(state: resendState) {
                    Task { await viewModel.resend() }
                }

                Button {
                    viewModel.resetToStart()
                } label: {
                    Text("Wrong email? \(Text("Start over").foregroundStyle(Color.vText))")
                        .foregroundStyle(Color.vText3)
                        .font(.appSubheadline)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The view model's resend status in the shared button's terms.
    private var resendState: AuthResendButton.ResendState {
        switch viewModel.resendStatus {
        case .idle: .idle
        case .sending: .sending
        case .sent: .sent
        }
    }

    // ── Step 4: photos ──

    @ViewBuilder
    private func photosStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profile photo")
                    .font(.appCalloutSemibold)
                    .foregroundStyle(Color.vText)

                Button {
                    showAvatarPicker = true
                } label: {
                    ZStack {
                        if let image = viewModel.avatarImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            // Borderless field fill, like the rest of the app's
                            // pickers (no dashed "create" outline).
                            Color.vField
                            LucideIcon(.camera, .lg)
                                .foregroundStyle(Color.vText3)
                        }
                    }
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
            }

            // Banners are parked (FeatureFlags.profileBanners).
            if FeatureFlags.profileBanners {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Banner")
                        .font(.appCalloutSemibold)
                        .foregroundStyle(Color.vText)

                    Button {
                        showBannerPicker = true
                    } label: {
                        ZStack {
                            if let image = viewModel.bannerImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.vField
                                VStack(spacing: 6) {
                                    LucideIcon(.image, .lg)
                                        .foregroundStyle(Color.vText3)
                                    Text("Tap to upload")
                                        .font(.appFootnote)
                                        .foregroundStyle(Color.vText3)
                                }
                            }
                        }
                        .aspectRatio(ProfileLayout.bannerCropAspect, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(FeatureFlags.profileBanners
                 ? "Both are optional — you can add or change them any time from your profile."
                 : "It's optional — you can add or change it any time from your profile.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $avatarItem, matching: .images)
        .photosPicker(isPresented: $showBannerPicker, selection: $bannerItem, matching: .images)
        .onChange(of: avatarItem) { _, item in
            loadImage(item) { viewModel.avatarImage = $0 }
        }
        .onChange(of: bannerItem) { _, item in
            // Crop it like Edit Profile does, rather than uploading the raw photo.
            loadImage(item) { bannerCropTarget = CropTarget(image: $0.normalizedUp()) }
        }
        .fullScreenCover(item: $bannerCropTarget) { target in
            ImageCropperView(
                image: target.image,
                onCrop: { data in
                    viewModel.bannerImage = UIImage(data: data)
                    bannerCropTarget = nil
                },
                onCancel: { bannerCropTarget = nil },
                aspectRatio: ProfileLayout.bannerCropAspect,
                // 2400×1350: tall enough for the iPhone hero's height fill
                // (~1130px at 3x) without upscaling.
                outputSize: ProfileLayout.bannerOutputSize,
                allowsFitMode: false,
                guides: ProfileLayout.bannerGuides
            )
        }
    }

    private func loadImage(_ item: PhotosPickerItem?, assign: @escaping (UIImage) -> Void) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data)
            {
                assign(image)
            }
        }
    }

    // MARK: - Existing-account notice

    private func existingAccountNotice(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("An account already exists for \(viewModel.email).")
                .font(.appCalloutRegular)
                .foregroundStyle(Color.vText)
            HStack(spacing: 4) {
                Button {
                    leaveWizard(to: .existingAccount(email: viewModel.email.trimmingCharacters(in: .whitespaces)))
                } label: {
                    Text("Sign in instead")
                        .foregroundStyle(Color.vText)
                        .fontWeight(.medium)
                        .underline()
                }
                .buttonStyle(.plain)
                Text("or")
                    .foregroundStyle(Color.vText3)
                Button {
                    viewModel.resetToStart()
                } label: {
                    Text("use a different email")
                        .foregroundStyle(Color.vText)
                        .fontWeight(.medium)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .font(.appFootnote)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.vCard, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    ZStack {
        AuthCanvas()
        RegisterScreen(
            viewModel: RegisterViewModel(
                authManager: dependencies.authManager,
                supabaseService: dependencies.supabaseService
            ),
            onExit: { _ in }
        )
    }
    .environment(dependencies)
}
