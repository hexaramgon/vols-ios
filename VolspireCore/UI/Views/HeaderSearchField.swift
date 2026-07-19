//
//  HeaderSearchField.swift
//  Volspire
//
//  The tab-root header's reveal-search row — the 42pt icon/TextField/clear
//  field plus the Cancel button that hides it again. Library and Inbox carried
//  line-for-line copies; the header icon's reveal action (animate the flag,
//  focus after the reveal lands) stays with the caller, which owns the flag
//  and @FocusState.
//

import DesignSystem
import SwiftUI

struct HeaderSearchField: View {
    let prompt: String
    @Binding var text: String
    /// The header's reveal flag — Cancel animates it back down and clears.
    @Binding var isRevealed: Bool
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 12) {
            field
            Button("Cancel") {
                focus.wrappedValue = false
                withAnimation(.easeInOut(duration: 0.2)) { isRevealed = false }
                text = ""
            }
            .font(.appCallout)
            .foregroundStyle(.white)
        }
        .padding(.horizontal, ViewConst.screenPaddings)
        .padding(.bottom, 12)
    }

    private var field: some View {
        HStack(spacing: 10) {
            LucideIcon(.search, .md).foregroundStyle(Color.vText3)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(Color.vText3))
                .font(.appCallout)
                .foregroundStyle(.white)
                .tint(.white)
                .focused(focus)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    LucideIcon(.circleX, .md)
                        .foregroundStyle(Color.vText3)
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        // Fixed height — the clear button (28pt) appearing once you type must
        // not grow the field.
        .frame(height: 42)
        .background(Color.vSurface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.vBorder, lineWidth: 1))
    }
}
