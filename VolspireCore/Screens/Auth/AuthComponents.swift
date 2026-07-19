//
//  AuthComponents.swift
//  Volspire
//
//  Auth UI kit, v2 — flat dark canvas, grouped input cards (iOS-style rows
//  divided by hairlines, placeholder-only), send-accent gradient CTA, flat
//  provider buttons, and a segmented 6-digit code field.
//

import AuthenticationServices
import DesignSystem
import SwiftUI
import UIKit

// MARK: - Canvas

/// Flat app-base background — the auth pages live in the same world as the
/// rest of the app, no special glow.
struct AuthCanvas: View {
    var body: some View {
        Color.vBase.ignoresSafeArea()
    }
}

// MARK: - Press feedback

struct AuthPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Grouped input card

/// One rounded card holding input rows separated by hairlines — like a
/// grouped iOS form, not individual labeled boxes.
struct AuthFieldGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Hairline between rows in an `AuthFieldGroup`, inset past the icon column.
struct AuthRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.5)
            .padding(.leading, 50)
    }
}

/// A text row inside an `AuthFieldGroup` — icon + placeholder, no label.
struct AuthRow: View {
    let icon: LucideIcon.Name
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalize = false

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            LucideIcon(icon, .md)
                .foregroundStyle(focused ? .white : Color.vText3)
            TextField(
                "",
                text: $text,
                prompt: Text(placeholder).foregroundStyle(Color.vText3)
            )
            .font(.appBody)
            .foregroundStyle(.white)
            .tint(.white)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled()
            .focused($focused)
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .animation(.easeInOut(duration: 0.15), value: focused)
    }
}

/// A secure row inside an `AuthFieldGroup`, with the reveal toggle.
struct AuthSecureRow: View {
    let placeholder: String
    @Binding var text: String
    var contentType: UITextContentType = .password

    @State private var revealed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            LucideIcon(.lock, .md)
                .foregroundStyle(focused ? .white : Color.vText3)
            Group {
                if revealed {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.vText3))
                } else {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(Color.vText3))
                }
            }
            .font(.appBody)
            .foregroundStyle(.white)
            .tint(.white)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)

            Button {
                revealed.toggle()
            } label: {
                LucideIcon(revealed ? .eyeOff : .eye, .md)
                    .foregroundStyle(Color.vText3)
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .frame(height: 54)
        .animation(.easeInOut(duration: 0.15), value: focused)
    }
}

// MARK: - Primary CTA (send-accent gradient, the app's action color)

struct AuthCTA: View {
    let title: String
    var loadingTitle: String = "…"
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white).controlSize(.small)
                }
                Text(isLoading ? loadingTitle : title)
                    .font(.appHeadline)
            }
            .foregroundStyle(isDisabled && !isLoading ? Color.vText3 : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isDisabled && !isLoading
                            ? AnyShapeStyle(Color.white.opacity(0.06))
                            : AnyShapeStyle(LinearGradient.sendAccent)
                    )
            }
        }
        .buttonStyle(AuthPress())
        .disabled(isDisabled || isLoading)
        .animation(.easeInOut(duration: 0.2), value: isDisabled)
    }
}

// MARK: - Provider buttons (flat, matching the field cards)

/// Custom "Continue with Apple" — official wording + logo per the HIG's
/// custom-button allowance; flat dark style to match the page.
struct AppleAuthButton: View {
    let label: String
    let onCredential: (ASAuthorizationAppleIDCredential) -> Void
    let onError: (Error) -> Void

    @State private var coordinator = AppleSignInCoordinator()

    var body: some View {
        Button {
            coordinator.start(onCredential: onCredential, onError: onError)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 17, weight: .medium))
                    .padding(.bottom, 2) // optical centre — the glyph sits low
                Text(label)
                    .font(.appBodyMedium)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(AuthPress())
    }
}

/// "Continue with Google" — same flat card style.
struct GoogleAuthButton: View {
    let label: String
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image("google-logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 17, height: 17)
                Text(isLoading ? "Signing in…" : label)
                    .font(.appBodyMedium)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(AuthPress())
        .disabled(isLoading)
    }
}

/// Drives the native Apple ID authorization sheet for `AppleAuthButton`.
@MainActor
final class AppleSignInCoordinator: NSObject {
    private var onCredential: ((ASAuthorizationAppleIDCredential) -> Void)?
    private var onError: ((Error) -> Void)?

    func start(
        onCredential: @escaping (ASAuthorizationAppleIDCredential) -> Void,
        onError: @escaping (Error) -> Void
    ) {
        self.onCredential = onCredential
        self.onError = onError
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    // Delegate callbacks arrive on the main thread for a UI-presented
    // controller — `assumeIsolated` is an assertion, not a thread hop.
    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        MainActor.assumeIsolated {
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                onCredential?(credential)
            }
        }
    }

    nonisolated func authorizationController(
        controller _: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        MainActor.assumeIsolated {
            // A dismissed sheet is a user choice, not an error to surface.
            if (error as NSError).code == ASAuthorizationError.canceled.rawValue { return }
            onError?(error)
        }
    }

    nonisolated func presentationAnchor(for _: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            guard let scene else {
                // Unreachable: the button that started the flow is on screen,
                // so a connected window scene exists.
                preconditionFailure("Apple sign-in presented with no connected window scene")
            }
            return scene.keyWindow ?? scene.windows.first ?? UIWindow(windowScene: scene)
        }
    }
}

// MARK: - Wizard chrome (back bar + step scaffold + pinned bottom link)

/// The auth wizards' top bar (register + password reset): the back chevron —
/// same Lucide glyph + token as the shared `BackButton`, in a 44pt target.
/// The bar keeps its height when the chevron is hidden (verify/done steps)
/// so step transitions don't shift vertically.
struct AuthWizardBackBar: View {
    /// Shows the chevron; the bar itself always occupies its height.
    var canGoBack = true
    /// Disables the chevron mid-request.
    var disabled = false
    /// Step-0 exits vs. step-back stays with the caller.
    let onBack: () -> Void

    var body: some View {
        HStack {
            if canGoBack {
                Button(action: onBack) {
                    LucideIcon(.chevronLeft, size: ViewConst.backIconSize)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(disabled)
            }
            Spacer()
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

/// One wizard step's scroll shell: left-aligned appTitleXXL heading + subtitle,
/// the step's fields, an optional inline error, and an optional footer (notice
/// + CTA), centered at a 440pt max width with the shared keyboard-friendly
/// scroll behaviour. Shared by the register wizard and the password reset.
struct AuthStepPage<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    var error: String?
    /// First steps pass extra clearance for the pinned bottom link.
    var bottomPadding: CGFloat = 32
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    init(
        title: String,
        subtitle: String,
        error: String? = nil,
        bottomPadding: CGFloat = 32,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.error = error
        self.bottomPadding = bottomPadding
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.appTitleXXL)
                    .foregroundStyle(.white)
                    .padding(.top, 12)

                Text(subtitle)
                    .font(.appCalloutRegular)
                    .foregroundStyle(Color.vText2)
                    .padding(.top, 6)

                content
                    .padding(.top, 28)

                if let error {
                    ErrorBanner(error)
                        .padding(.top, 14)
                }

                footer
            }
            .padding(.horizontal, 24)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        // No rubber-band on steps that fit the screen — keyboard-driven scroll
        // adjustments stay pinned instead of bouncing the page.
        .scrollBounceBehavior(.basedOnSize)
    }
}

extension AuthStepPage where Footer == EmptyView {
    init(
        title: String,
        subtitle: String,
        error: String? = nil,
        bottomPadding: CGFloat = 32,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title, subtitle: subtitle, error: error,
            bottomPadding: bottomPadding, content: content, footer: { EmptyView() }
        )
    }
}

/// The bottom pinned prompt + action link ("New to Volspire? Create account"),
/// for use inside a full-screen `.overlay` on an auth page.
// Overlay (not safeAreaInset): the link stays anchored to the screen
// bottom and the keyboard simply covers it, instead of riding up.
// The content here is FULL-HEIGHT for the keyboard opt-out to work —
// ignoresSafeArea only expands views whose bounds touch the ignored
// region, so a bare link would still be pushed up.
struct AuthBottomLink: View {
    let prompt: String
    let action: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(prompt)
                    .foregroundStyle(Color.vText3)
                Text(action)
                    .foregroundStyle(.white)
                    .fontWeight(.semibold)
            }
            .font(.appCalloutRegular)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

// MARK: - Segmented 6-digit code field

/// Six digit boxes over an invisible text field — autofill from Messages
/// still works (`oneTimeCode`), and the active box brightens. Input is
/// digit-filtered and capped at 6 inside the field; `onFilled` fires when
/// the sixth digit lands (the shared auto-submit).
struct AuthCodeField: View {
    @Binding var code: String
    var disabled = false
    /// Runs on every edit, before the fill check (e.g. clearing a stale error).
    var onEdit: () -> Void = {}
    /// The auto-submit hook — fires whenever an edit leaves all 6 digits set.
    var onFilled: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                let digits = Array(code)
                let active = focused && index == min(code.count, 5)
                Text(index < digits.count ? String(digits[index]) : " ")
                    .font(.appTitle2)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(
                        Color.white.opacity(active ? 0.12 : 0.05),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: code)
        .animation(.easeInOut(duration: 0.15), value: focused)
        .overlay {
            // Invisible input driving the boxes.
            TextField("", text: sanitizedCode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .foregroundStyle(.clear)
                .tint(.clear)
                .focused($focused)
                .disabled(disabled)
        }
        .contentShape(.rect)
        .onTapGesture { focused = true }
    }

    /// Digits-only, capped at 6, firing the edit/auto-submit hooks.
    private var sanitizedCode: Binding<String> {
        Binding(
            get: { code },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(6))
                code = digits
                onEdit()
                if digits.count == 6 { onFilled() }
            }
        )
    }
}

// MARK: - Resend-code button

/// The "Didn't get a code? Resend" button under a code field, with its
/// "Sending…" and green "New code sent" states. Disabled once not idle.
struct AuthResendButton: View {
    enum ResendState { case idle, sending, sent }

    let state: ResendState
    let onResend: () -> Void

    var body: some View {
        Button(action: onResend) {
            Group {
                switch state {
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
        .disabled(state != .idle)
    }
}

// MARK: - Small text pieces

/// Centered "or" microcopy between the form and the provider buttons.
struct AuthOrDivider: View {
    var body: some View {
        Text("or continue with")
            .font(.appCaption)
            .foregroundStyle(Color.vText3)
            .frame(maxWidth: .infinity)
    }
}

/// "Passwords must match" — the caption under confirm-password fields
/// (register + password reset).
struct AuthPasswordMismatchLabel: View {
    var body: some View {
        Text("Passwords must match")
            .font(.appFootnote)
            .foregroundStyle(Color.vError)
    }
}
