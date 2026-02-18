//
//  ProfileBar.swift
//  Volspire
//
//

import SwiftUI

struct ProfileBar: View {
    let title: String
    let controsOpacity: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                gradient: Gradient(colors: [.black.opacity(0), .black.opacity(0.3)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Const.height)

            HStack(spacing: 0) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
            .opacity(controsOpacity)
        }
    }

    enum Const {
        static var height: CGFloat { 88 }
    }
}
