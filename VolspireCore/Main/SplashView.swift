//
//  SplashView.swift
//  Volspire
//
//  Launch splash — the Volspire wordmark on the app's base background, shown over
//  the auth restore and faded out once the app is ready.
//

import DesignSystem
import SwiftUI

struct SplashView: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            Color.vBase.ignoresSafeArea()

            // Soft brand glow behind the mark.
            RadialGradient(
                colors: [Color.brand.opacity(0.18), .clear],
                center: .center, startRadius: 0, endRadius: 240
            )
            .ignoresSafeArea()
            .opacity(appear ? 1 : 0)

            VolspireWordmark(height: 38)
                .foregroundStyle(.white)
                .opacity(appear ? 1 : 0)
                .scaleEffect(appear ? 1 : 0.92)
                .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        }
        .onAppear {
            withAnimation(.smooth(duration: 0.7)) { appear = true }
        }
    }
}

#Preview {
    SplashView()
}
