//
//  ProfileMiniHeader.swift
//  Volspire
//
//  Solid bar that crossfades in behind the (system-centred) nav title + back
//  button as the hero scrolls past — matches the app's standard nav header.
//

import DesignSystem
import SwiftUI

struct ProfileMiniHeader: View {
    let opacity: Double

    var body: some View {
        Color(white: 0.1)
            .frame(height: ViewConst.safeAreaInsets.top + 44)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5) }
            .opacity(opacity)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }
}
