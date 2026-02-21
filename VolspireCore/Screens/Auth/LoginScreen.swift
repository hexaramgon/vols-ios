//
//  LoginScreen.swift
//  Volspire
//
//

import AuthenticationServices
import DesignSystem
import Services
import SwiftUI

struct LoginScreen: View {
    @Environment(Dependencies.self) var dependencies
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var isLoading = false

    private var authManager: AuthManager {
        dependencies.authManager
    }

    var body: some View {
        ZStack {
            // Full branded background
            LinearGradient(
                colors: [
                    Color.brand,
                    Color.brand.opacity(0.7),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 100)

                    // App icon
                    Image("Volspire", bundle: nil)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .shadow(color: .black.opacity(0.3), radius: 20, y: 10)

                    Text("Volspire")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 16)

                    Text("Discover, create, and share music")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 4)

                    Spacer().frame(height: 50)

                    // Social sign-in buttons
                    VStack(spacing: 12) {
                        // Sign in with Apple
                        SignInWithAppleButton(.signIn) { request in
                            request.requestedScopes = [.fullName, .email]
                        } onCompletion: { result in
                            handleAppleSignIn(result)
                        }
                        .signInWithAppleButtonStyle(.white)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        // Sign in with Google
                        Button {
                            Task {
                                isLoading = true
                                await authManager.signInWithGoogle()
                                isLoading = false
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                    .font(.system(size: 18, weight: .medium))
                                Text("Sign in with Google")
                                    .font(.system(size: 17, weight: .medium))
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 32)

                    // Divider
                    HStack {
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 1)
                        Text("or")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 12)
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)

                    // Email form
                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            Task {
                                isLoading = true
                                if isSignUp {
                                    await authManager.signUpWithEmail(email: email, password: password)
                                } else {
                                    await authManager.signInWithEmail(email: email, password: password)
                                }
                                isLoading = false
                            }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.brand)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(email.isEmpty || password.isEmpty || isLoading)
                        .opacity(email.isEmpty || password.isEmpty ? 0.6 : 1)
                    }
                    .padding(.horizontal, 32)

                    // Error message
                    if let error = authManager.errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 12)
                    }

                    // Toggle sign up / sign in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            authManager.setError(nil)
                        }
                    } label: {
                        Text(isSignUp ? "Already have an account? **Sign In**" : "Don't have an account? **Sign Up**")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.top, 20)

                    Spacer().frame(height: 60)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                Task {
                    isLoading = true
                    await authManager.signInWithApple(credential: credential)
                    isLoading = false
                }
            }
        case .failure(let error):
            dependencies.authManager.setError(error.localizedDescription)
        }
    }
}

#Preview {
    @Previewable @State var dependencies = Dependencies.stub
    LoginScreen()
        .environment(dependencies)
}
