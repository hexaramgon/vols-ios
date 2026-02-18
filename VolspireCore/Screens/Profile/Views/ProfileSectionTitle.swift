//
//  ProfileSectionTitle.swift
//  Volspire
//
//

import SwiftUI

struct ProfileSectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(spacing: 5) {
            Text(text)
                .font(.system(size: 22, weight: .bold))
            Image(systemName: "chevron.right")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(.palette.textSecondary))
            Spacer()
        }
    }
}
