//
//  TrackOptionsSheet.swift
//  Volspire
//
//  The single track "…" options sheet, used everywhere a track shows options so
//  they all match: a header (cover + title + artist + meta) over a divider and a
//  list of chevron action rows (the Library "Recently saved" style).
//

import DesignSystem
import SwiftUI

struct TrackOptionsSheet: View {
    struct Action: Identifiable {
        let id = UUID()
        var icon: LucideIcon.Name
        var title: String
        var subtitle: String? = nil
        var isDestructive: Bool = false
        /// `true`: show a spinner on the row while `perform` runs, then dismiss.
        var awaitsCompletion: Bool = false
        /// `true` (default): dismiss the sheet first, then run `perform` (for
        /// navigation / presenting another sheet). `false`: run `perform` now
        /// without dismissing — for share, which presents over this sheet.
        var dismissesSheet: Bool = true
        var perform: () async -> Void
    }

    let artwork: Artwork
    let title: String
    var artist: String? = nil
    var meta: String? = nil
    let actions: [Action]

    @Environment(\.dismiss) private var dismiss
    @State private var loadingID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title, subtitle: headerSubtitle) { dismiss() } leading: {
                ArtworkView(artwork, cornerRadius: 8)
                    .frame(width: 40, height: 40)
            }

            VStack(spacing: 0) {
                ForEach(actions) { row($0) }
            }
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .environment(\.colorScheme, .dark)
    }

    /// Artist and meta collapsed onto the single subtitle line the header allows.
    private var headerSubtitle: String? {
        let parts = [artist, meta].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ action: Action) -> some View {
        Button {
            if action.awaitsCompletion {
                Task {
                    loadingID = action.id
                    await action.perform()
                    loadingID = nil
                    dismiss()
                }
            } else if action.dismissesSheet {
                dismiss()
                Task {
                    // Let the sheet finish dismissing before navigating / presenting.
                    try? await Task.sleep(for: .seconds(0.3))
                    await action.perform()
                }
            } else {
                // Present over this sheet (e.g. share) — don't dismiss.
                Task { await action.perform() }
            }
        } label: {
            HStack(spacing: 14) {
                LucideIcon(action.icon, .lg)
                    .foregroundStyle(action.isDestructive ? Color.red : .primary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.appBody)
                        .foregroundStyle(action.isDestructive ? Color.red : .primary)
                    if let subtitle = action.subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if loadingID == action.id {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loadingID != nil)
    }
}
