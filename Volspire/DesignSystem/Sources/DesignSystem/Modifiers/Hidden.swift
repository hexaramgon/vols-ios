//
//  Hidden.swift
//  Volspire
//
//

import SwiftUI

public extension View {
    func hidden(_ shouldHide: Bool) -> some View {
        opacity(shouldHide ? 0 : 1)
    }
}
