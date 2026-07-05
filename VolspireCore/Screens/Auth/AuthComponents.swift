//
//  AuthComponents.swift
//  Volspire
//
//  Shared pieces for the login/register pages, mirroring the web auth
//  screens: the radial top glow on black, labeled dark inputs (with the
//  eye toggle for passwords), the Google button, and the white CTA.
//

import DesignSystem
import SwiftUI

// MARK: - Background (web: black + radial ellipse glow at the top)

struct AuthBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            // radial-gradient(ellipse 80% 60% at 50% -10%, #163654, transparent 70%)
            EllipticalGradient(
                colors: [Color(red: 0.086, green: 0.212, blue: 0.329), .clear],
                center: UnitPoint(x: 0.5, y: 0),
                startRadiusFraction: 0,
                endRadiusFraction: 0.7
            )
            .scaleEffect(x: 1.6, y: 1.0, anchor: .top)
            .frame(height: UIScreen.size.height * 0.55)
            .offset(y: -UIScreen.size.height * 0.08)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Labeled input

struct AuthTextField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var autocapitalize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.appCallout)
                .foregroundStyle(Color.vText2)

            TextField(
                "",
                text: $text,
                prompt: Text(prompt).foregroundStyle(Color.vText3)
            )
            .font(.appBodyLarge)
            .foregroundStyle(.white)
            .tint(.white)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(autocapitalize ? .sentences : .never)
            .autocorrectionDisabled()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.vBorder, lineWidth: 1))
        }
    }
}

// MARK: - Labeled secure input with the web's eye toggle

struct AuthSecureField: View {
    let label: String
    @Binding var text: String
    var contentType: UITextContentType = .password

    @State private var revealed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.appCallout)
                .foregroundStyle(Color.vText2)

            HStack(spacing: 8) {
                Group {
                    if revealed {
                        TextField("", text: $text)
                    } else {
                        SecureField("", text: $text)
                    }
                }
                .font(.appBodyLarge)
                .foregroundStyle(.white)
                .tint(.white)
                .textContentType(contentType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

                Button {
                    revealed.toggle()
                } label: {
                    LucideIcon(revealed ? .eyeOff : .eye, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .background(Color(white: 0.09))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.vBorder, lineWidth: 1))
        }
    }
}

// MARK: - Buttons

/// The white primary CTA (web's Button).
struct AuthPrimaryButton: View {
    let title: String
    var loadingTitle: String = "…"
    var isLoading = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.black).controlSize(.small)
                }
                Text(isLoading ? loadingTitle : title)
                    .font(.appHeadline)
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(.white, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled && !isLoading ? 0.5 : 1)
    }
}

/// Google sign-in — dark button with the colored G (web GoogleButton).
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
            .frame(height: 48)
            .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.vBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

// MARK: - Error banner (web: red-950/30 card with border, not bare text)

/// Auth-screen error — now just the shared `ErrorBanner` (kept as a named alias
/// so the login/register call sites don't change).
struct AuthErrorBanner: View {
    let message: String
    var body: some View { ErrorBanner(message) }
}

// MARK: - "or" divider

struct AuthOrDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text("or")
                .font(.appFootnote)
                .foregroundStyle(Color.vText3)
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
    }
}
