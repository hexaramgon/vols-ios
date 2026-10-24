//
//  SegmentedControl.swift
//  DesignSystem
//
//  The app's segmented control (web `SegmentedControl`): an ink @ 0.06 capsule
//  track with 4pt padding / gap; each item is a 12/6-padded caption-medium
//  label. Active = ink fill + paper label, inactive = ink @ 0.70 label.
//  Segments can carry a Lucide glyph; when the labelled form doesn't fit the
//  width it's offered, it falls back to glyphs only.
//

import SwiftUI

public struct SegmentedControl<Value: Hashable>: View {
    public struct Segment {
        public let value: Value
        public let title: String
        public let icon: LucideIcon.Name?

        public init(_ value: Value, title: String, icon: LucideIcon.Name? = nil) {
            self.value = value
            self.title = title
            self.icon = icon
        }
    }

    @Binding private var selection: Value
    private let segments: [Segment]

    public init(selection: Binding<Value>, segments: [Segment]) {
        self._selection = selection
        self.segments = segments
    }

    public var body: some View {
        let hasIcons = segments.contains { $0.icon != nil }
        if hasIcons {
            ViewThatFits(in: .horizontal) {
                track(showTitles: true)
                track(showTitles: false)
            }
        } else {
            track(showTitles: true)
        }
    }

    private func track(showTitles: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(segments.indices, id: \.self) { index in
                item(segments[index], showTitle: showTitles)
            }
        }
        .padding(4)
        .background(Color.ink(0.06), in: Capsule())
        .fixedSize()
    }

    private func item(_ segment: Segment, showTitle: Bool) -> some View {
        let active = segment.value == selection
        return Button {
            selection = segment.value
        } label: {
            HStack(spacing: 6) {
                if let icon = segment.icon { LucideIcon(icon, .xs) }
                if showTitle || segment.icon == nil {
                    Text(segment.title).font(.appCaptionMedium)
                }
            }
            .foregroundStyle(active ? Color.vOnInverse : Color.vControlLabel)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(active ? Color.vInverse : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(segment.title)
        .accessibilityAddTraits(active ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: active)
    }
}

#Preview {
    @Previewable @State var selection = 0
    SegmentedControl(selection: $selection, segments: [
        .init(0, title: "System", icon: .monitor),
        .init(1, title: "Light", icon: .sun),
        .init(2, title: "Dark", icon: .moon),
    ])
    .padding()
    .background(Color.vBase)
}
