//
//  NotificationSettingsScreen.swift
//  Volspire
//
//  Settings → Notifications. Per-event toggles backed by the
//  get/update_notification_preferences RPCs, plus the iOS permission state
//  (the toggles do nothing while notifications are off for the app).
//

import DesignSystem
import Services
import SwiftUI
import UIKit

struct NotificationSettingsScreen: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(\.scenePhase) private var scenePhase
    private let push = PushNotificationManager.shared

    var body: some View {
        SettingsSectionPage(title: "Notifications") {
            if push.authorizationStatus == .denied || push.authorizationStatus == .notDetermined {
                permissionGroup
            }

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
        .task { await push.refreshStatus() }
        // Back from iOS Settings: pick up a change made there.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await push.refreshStatus() } }
        }
    }

    /// Shown while iOS won't deliver this app's notifications. Denied can only
    /// be undone in iOS Settings; not-yet-asked shows the system prompt here.
    private var permissionGroup: some View {
        let denied = push.authorizationStatus == .denied
        return SettingsGroup(title: "Push notifications") {
            SettingsRow(
                title: "Notifications are off",
                caption: denied
                    ? "Turn them on for Volspire in iOS Settings to get these alerts."
                    : "Turn them on to get these alerts on this device."
            ) {
                Button {
                    if denied {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } else {
                        Task { await push.requestPermission() }
                    }
                } label: {
                    CapsuleButtonLabel(title: denied ? "Open Settings" : "Turn on", style: .primary)
                }
                .buttonStyle(.plain)
            }
        }
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
