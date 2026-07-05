//
//  FloatingActionButton.swift
//  Volspire
//
//  A circular bottom-right floating action button. Pinned with a consistent
//  inset above the tab bar + mini-player so it stays in the exact same spot
//  across screens (e.g. the Workspace folder list and a folder's contents).
//

import DesignSystem
import SwiftUI

struct FloatingActionButton: View {
    let systemImage: String
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 56, height: 56)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        // Small lift off the bottom safe area. Because the button is overlaid on
        // the tab's NavigationStack, that safe area already includes the tab bar
        // and the mini-player — so it sits low and rises automatically when the
        // mini-player appears, no manual offset needed.
        .padding(.trailing, 20)
        .padding(.bottom, 18)
    }
}
