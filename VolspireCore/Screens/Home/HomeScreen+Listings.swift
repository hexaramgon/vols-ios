//
//  HomeScreen+Listings.swift
//  Volspire
//
//  The Listings tab (web HomeSocialColumn / ListingsBoard): the shared
//  FilterBar (Saved + categories), then the board as post cards — hottest
//  first (engagement + recency, `get_listings_feed`), loading more as you
//  scroll. Categories filter on the server; Saved swaps in your saved
//  listings (ListingsStore), narrowed by any picked categories on device.
//  Saved state also shows on each card's bookmark.
//

import DesignSystem
import Services
import SwiftUI

extension HomeScreen {
    /// Every listing category, for the shared FilterBar.
    private var categoryFilterOptions: [FilterOption] {
        listingCategories.map { FilterOption(id: $0.id, label: $0.label, icon: $0.icon) }
    }

    /// The picked categories (the selection minus Saved).
    private var pickedCategories: Set<String> { listingFilter.subtracting([FilterBar.savedId]) }
    private var showsSavedListings: Bool { listingFilter.contains(FilterBar.savedId) }

    /// The board slice for the picked categories (the whole board when none).
    private var listingPage: ListingsStore.ListingsPage { listingsStore.page(for: pickedCategories) }

    /// Saved listings in the picked categories (all of them when none).
    private var savedListingRows: [ApiListing] {
        let rows = listingsStore.savedListings
        return pickedCategories.isEmpty ? rows : rows.filter { pickedCategories.contains($0.category) }
    }

    var listingsTab: some View {
        tabScroll(.listings, refresh: { await refreshTab(.listings) }) {
            VStack(alignment: .leading, spacing: 0) {
                // Categories combine: a listing in any picked one shows.
                FilterBar(
                    sectionTitle: "Categories",
                    options: categoryFilterOptions,
                    quick: ["vocalist", "producer", "beatmaker", "instrumentalist"],
                    showsSaved: true,
                    selection: $listingFilter,
                    noun: "listings"
                )
                .padding(.bottom, 12)
                // Category filtering is server-side (the board pages) — fetch
                // the picked categories' first page. (Saved filters on device.)
                .onChange(of: listingFilter) { _, picked in
                    Task { await listingsStore.setFilter(picked.subtracting([FilterBar.savedId])) }
                }
                .task { await listingsStore.loadSavedIfNeeded() }

                if showsSavedListings {
                    savedListingsContent
                        .loadingCrossfade(listingsStore.savedListingsLoaded)
                } else {
                    listingsContent
                        .loadingCrossfade(listingPage.loaded)
                }
            }
        }
    }

    /// The Saved filter: your saved listings (in the picked categories), as
    /// the board's cards. Un-saving one drops it here in place.
    @ViewBuilder
    private var savedListingsContent: some View {
        if !listingsStore.savedListingsLoaded && listingsStore.savedListingsFailed {
            LoadErrorView(icon: .bookmark, title: "Couldn't load saved listings") {
                Task { await listingsStore.refreshSaved() }
            }
            .padding(.top, 40)
        } else if !listingsStore.savedListingsLoaded {
            ListingPostCardSkeleton().padding(.horizontal, -8)
        } else if savedListingRows.isEmpty {
            HomeEmpty(title: pickedCategories.isEmpty ? "No saved listings" : "No saved listings here",
                      message: "Tap the bookmark on a listing to keep it here.") {
                GhostListingCards()
            }
            .padding(.vertical, -8)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(savedListingRows.enumerated()), id: \.element.id) { i, listing in
                    ListingPostCard(listing: listing, respondInSheet: true, horizontalInset: 14,
                                    showsMatch: !pickedCategories.isEmpty).staggeredAppear(i, in: "explore.savedListings")
                }
            }
            .padding(.horizontal, -8)
            .animation(.easeInOut(duration: 0.25), value: savedListingRows.map(\.listingId))
        }
    }

    @ViewBuilder
    private var listingsContent: some View {
        let page = listingPage
        if page.failed && page.rows.isEmpty {
            LoadErrorView(icon: .megaphone, title: "Couldn't load listings") {
                Task { await refreshTab(.listings) }
            }
            .padding(.top, 40)
        } else if !page.loaded {
            ListingPostCardSkeleton().padding(.horizontal, -8)
        } else if page.rows.isEmpty {
            HomeEmpty(title: pickedCategories.isEmpty ? "No open listings"
                          : (pickedCategories.count == 1 ? "Nothing in this category yet" : "Nothing in these categories yet"),
                      message: "Post what you're looking for and it shows up here.") {
                GhostListingCards()
            }
            .padding(.vertical, -8)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(Array(page.rows.enumerated()), id: \.element.id) { i, listing in
                    ListingPostCard(listing: listing, respondInSheet: true, horizontalInset: 14,
                                    showsMatch: !pickedCategories.isEmpty).staggeredAppear(i, in: "explore.listings")
                }
                PageFooter(hasMore: page.hasMore, failed: page.pageFailed, rowCount: page.rows.count) {
                    await listingsStore.loadMore(categories: pickedCategories)
                }
            }
            // Cards run wider than the page's text column.
            .padding(.horizontal, -8)
        }
    }
}
