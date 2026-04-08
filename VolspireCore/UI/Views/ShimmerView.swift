//
//  ShimmerView.swift
//  Volspire
//

import SwiftUI

struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        Color(.systemGray5)
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        Color.white.opacity(0.3),
                        .clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: phase * 300)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}
