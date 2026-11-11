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

enum ListingCategory {
    /// Human label for a category id ("mixing_mastering" → "Mixing / Mastering").
    /// Unknown ids fall back to a de-underscored, capitalized raw id.
    static func label(_ id: String) -> String {
        listingCategories.first { $0.id == id }?.label
            ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Lucide icon for a category id (unknown ids fall back to the music note).
    static func icon(_ id: String) -> LucideIcon.Name {
        listingCategories.first { $0.id == id }?.icon ?? .music
    }
}

extension ApiListing {
    var categoryLabel: String { ListingCategory.label(category) }
    var categoryIcon: LucideIcon.Name { ListingCategory.icon(category) }
}
