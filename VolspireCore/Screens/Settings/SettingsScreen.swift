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

    var body: some View {
        List {
            Section("Account") {
                settingsRow(icon: "person.fill", title: "Account Info", color: .brand)
                settingsRow(icon: "lock.fill", title: "Privacy", color: .brand)
                settingsRow(icon: "bell.fill", title: "Notifications", color: .orange)
            }

            Section("Preferences") {
                settingsRow(icon: "paintbrush.fill", title: "Appearance", color: .purple)
                settingsRow(icon: "speaker.wave.2.fill", title: "Audio Quality", color: .green)
                settingsRow(icon: "arrow.down.circle.fill", title: "Downloads", color: .blue)
            }

            Section("Support") {
                settingsRow(icon: "questionmark.circle.fill", title: "Help Center", color: .gray)
                settingsRow(icon: "doc.text.fill", title: "Terms of Service", color: .gray)
                settingsRow(icon: "hand.raised.fill", title: "Privacy Policy", color: .gray)
            }

            Section {
                Button {
                    Task {
                        await dependencies.authManager.signOut()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Sign Out")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func settingsRow(icon: String, title: String, color: Color) -> some View {
        Button {
            // TODO: navigate to detail
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
