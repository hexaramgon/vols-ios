//
//  HomeScreen+Listings.swift
//  Volspire
//
//  The Listings tab (web HomeSocialColumn / ListingsBoard): the
//  category chips (single-select — picking the active one clears it), then
//  the newest 10 listings as post cards. Saved state shows on each card's
//  bookmark (no Recent/Saved toggle any more).
//

import DesignSystem
import Services
import SwiftUI

extension HomeScreen {
    /// Every listing category, for the shared FilterBar.
    private var categoryFilterOptions: [FilterOption] {
        listingCategories.map { FilterOption(id: $0.id, label: $0.label, icon: $0.icon) }
    }

    /// How many cards a category selection shows (the tab lists the newest 10).
    private func listingCount(for filter: Set<String>) -> Int {
        let all = listingsStore.listings
        let n = filter.isEmpty ? all.count : all.filter { filter.contains($0.category) }.count
        return min(n, 10)
    }

    /// Newest 10 of the board, scoped to the picked category.
    private var listingRows: [ApiListing] {
        let all = listingsStore.listings
        let scoped = listingFilter.isEmpty ? all : all.filter { listingFilter.contains($0.category) }
        return Array(scoped.prefix(10))
    }

    var listingsTab: some View {
        tabScroll(.listings, refresh: { await viewModel.refreshListings() }) {
            VStack(alignment: .leading, spacing: 0) {
                // Categories combine: a listing in any picked one shows.
                FilterBar(
                    sectionTitle: "Categories",
                    options: categoryFilterOptions,
                    quick: ["vocalist", "producer", "beatmaker", "instrumentalist"],
                    selection: $listingFilter,
                    noun: "listings",
                    resultCount: listingCount(for:)
                )
                .padding(.bottom, 12)

                listingsContent
                    .loadingCrossfade(listingsStore.listingsLoaded)
            }
        }
    }

    @ViewBuilder
    private var listingsContent: some View {
        if !listingsStore.listingsLoaded {
            ListingPostCardSkeleton().padding(.horizontal, -8)
        } else if listingRows.isEmpty {
            HomeEmpty(title: listingFilter.isEmpty ? "No open listings"
                          : (listingFilter.count == 1 ? "Nothing in this category yet" : "Nothing in these categories yet"),
                      message: "Post what you're looking for and it shows up here.") {
                GhostListingCards()
            }
            .padding(.vertical, -8)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(listingRows.enumerated()), id: \.element.id) { i, listing in
                    ListingPostCard(listing: listing, respondInSheet: true, horizontalInset: 14).staggeredAppear(i, in: "explore.listings")
                }
            }
            // Cards run wider than the page's text column.
            .padding(.horizontal, -8)
        }
    }
}
