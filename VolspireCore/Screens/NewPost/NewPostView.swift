//
//  NewPostView.swift
//  Volspire
//
//

import DesignSystem
import Services
import SwiftUI

struct NewPostView: View {
    @State private var contentHeight: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)

            Text("Upload New Content")
                .font(.system(size: 20, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

            NewPostRow(
                icon: "music.note",
                title: "Track",
                description: "Upload a finished track with audio with cover art or from a video"
            ) {
                dismiss()
                onSelect("track")
            }
            NewPostRow(
                icon: "square.grid.2x2.fill",
                title: "Sample Pack",
                description: "Share a collection of sounds, loops or presets"
            ) {
                dismiss()
                onSelect("sample_pack")
            }
            NewPostRow(
                icon: "sparkles",
                title: "Skill Highlight",
                description: "Showcase your production skills or techniques"
            ) {
                dismiss()
                onSelect("skill_highlight")
            }
        }
        .padding(.bottom, 20)
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
    let icon: String
    let title: String
    let description: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Color.brand)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NewPostView(onSelect: { _ in })
}
