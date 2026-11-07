//
//  PageFooter.swift
//  Volspire
//
//  The bottom-of-list pager for infinitely scrolling lists (inbox, collab
//  board): while there's more, a spinner that fetches the next page whenever
//  it's on screen; after a failed page, a retry. Keyed on the row count, so a
//  page that adds nothing visible (a filtered list) rolls straight on to the
//  next one while the footer is still in view.
//

import DesignSystem
import SwiftUI

struct PageFooter: View {
    let hasMore: Bool
    let failed: Bool
    /// The list's current row count — a new value re-arms the fetch.
    let rowCount: Int
    let loadMore: () async -> Void

    var body: some View {
        if failed {
            Button("Couldn't load more · Retry") {
                Task { await loadMore() }
            }
            .font(.appFootnoteMedium)
            .foregroundStyle(Color.vText2)
            .frame(maxWidth: .infinity, minHeight: 56)
        } else if hasMore {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 56)
                .task(id: rowCount) { await loadMore() }
        }
    }
}
