//
//  TapToDismissKeyboard.swift
//  DesignSystem
//
//  App-wide "tap empty space to drop the keyboard". Descendant fields, buttons
//  and gestures always win the tap, so interactive controls are unaffected —
//  this only catches taps on otherwise-inert space. Applied centrally (the app
//  root, the auth root, and `sheetBackground()`), so every keyboard in the app
//  behaves the same; full-screen covers apply it to their own roots.
//

import SwiftUI
import UIKit

public extension View {
    /// Tapping inert space resigns the first responder (drops the keyboard).
    func tapToDismissKeyboard() -> some View {
        onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
            )
        }
    }
}
