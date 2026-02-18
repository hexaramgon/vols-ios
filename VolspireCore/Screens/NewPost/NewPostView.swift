//
//  NewPostView.swift
//  Volspire
//
//

import DesignSystem
import SwiftUI

struct NewPostView: View {
    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 20)

            NewPostRow(
                icon: "camera.fill",
                title: "Photo",
                description: "Share a photo from your camera or library"
            )
            Divider().padding(.leading, 60)
            NewPostRow(
                icon: "waveform",
                title: "Audio",
                description: "Record or upload an audio clip"
            )
            Divider().padding(.leading, 60)
            NewPostRow(
                icon: "text.alignleft",
                title: "Text",
                description: "Write a text post to share with others"
            )

            Spacer()
        }
        .presentationDetents([.medium])
    }
}

private struct NewPostRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
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
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(.rect)
    }
}

#Preview {
    NewPostView()
}
