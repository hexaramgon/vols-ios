//
//  MeasureSizeModifier.swift
//  Volspire
//
//

import SwiftUI

struct SizeReader: ViewModifier {
    @Binding var size: CGSize

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newVal in
                size = newVal
            }
    }
}

extension View {
    func sizeReader(size: Binding<CGSize>) -> some View {
        modifier(SizeReader(size: size))
    }
}
