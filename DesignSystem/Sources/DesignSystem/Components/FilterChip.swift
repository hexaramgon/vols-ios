//
//  FilterChip.swift
//  DesignSystem
//
//  The one filter / category chip (web `FilterChip`): `Radius.panel` rounded
//  rect, 14/8 padding. On = ink fill + paper label; off = ink @ 0.05 fill +
//  ink @ 0.85 label. Use for filter rows ("All" + a few inline + More).
//

import SwiftUI

public struct FilterChip: View {
    private let title: String
    private let icon: LucideIcon.Name?
    private let isOn: Bool
    private let action: () -> Void

    public init(_ title: String, icon: LucideIcon.Name? = nil, isOn: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isOn = isOn
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { LucideIcon(icon, .sm) }
                Text(title).font(.appFootnoteMedium)
            }
            .foregroundStyle(isOn ? Color.vOnInverse : Color.inkText(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isOn ? Color.vInverse : Color.vRowActive,
                        in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

#Preview {
    HStack(spacing: 8) {
        FilterChip("All", isOn: true) {}
        FilterChip("Vocals", isOn: false) {}
        FilterChip("More", icon: .chevronDown, isOn: false) {}
    }
    .padding()
    .background(Color.vBase)
}
