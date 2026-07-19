//
//  NewPostView.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct NewPostView: View {
    @State private var contentHeight: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)

            Text("Upload New Content")
                .font(.appHeadline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            NewPostRow(
                icon: .music,
                title: "Track",
                description: "Upload a finished track with audio with cover art or from a video"
            ) {
                dismiss()
                onSelect("track")
            }
            NewPostRow(
                icon: .handshake,
                title: "Listing",
                description: "Post to the collab board — find a vocalist, producer, or any collaborator"
            ) {
                dismiss()
                onSelect("listing")
            }
        }
        .padding(.bottom, 20)
        .sheetBackground(dragIndicator: false)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: ContentHeightKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(ContentHeightKey.self) { height in
            contentHeight = height
        }
        .presentationDetents([.height(contentHeight)])
    }
}

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NewPostRow: View {
    let icon: LucideIcon.Name
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.06))
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.vBorder, lineWidth: 1)
                    LucideIcon(icon, .lg)
                        .foregroundStyle(Color.vText2)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appBodyMedium)
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.appFootnote)
                        .foregroundStyle(Color.vText2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                LucideIcon(.chevronRight, .sm)
                    .foregroundStyle(Color.vText3)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
