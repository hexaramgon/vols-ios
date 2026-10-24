//
//  NotificationSettingsScreen.swift
//  Volspire
//
//  Settings → Notifications. Per-event toggles backed by the
//  get/update_notification_preferences RPCs.
//

import DesignSystem
import SwiftUI

struct NotificationSettingsScreen: View {
    @State private var viewModel = SettingsViewModel()

    var body: some View {
        SettingsSectionPage(title: "Notifications") {
            // Prefs gate PUSHES only — the in-app notifications feed always
            // shows everything (see get_user_notifications).
            SettingsGroup(
                title: "Email & push alerts",
                caption: "Choose which activity reaches you outside the app."
            ) {
                ForEach(Array(NotificationPref.visibleCases.enumerated()), id: \.element.id) { index, pref in
                    if index > 0 { SettingsDivider() }
                    toggleRow(pref)
                }
            }
            .redacted(reason: viewModel.prefsLoaded ? [] : .placeholder)

            if let error = viewModel.saveError {
                ErrorBanner(error)
            }
        }
        .task { await viewModel.loadPreferences() }
    }

    private func toggleRow(_ pref: NotificationPref) -> some View {
        SettingsRow(title: pref.title, caption: pref.subtitle) {
            Toggle("", isOn: Binding(
                get: { viewModel.isOn(pref) },
                set: { newValue in Task { await viewModel.toggle(pref, to: newValue) } }
            ))
            .labelsHidden()
            .toggleStyle(.ink)
            .disabled(!viewModel.prefsLoaded)
        }
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    NotificationSettingsScreen()
        .environment(playerController)
}
