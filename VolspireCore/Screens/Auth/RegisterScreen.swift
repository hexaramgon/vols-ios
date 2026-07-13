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
    @Environment(Dependencies.self) private var dependencies

    /// Injected fully-formed so the slide-in transition animates real content
    /// (a lazily-created view model would insert an empty frame that pops).
    @State var viewModel: RegisterViewModel
    /// Returns to the login form (the auth container swaps screens in place).
    let onClose: () -> Void

    /// MapKit city/region autocomplete for the location field (same completer
    /// as Edit Profile).
    @State private var locationCompleter = LocationCompleter()
    @FocusState private var locationFocused: Bool

    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var showAvatarPicker = false
    @State private var showBannerPicker = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 12)
                .padding(.top, 8)

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
        // Overlay (not safeAreaInset): the link stays anchored to the screen
        // bottom and the keyboard simply covers it, instead of riding up.
        // The overlay content must be FULL-HEIGHT for the keyboard opt-out to
        // work — ignoresSafeArea only expands views whose bounds touch the
        // ignored region, so a bare link would still be pushed up.
        .overlay {
            if viewModel.step == 0 {
                signInLink
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
    }

    // MARK: - Top bar (back chevron)

    /// Back steps the wizard; on the first step it returns to login. Hidden
    /// mid-verification (the verify step has its own "start over") and on the
    /// done step.
    private var topBar: some View {
        HStack {
            if viewModel.step != 3, viewModel.step < RegisterViewModel.totalSteps {
                Button {
                    if viewModel.step == 0 {
                        leaveWizard()
                    } else {
                        viewModel.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: ViewConst.backIconSize, weight: .semibold))
                        .imageScale(.large)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.loading)
            }
            Spacer()
        }
        .frame(height: 44)
    }

    /// Shared scroll shell for a step: left-aligned heading, the step's
    /// fields, error state, then its inline CTA.
    private func stepPage(_ step: Int, @ViewBuilder content: () -> some View) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(RegisterViewModel.stepTitles[step])
                    .font(.appTitleXXL)
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                Text(RegisterViewModel.stepSubtitles[step])
                    .font(.appCalloutRegular)
                    .foregroundStyle(Color.vText2)
                    .padding(.top, 6)

                content()
                    .padding(.top, 28)

                if let error = viewModel.error, !viewModel.existingAccount {
                    AuthErrorBanner(message: error)
                        .padding(.top, 14)
                }

                if viewModel.existingAccount {
                    existingAccountNotice(viewModel)
                        .padding(.top, 14)
                }

                stepPrimaryButton(step)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 24)
            // Extra clearance on the first step for the pinned sign-in link.
            .padding(.bottom, step == 0 ? 72 : 32)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // No rubber-band on steps that fit the screen — keyboard-driven scroll
        // adjustments stay pinned instead of bouncing the page.
        .scrollBounceBehavior(.basedOnSize)
    }

    /// The step's inline CTA. The verify step auto-submits when the sixth
    /// digit lands, so its button doubles as a manual retry.
    @ViewBuilder
    private func stepPrimaryButton(_ step: Int) -> some View {
        switch step {
        case 0, 1, 2:
            AuthCTA(
                title: "Continue",
                loadingTitle: "Creating account…",
                isLoading: viewModel.loading,
                isDisabled: !viewModel.canContinue
            ) {
                Task { await viewModel.goNext() }
            }
        case 3:
            AuthCTA(
                title: "Verify",
                loadingTitle: "Verifying…",
                isLoading: viewModel.loading,
                isDisabled: viewModel.otpCode.count != 6
            ) {
                Task { await viewModel.verifyOtp() }
            }
        case 4:
            AuthCTA(
                title: viewModel.finishButtonTitle,
                loadingTitle: "Creating account…",
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

    private var signInLink: some View {
        Button {
            leaveWizard()
        } label: {
            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(Color.vText3)
                Text("Sign in")
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
            }
            .font(.appCalloutRegular)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
    }

    /// Closes the wizard. If a held session exists (user verified but bailed
    /// early), reveal it so they land in the app rather than limbo.
    private func leaveWizard() {
        Task {
            await dependencies.authManager.finishOnboarding()
            onClose()
        }
    }

    // ── Step 0: email ──

    @ViewBuilder
    private func emailStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                AppleAuthButton(label: "Continue with Apple") { credential in
                    Task { await dependencies.authManager.signInWithApple(credential: credential) }
                } onError: { error in
                    dependencies.authManager.setError(error.localizedDescription)
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

    // ── Step 1: password + rules ──

    @ViewBuilder
    private func passwordStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 18) {
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
                        ZStack {
                            Circle().fill(rule.ok ? Color.green.opacity(0.15) : Color.white.opacity(0.08))
                            LucideIcon(.check, .xs)
                                .foregroundStyle(rule.ok ? Color.green : Color.vText3)
                        }
                        .frame(width: 17, height: 17)
                        Text(rule.label)
                            .font(.appFootnote)
                            .foregroundStyle(rule.ok ? Color.vText2 : Color.vText3)
                    }
                }

                if !viewModel.confirmPassword.isEmpty, !viewModel.passwordsMatch {
                    Text("Passwords must match")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vError)
                }
            }
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
                        .foregroundStyle(.white)
                        .tint(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        switch viewModel.usernameStatus {
                        case .checking:
                            ProgressView().controlSize(.small).tint(Color.vText3)
                        case .available:
                            LucideIcon(.circleCheck, .md).foregroundStyle(Color.green)
                        case .taken:
                            LucideIcon(.circleX, .md).foregroundStyle(Color.vError)
                        case .idle:
                            EmptyView()
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                }

                if viewModel.usernameStatus == .taken {
                    Text("That username is already taken.")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vError)
                        .padding(.leading, 4)
                } else if viewModel.usernameStatus == .available {
                    Text("Username is available.")
                        .font(.appFootnote)
                        .foregroundStyle(Color.green)
                        .padding(.leading, 4)
                }
            }

            locationField(viewModel)

            VStack(alignment: .leading, spacing: 10) {
                Text("Your roles")
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.white)
                Text("Optional — helps people find your work. Pick up to \(ProfileRoles.max).")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)

                ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(ProfileRoles.all, id: \.self) { role in
                        let selected = viewModel.tags.contains(role)
                        Button {
                            viewModel.toggleTag(role)
                        } label: {
                            Text(role)
                                .font(.appFootnoteMedium)
                                .foregroundStyle(selected ? .black : Color.vText2)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    Color.white.opacity(selected ? 1 : 0.05),
                                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                                )
                                .contentShape(.rect(cornerRadius: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Location with MapKit autocomplete — suggestions drop down inside the
    /// same grouped card.
    private func locationField(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.appCalloutSemibold)
                .foregroundStyle(.white)

            AuthFieldGroup {
                HStack(spacing: 12) {
                    LucideIcon(.mapPin, .md)
                        .foregroundStyle(locationFocused ? .white : Color.vText3)
                    TextField(
                        "",
                        text: Binding(get: { viewModel.location }, set: { viewModel.location = $0 }),
                        prompt: Text("City, Country (optional)").foregroundStyle(Color.vText3)
                    )
                    .font(.appBody)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($locationFocused)
                    .onChange(of: viewModel.location) { _, newValue in
                        locationCompleter.update(newValue)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 54)

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
                                        .font(.appCallout).foregroundStyle(.white).lineLimit(1)
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
            Text("We sent a 6-digit code to \(Text(viewModel.email).foregroundStyle(.white)).")
                .foregroundStyle(Color.vText2)
                .font(.appCalloutRegular)
                .frame(maxWidth: .infinity, alignment: .leading)

            AuthCodeField(
                code: Binding(
                    get: { viewModel.otpCode },
                    set: { newValue in
                        let digits = String(newValue.filter(\.isNumber).prefix(6))
                        viewModel.otpCode = digits
                        viewModel.verifyError = nil
                        if digits.count == 6 {
                            Task { await viewModel.verifyOtp() }
                        }
                    }
                ),
                disabled: viewModel.loading
            )

            if let verifyError = viewModel.verifyError {
                AuthErrorBanner(message: verifyError)
            }

            VStack(spacing: 14) {
                Button {
                    Task { await viewModel.resend() }
                } label: {
                    Group {
                        switch viewModel.resendStatus {
                        case .sending:
                            Text("Sending…").foregroundStyle(Color.vText3)
                        case .sent:
                            HStack(spacing: 6) {
                                LucideIcon(.check, .xs)
                                Text("New code sent — check your inbox")
                            }
                            .foregroundStyle(Color.green)
                        case .idle:
                            Text("Didn't get a code? \(Text("Resend").foregroundStyle(.white).underline())")
                                .foregroundStyle(Color.vText3)
                        }
                    }
                    .font(.appSubheadline)
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.resendStatus != .idle)

                Button {
                    viewModel.resetToStart()
                } label: {
                    Text("Wrong email? \(Text("Start over").foregroundStyle(.white))")
                        .foregroundStyle(Color.vText3)
                        .font(.appSubheadline)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // ── Step 4: photos ──

    @ViewBuilder
    private func photosStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Profile photo")
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.white)

                Button {
                    showAvatarPicker = true
                } label: {
                    ZStack {
                        if let image = viewModel.avatarImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                            LucideIcon(.camera, .lg)
                                .foregroundStyle(Color.vText3)
                        }
                    }
                    .frame(width: 104, height: 104)
                    .clipShape(Circle())
                    .overlay {
                        if viewModel.avatarImage == nil {
                            Circle().strokeBorder(
                                Color.white.opacity(0.16),
                                style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                            )
                        }
                    }
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Banner")
                    .font(.appCalloutSemibold)
                    .foregroundStyle(.white)

                Button {
                    showBannerPicker = true
                } label: {
                    ZStack {
                        if let image = viewModel.bannerImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Color.white.opacity(0.05)
                            VStack(spacing: 6) {
                                LucideIcon(.image, .lg)
                                    .foregroundStyle(Color.vText3)
                                Text("Tap to upload")
                                    .font(.appFootnote)
                                    .foregroundStyle(Color.vText3)
                            }
                        }
                    }
                    .aspectRatio(3, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if viewModel.bannerImage == nil {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(0.16),
                                    style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])
                                )
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            Text("Both are optional — you can add or change them any time from your profile.")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
        }
        .photosPicker(isPresented: $showAvatarPicker, selection: $avatarItem, matching: .images)
        .photosPicker(isPresented: $showBannerPicker, selection: $bannerItem, matching: .images)
        .onChange(of: avatarItem) { _, item in
            loadImage(item) { viewModel.avatarImage = $0 }
        }
        .onChange(of: bannerItem) { _, item in
            loadImage(item) { viewModel.bannerImage = $0 }
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
                .foregroundStyle(.white)
            HStack(spacing: 4) {
                Button {
                    leaveWizard()
                } label: {
                    Text("Sign in instead")
                        .foregroundStyle(.white)
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
                        .foregroundStyle(.white)
                        .fontWeight(.medium)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .font(.appFootnote)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            onClose: {}
        )
    }
    .preferredColorScheme(.dark)
    .environment(dependencies)
}
