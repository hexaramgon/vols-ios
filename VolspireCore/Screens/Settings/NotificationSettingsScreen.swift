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
    @Environment(\.dismiss) private var dismiss
    @Environment(PlayerController.self) private var playerController
    @State private var viewModel = SettingsViewModel()

    /// Clears the custom tab bar + home indicator + (when present) the floating
    /// mini-player — none of which are part of this pushed screen's safe area.
    private var bottomInset: CGFloat {
        let mini = playerController.display.title.isEmpty ? 0 : ViewConst.compactNowPlayingHeight + 16
        return ViewConst.safeAreaInsets.bottom + 52 + mini
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Prefs gate PUSHES only — the in-app notifications feed always
                // shows everything (see get_user_notifications).
                Text("Choose which push notifications you receive. Everything still shows in your notifications feed.")
                    .font(.appFootnote)
                    .foregroundStyle(Color.vText3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, ViewConst.screenPaddings)
                    .padding(.top, 2)
                    .padding(.bottom, 18)

                card
            }
            .padding(.bottom, bottomInset)
        }
        .scrollIndicators(.hidden)
        .appNavBar(title: "Notifications") { dismiss() }
        .task { await viewModel.loadPreferences() }
    }
}

private extension NotificationSettingsScreen {
    var card: some View {
        VStack(spacing: 0) {
            ForEach(Array(NotificationPref.allCases.enumerated()), id: \.element.id) { index, pref in
                if index > 0 {
                    Rectangle().fill(.white.opacity(0.07)).frame(height: 1)
                }
                toggleRow(pref)
            }
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .redacted(reason: viewModel.prefsLoaded ? [] : .placeholder)
    }

    func toggleRow(_ pref: NotificationPref) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pref.title).font(.appBodyMedium).foregroundStyle(.white)
                Text(pref.subtitle).font(.appFootnote).foregroundStyle(Color.vText3).lineLimit(2)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { viewModel.isOn(pref) },
                set: { newValue in Task { await viewModel.toggle(pref, to: newValue) } }
            ))
            .labelsHidden()
            .tint(Color.brand)
            .disabled(!viewModel.prefsLoaded)
        }
        .padding(.vertical, 14)
    }
}

#Preview {
    @Previewable @State var playerController = PlayerController.stub
    NotificationSettingsScreen()
        .environment(playerController)
}
