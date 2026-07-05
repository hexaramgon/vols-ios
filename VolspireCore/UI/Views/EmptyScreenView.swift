//
//  EmptyScreenView.swift
//  Volspire
//
//

import SwiftUI

struct EmptyScreenView: View {
    let systemImage: String
    let title: String
    let description: String

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(Color(.palette.stroke))
            Text(title)
                .font(.appTitleSemibold)
                .padding(.top, 16)
            Text(description)
                .font(.appBodyLarge)
                .padding(.top, 8)
                .foregroundStyle(Color(.palette.textTertiary))
        }
        .multilineTextAlignment(.center)
    }
}

#Preview {
    EmptyScreenView(
        systemImage: "icloud.and.arrow.down",
        title: "Download Music to Listen Offline",
        description: "Downloaded tracks will appear here."
    )
}
