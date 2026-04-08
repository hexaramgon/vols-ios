//
//  SettingsScreen.swift
//  Volspire
//
//

import DesignSystem
import Services
import SwiftUI

struct SettingsScreen: View {
    @Environment(Dependencies.self) var dependencies
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 14) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)

                    Text("Settings")
                        .font(.system(size: 26, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 8)
                .padding(.bottom, 24)

                // Account
                sectionHeader("Account")

                VStack(spacing: 0) {
                    settingsRow(icon: "person.fill", title: "Account Info", color: .brand)
                    divider
                    settingsRow(icon: "lock.fill", title: "Privacy", color: .brand)
                    divider
                    settingsRow(icon: "bell.fill", title: "Notifications", color: .orange)
                }
                .sectionCard()

                // Preferences
                sectionHeader("Preferences")

                VStack(spacing: 0) {
                    settingsRow(icon: "paintbrush.fill", title: "Appearance", color: .purple)
                    divider
                    settingsRow(icon: "speaker.wave.2.fill", title: "Audio Quality", color: .green)
                    divider
                    settingsRow(icon: "arrow.down.circle.fill", title: "Downloads", color: .blue)
                }
                .sectionCard()

                // Support
                sectionHeader("Support")

                VStack(spacing: 0) {
                    settingsRow(icon: "questionmark.circle.fill", title: "Help Center", color: .gray)
                    divider
                    settingsRow(icon: "doc.text.fill", title: "Terms of Service", color: .gray)
                    divider
                    settingsRow(icon: "hand.raised.fill", title: "Privacy Policy", color: .gray)
                }
                .sectionCard()

                // Sign Out
                Button {
                    Task {
                        await dependencies.authManager.signOut()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15))
                        Text("Sign Out")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(.systemGray6).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, ViewConst.screenPaddings)
                .padding(.top, 32)

                // App info
                VStack(spacing: 4) {
                    Text("Volspire")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("Version 1.0.0")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .enableSwipeBack()
        .gradientBackground()
    }

    // MARK: - Components

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ViewConst.screenPaddings + 4)
            .padding(.top, 24)
            .padding(.bottom, 8)
    }

    private var divider: some View {
        Divider()
            .padding(.leading, 52)
    }

    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        Button {
            // TODO: navigate to detail
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.systemGray3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Card Modifier

private extension View {
    func sectionCard() -> some View {
        self
            .background(Color(.systemGray6).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, ViewConst.screenPaddings)
    }
}
