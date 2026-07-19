//
//  ListingCategory.swift
//  Volspire
//
//  Category label/icon resolution for collab listings. `listingCategories`
//  (CreateListingViewModel) is the canonical id → label/icon table; five call
//  sites had re-implemented this lookup, and two naive `capitalized` re-rolls
//  rendered "Mixing Mastering" instead of "Mixing / Mastering". Resolve
//  through these accessors instead.
//

import DesignSystem
import Services

extension ApiListing {
    /// Human label for `category` ("mixing_mastering" → "Mixing / Mastering").
    /// Unknown ids fall back to a de-underscored, capitalized raw id.
    var categoryLabel: String {
        listingCategories.first { $0.id == category }?.label
            ?? category.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Lucide icon for `category` (unknown ids fall back to the music note).
    var categoryIcon: LucideIcon.Name {
        listingCategories.first { $0.id == category }?.icon ?? .music
    }
}
