//
//  RegisterScreen.swift
//  Volspire
//
//  Five-step signup wizard mirroring the web's register page: step header
//  with progress dots, sliding step content, password rules checklist,
//  username availability, OTP verification, and the photos step.
//

import AuthenticationServices
import DesignSystem
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

    @State private var avatarItem: PhotosPickerItem?
    @State private var bannerItem: PhotosPickerItem?
    @State private var showAvatarPicker = false
    @State private var showBannerPicker = false

    var body: some View {
        wizard(viewModel)
    }

    private func wizard(_ viewModel: RegisterViewModel) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                VolspireWordmark(height: 30)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 16)

                Text(RegisterViewModel.stepTitles[viewModel.step])
                    .font(.appTitleXL)
                    .foregroundStyle(.white)
                    .padding(.top, 36)
                    .animation(nil, value: viewModel.step)

                Text(RegisterViewModel.stepSubtitles[viewModel.step])
                    .font(.appCalloutRegular)
                    .foregroundStyle(Color.vText2)
                    .padding(.top, 8)
                    .animation(nil, value: viewModel.step)

                if viewModel.step < RegisterViewModel.totalSteps {
                    stepIndicator(viewModel)
                        .padding(.top, 24)
                }

                stepContent(viewModel)
                    .padding(.top, 28)

                if let error = viewModel.error, !viewModel.existingAccount {
                    AuthErrorBanner(message: error)
                        .padding(.top, 16)
                }

                if viewModel.existingAccount {
                    existingAccountNotice(viewModel)
                        .padding(.top, 16)
                }

                footer(viewModel)
                    .padding(.top, 28)

                if viewModel.step == 0 {
                    Button {
                        leaveWizard()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundStyle(Color.vText3)
                            Text("Sign in")
                                .foregroundStyle(.white)
                                .fontWeight(.medium)
                        }
                        .font(.appCalloutRegular)
                        .frame(maxWidth: .infinity)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                }

                Spacer(minLength: 48)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: 440)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Closes the wizard. If a held session exists (user verified but bailed
    /// early), reveal it so they land in the app rather than limbo.
    private func leaveWizard() {
        Task {
            await dependencies.authManager.finishOnboarding()
            onClose()
        }
    }

    // MARK: - Step indicator (web: check / current / upcoming circles)

    private func stepIndicator(_ viewModel: RegisterViewModel) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<RegisterViewModel.totalSteps, id: \.self) { index in
                stepDot(index, current: viewModel.step)
                if index < RegisterViewModel.totalSteps - 1 {
                    Rectangle()
                        .fill(index < viewModel.step ? Color.white.opacity(0.35) : Color.white.opacity(0.12))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .animation(.easeOut(duration: 0.25), value: viewModel.step)
    }

    @ViewBuilder
    private func stepDot(_ index: Int, current: Int) -> some View {
        ZStack {
            if index < current {
                Circle().fill(Color.white.opacity(0.12))
                LucideIcon(.check, .xs)
                    .foregroundStyle(Color.vText2)
            } else if index == current {
                Circle().fill(.white)
                Text("\(index + 1)")
                    .font(.appCaptionBold)
                    .foregroundStyle(.black)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                Text("\(index + 1)")
                    .font(.appCaptionBold)
                    .foregroundStyle(Color.vText3)
            }
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Step content

    @ViewBuilder
    private func stepContent(_ viewModel: RegisterViewModel) -> some View {
        Group {
            switch viewModel.step {
            case 0: emailStep(viewModel)
            case 1: passwordStep(viewModel)
            case 2: profileStep(viewModel)
            case 3: verifyStep(viewModel)
            case 4: photosStep(viewModel)
            default: EmptyView()
            }
        }
        .id(viewModel.step)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .offset(x: viewModel.slideForward ? 40 : -40)),
                removal: .opacity.combined(with: .offset(x: viewModel.slideForward ? -40 : 40))
            )
        )
    }

    // ── Step 0: email ──

    @ViewBuilder
    private func emailStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    if case .success(let authorization) = result,
                       let credential = authorization.credential as? ASAuthorizationAppleIDCredential
                    {
                        Task { await dependencies.authManager.signInWithApple(credential: credential) }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                GoogleAuthButton(label: "Sign up with Google") {
                    Task { await dependencies.authManager.signInWithGoogle() }
                }
            }

            AuthOrDivider()

            AuthTextField(
                label: "Email address",
                text: Binding(get: { viewModel.email }, set: { viewModel.email = $0 }),
                keyboard: .emailAddress,
                contentType: .emailAddress
            )
        }
    }

    // ── Step 1: password + rules ──

    @ViewBuilder
    private func passwordStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            AuthSecureField(
                label: "Password",
                text: Binding(get: { viewModel.password }, set: { viewModel.password = $0 }),
                contentType: .newPassword
            )

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
            }

            AuthSecureField(
                label: "Confirm password",
                text: Binding(get: { viewModel.confirmPassword }, set: { viewModel.confirmPassword = $0 }),
                contentType: .newPassword
            )

            if !viewModel.confirmPassword.isEmpty, !viewModel.passwordsMatch {
                Text("Passwords must match")
                    .font(.appCaption)
                    .foregroundStyle(UploadTheme.errorText)
            }
        }
    }

    // ── Step 2: username + roles + location ──

    @ViewBuilder
    private func profileStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Username")
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)

                HStack(spacing: 8) {
                    TextField(
                        "",
                        text: Binding(
                            get: { viewModel.username },
                            set: { viewModel.usernameChanged($0) }
                        )
                    )
                    .font(.appBodyLarge)
                    .foregroundStyle(.white)
                    .tint(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    switch viewModel.usernameStatus {
                    case .checking:
                        ProgressView().controlSize(.small).tint(Color.vText3)
                    case .available:
                        LucideIcon(.check, .sm).foregroundStyle(Color.green)
                    case .taken:
                        LucideIcon(.x, .sm).foregroundStyle(UploadTheme.errorText)
                    case .idle:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(white: 0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.vBorder, lineWidth: 1))

                if viewModel.usernameStatus == .taken {
                    Text("That username is already taken.")
                        .font(.appFootnote)
                        .foregroundStyle(UploadTheme.errorText)
                } else if viewModel.usernameStatus == .available {
                    Text("Username is available.")
                        .font(.appFootnote)
                        .foregroundStyle(Color.green)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your Roles (optional)")
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)
                Text("Helps people find your work. Pick up to \(ProfileRoles.max), or skip.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)

                ChipFlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(ProfileRoles.all, id: \.self) { role in
                        let selected = viewModel.tags.contains(role)
                        Button {
                            viewModel.toggleTag(role)
                        } label: {
                            Text(role)
                                .font(.appSubheadline)
                                .foregroundStyle(selected ? .white : Color.vText3)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Capsule().fill(selected ? Color.white.opacity(0.12) : .clear))
                                .overlay(
                                    Capsule().strokeBorder(
                                        selected ? Color.white.opacity(0.3) : UploadTheme.border,
                                        lineWidth: 1
                                    )
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            AuthTextField(
                label: "Location (optional)",
                text: Binding(get: { viewModel.location }, set: { viewModel.location = $0 }),
                prompt: "City, Country",
                autocapitalize: true
            )
        }
    }

    // ── Step 3: verify email (OTP) ──

    @ViewBuilder
    private func verifyStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(spacing: 22) {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                LucideIcon(.mail, .lg).foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)
            .frame(maxWidth: .infinity)

            Text("We sent a 6-digit code to \(Text(viewModel.email).foregroundStyle(.white)). Enter it below to continue.")
                .foregroundStyle(Color.vText2)
                .font(.appCalloutRegular)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            TextField("", text: Binding(
                get: { viewModel.otpCode },
                set: { newValue in
                    let digits = String(newValue.filter(\.isNumber).prefix(6))
                    viewModel.otpCode = digits
                    viewModel.verifyError = nil
                    if digits.count == 6 {
                        Task { await viewModel.verifyOtp() }
                    }
                }
            ), prompt: Text("••••••").foregroundStyle(Color.vText3))
                .font(.appLargeTitleSemibold)
                .monospacedDigit()
                .tracking(10)
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.vertical, 12)
                .background(Color(white: 0.09))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.vBorder, lineWidth: 1))
                .disabled(viewModel.loading)

            AuthPrimaryButton(
                title: "Verify",
                loadingTitle: "Verifying…",
                isLoading: viewModel.loading,
                isDisabled: viewModel.otpCode.count != 6
            ) {
                Task { await viewModel.verifyOtp() }
            }

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

            if let verifyError = viewModel.verifyError {
                AuthErrorBanner(message: verifyError)
            }

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

    // ── Step 4: photos ──

    @ViewBuilder
    private func photosStep(_ viewModel: RegisterViewModel) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Profile photo (optional)")
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)

                Button {
                    showAvatarPicker = true
                } label: {
                    photoBox(image: viewModel.avatarImage, icon: .camera)
                        .frame(width: 110, height: 110)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Banner image (optional)")
                    .font(.appCallout)
                    .foregroundStyle(Color.vText2)

                Button {
                    showBannerPicker = true
                } label: {
                    photoBox(image: viewModel.bannerImage, icon: .image)
                        .aspectRatio(3, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
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

    private func photoBox(image: UIImage?, icon: LucideIcon.Name) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color(white: 0.09)
                VStack(spacing: 6) {
                    LucideIcon(icon, .lg)
                        .foregroundStyle(Color.vText3)
                    Text("Tap to upload")
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText3)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(image == nil ? UploadTheme.border : Color.white.opacity(0.15), lineWidth: 1)
        )
        .contentShape(.rect)
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
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.vBorder, lineWidth: 1))
    }

    // MARK: - Footer navigation

    @ViewBuilder
    private func footer(_ viewModel: RegisterViewModel) -> some View {
        // The verify step owns its own buttons — no Continue to bypass it.
        if viewModel.step != 3 {
            HStack(spacing: 10) {
                if viewModel.step > 0, viewModel.step < RegisterViewModel.totalSteps {
                    Button {
                        viewModel.goBack()
                    } label: {
                        HStack(spacing: 6) {
                            LucideIcon(.chevronLeft, .sm)
                            Text("Back")
                                .font(.appBodyMedium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(height: 48)
                        .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.vBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                switch viewModel.step {
                case 0, 1, 2:
                    AuthPrimaryButton(
                        title: "Continue",
                        loadingTitle: "Creating account…",
                        isLoading: viewModel.loading,
                        isDisabled: !viewModel.canContinue
                    ) {
                        Task { await viewModel.goNext() }
                    }
                case 4:
                    AuthPrimaryButton(
                        title: viewModel.finishButtonTitle,
                        loadingTitle: "Creating account…",
                        isLoading: viewModel.loading
                    ) {
                        Task { await viewModel.finish() }
                    }
                default:
                    AuthPrimaryButton(title: "Continue to Profile") {
                        Task { await viewModel.enterApp() }
                    }
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    ZStack {
        AuthBackground()
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
