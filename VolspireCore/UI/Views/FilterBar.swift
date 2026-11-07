//
//  FilterBar.swift
//  Volspire
//
//  THE filter control (Facebook Marketplace pattern), used by every chip
//  filter in the app — Listings categories, Collab roles (map + nearby):
//  - A row: a "Filters" button (count badge when any are on), "Clear all"
//    while any are on, then the active filters as ink chips with an ✕ (tap
//    to remove), then a few quick options to toggle in one tap.
//  - "Filters" opens a sheet with every option as a toggle chip. Choices are a
//    draft until "Show N …" applies them; Reset clears the draft.
//  - Listings and Marketplace only (`showsSaved`): a "Saved" chip leads the
//    row and gets its own "Show" section in the sheet, sharing the one
//    selection set (`FilterBar.savedId`). No other filter offers it.
//  Multi-select throughout; an empty selection means "everything".
//

import DesignSystem
import SwiftUI

struct FilterOption: Identifiable, Hashable {
    let id: String
    let label: String
    var icon: LucideIcon.Name? = nil
}

struct FilterBar: View {
    /// The sheet's section heading ("Categories", "Roles").
    let sectionTitle: String
    let options: [FilterOption]
    /// Option ids offered inline as one-tap chips (the rest live in the sheet).
    let quick: [String]
    /// The Listings / Marketplace "Saved" chip — leave off everywhere else.
    var showsSaved = false

    /// The Saved chip's id in `selection` (Listings / Marketplace only).
    static let savedId = "saved"
    private var pinned: [FilterOption] {
        showsSaved ? [FilterOption(id: Self.savedId, label: "Saved", icon: .bookmark)] : []
    }
    @Binding var selection: Set<String>
    /// Plural noun for the apply button ("listings", "artists").
    var noun = "results"
    /// How many results a draft selection would show — nil when unknown
    /// (server-filtered), and the button just says "Show results".
    var resultCount: ((Set<String>) -> Int)? = nil
    /// The page's side padding: the row then scrolls edge to edge while its
    /// first chip still lines up with the page column.
    var edgeInset: CGFloat = 0

    @State private var showSheet = false

    private var selectedOptions: [FilterOption] { (pinned + options).filter { selection.contains($0.id) } }
    private var quickOptions: [FilterOption] {
        (pinned + quick.compactMap { id in options.first { $0.id == id } }).filter { !selection.contains($0.id) }
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filtersButton
                if !selection.isEmpty { clearButton }
                ForEach(selectedOptions) { o in activeChip(o) }
                ForEach(quickOptions) { o in
                    FilterChip(o.label, icon: o.icon, isOn: false) { toggle(o.id) }
                }
            }
        }
        .scrollClipDisabled()
        .contentMargins(.horizontal, edgeInset, for: .scrollContent)
        .padding(.horizontal, -edgeInset)
        // Sideways chip scrolling wins over Explore's tab swipe.
        .excludesTabSwipe()
        .animation(.smooth(duration: 0.22), value: selection)
        .sheet(isPresented: $showSheet) {
            FilterSheet(sectionTitle: sectionTitle, options: options, pinned: pinned, initial: selection,
                        noun: noun, resultCount: resultCount) { applied in
                selection = applied
            }
        }
    }

    private func toggle(_ id: String) {
        Haptics.selection()
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// "Filters" with a sliders glyph; ink + count badge when any are on.
    private var filtersButton: some View {
        let count = selection.count
        return Button { showSheet = true } label: {
            HStack(spacing: 6) {
                LucideIcon(.slidersHorizontal, .sm)
                Text("Filters").font(.appFootnoteMedium)
                if count > 0 {
                    Text("\(count)")
                        .font(.appMicroBold)
                        .monospacedDigit()
                        .foregroundStyle(Color.vOnColor)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.vAccent, in: Circle())
                }
            }
            .foregroundStyle(count > 0 ? Color.vOnInverse : Color.inkText(0.85))
            .padding(.leading, 14)
            .padding(.trailing, count > 0 ? 8 : 14)
            .padding(.vertical, 8)
            .background(count > 0 ? Color.vInverse : Color.vRowActive,
                        in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count > 0 ? "Filters, \(count) on" : "Filters")
    }

    /// "Clear all" — right next to Filters whenever any are on, so resetting
    /// never means hunting for chips. Plain secondary text, no fill, so it
    /// reads as an action rather than another filter.
    private var clearButton: some View {
        Button {
            Haptics.selection()
            selection = []
        } label: {
            Text("Clear all")
                .font(.appFootnoteSemibold)
                .foregroundStyle(Color.vText2)
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .transition(.opacity)
        .accessibilityLabel("Clear all filters")
    }

    /// An applied filter: ink chip with an ✕ — tap to remove it.
    private func activeChip(_ o: FilterOption) -> some View {
        Button { toggle(o.id) } label: {
            HStack(spacing: 6) {
                if let icon = o.icon { LucideIcon(icon, .sm) }
                Text(o.label).font(.appFootnoteMedium)
                LucideIcon(.x, .sm)
            }
            .foregroundStyle(Color.vOnInverse)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.vInverse, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
            .contentShape(.rect(cornerRadius: Radius.panel))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .accessibilityLabel("Remove \(o.label) filter")
    }
}

// MARK: - Sheet

/// Every option as a toggle chip; a draft until "Show N …" applies it.
private struct FilterSheet: View {
    let sectionTitle: String
    let options: [FilterOption]
    let pinned: [FilterOption]
    let initial: Set<String>
    let noun: String
    let resultCount: ((Set<String>) -> Int)?
    let onApply: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: Set<String>

    init(sectionTitle: String, options: [FilterOption], pinned: [FilterOption], initial: Set<String>, noun: String,
         resultCount: ((Set<String>) -> Int)?, onApply: @escaping (Set<String>) -> Void) {
        self.sectionTitle = sectionTitle
        self.options = options
        self.pinned = pinned
        self.initial = initial
        self.noun = noun
        self.resultCount = resultCount
        self.onApply = onApply
        _draft = State(initialValue: initial)
    }

    private var applyTitle: String {
        guard let resultCount else { return "Show \(noun)" }
        let n = resultCount(draft)
        return "Show \(n) \(noun)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeader(icon: .slidersHorizontal, title: "Filters",
                        subtitle: "Pick as many as you like") { dismiss() }

            if !pinned.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Show")
                        .font(.appFont.sectionLabel)
                        .foregroundStyle(Color.vText3)
                    chips(pinned)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(sectionTitle)
                        .font(.appFont.sectionLabel)
                        .foregroundStyle(Color.vText3)
                    Spacer(minLength: 0)
                    if !draft.isEmpty {
                        Text("\(draft.count) selected")
                            .font(.appCaption)
                            .foregroundStyle(Color.vText3)
                            .monospacedDigit()
                    }
                }
                chips(options)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            HStack(spacing: 10) {
                SecondaryButton("Reset", size: .inline, enabled: !draft.isEmpty) { draft = [] }
                PrimaryButton(applyTitle, size: .inline) {
                    onApply(draft)
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 20)
        }
        .animation(.smooth(duration: 0.18), value: draft)
        .selfSizedDetent()
        .sheetBackground()
    }

    private func chips(_ list: [FilterOption]) -> some View {
        ChipFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(list) { o in
                FilterChip(o.label, icon: o.icon, isOn: draft.contains(o.id)) {
                    Haptics.selection()
                    if draft.contains(o.id) { draft.remove(o.id) } else { draft.insert(o.id) }
                }
            }
        }
    }
}
