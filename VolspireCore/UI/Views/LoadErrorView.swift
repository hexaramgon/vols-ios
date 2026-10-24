//
//  LoadErrorView.swift
//  Volspire
//
//  Shared "couldn't get a response" state — shown when a screen's load fails and
//  there's nothing to display (offline / server error). Used by Home, Marketplace
//  and Library so the offline experience is identical everywhere.
//

import DesignSystem
import SwiftUI

struct LoadErrorView: View {
    var icon: LucideIcon.Name = .triangleAlert
    var title: String = "Couldn't load"
    var message: String = "Check your connection and try again."
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            LucideIcon(icon, .xxl)
                .foregroundStyle(Color.vText3)
                .frame(width: 64, height: 64)
                .background(Color.vSurface, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
                .padding(.bottom, 2)
            Text(title).font(.appHeadline).foregroundStyle(Color.vText)
            Text(message)
                .font(.appCalloutRegular).foregroundStyle(Color.vText2).multilineTextAlignment(.center)
            Button(action: retry) {
                Text("Try Again")
                    .font(.appFootnoteSemibold).foregroundStyle(Color.vOnInverse)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.vInverse, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

/// The app-standard **inline** error banner — a triangle-alert icon + message in
/// a soft red-950 card (`vErrorFill`). Use for form / sheet / field errors instead of ad-hoc
/// red `Text`. (Full-screen "couldn't load" failures use `LoadErrorView`.)
struct ErrorBanner: View {
    let message: String

    init(_ message: String) { self.message = message }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LucideIcon(.triangleAlert, .sm)
                .padding(.top, 1)
            Text(message)
                .font(.appSubheadline)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Color.vError)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.vErrorFill, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
